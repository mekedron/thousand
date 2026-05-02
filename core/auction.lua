-- The Thousand auction state machine.
--
-- Phase 1.3 of the engine: the bidding phase. Forehand (left of the
-- dealer) acts first and the turn proceeds clockwise. On each turn a
-- player may either place a bid strictly higher than the current bid
-- or pass for good. The auction terminates the moment all-but-one
-- player has passed; the remaining player becomes declarer at their
-- final bid. If no one ever bid, the auction terminates as "all_pass"
-- with no declarer — Phase 3 toggles will decide what that means
-- (распасы, redeal, ...) without changing this module.
--
-- Phase 3.6 bidding-house-rules wired nine optional toggles in:
--   * `forced_opening`               — forehand cannot pass round 1.
--   * `forced_dealer_bid`            — dealer takes 100 on all-pass.
--   * `blind_bid`                    — record a first action as blind;
--                                       scoring later applies the
--                                       multiplier on win/loss.
--   * `re_entry_after_pass`          — passed seat may re-enter once.
--   * `contra` / `_and_redouble`     — post-finalize doubling phase.
--   * `no_contract_without_marriage` — bid cap from declared marriage
--                                       holdings.
--   * `negative_score_restriction`   — locks negative-score seats out
--                                       of bidding.
--   * `named_contracts`              — accept structured named-bid
--                                       amounts; numeric overcalls
--                                       are illegal once a named bid
--                                       leads.
-- The marriage cap and lock rules need extra context the auction
-- alone cannot derive from RuleConfig. The session passes them via
-- the optional `opts.holdings` and `opts.running_totals` arguments to
-- `M.new`; all other rules read pure RuleConfig.
--
-- Rule constants (opening minimum, pre-talon maximum, increment
-- thresholds, player count) are read from `RuleConfig`. Phase 1 ships
-- the canonical Russian config; future variants change rules through
-- data, not code.
--
-- API shape mirrors core.dealing: every function returns either
--   { ok = true, auction = next_state }
-- or
--   { ok = false, error = { code, message, ...extra } }.
-- Transitions never mutate the input auction; they return a new
-- state. The state itself is a plain readable Lua table sealed with a
-- protected `__metatable` so `M.is_auction` can recognise it (the
-- same pattern rule_config uses for `is_rule_config`).

local rule_config = require("core.rule_config")

local M = {}

M.SCHEMA_VERSION = 1

local AUCTION_TYPE = "thousand.auction"

local function failure(code, message, extra)
    local err = { code = code, message = message }
    if extra then
        for k, v in pairs(extra) do
            err[k] = v
        end
    end
    return { ok = false, error = err }
end

local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

local function is_valid_player(value, player_count)
    return is_integer(value) and value >= 1 and value <= player_count
end

local function tag_as_auction(state)
    return setmetatable(state, { __metatable = AUCTION_TYPE })
end

local function copy_bool_array(arr)
    local copy = {}
    for i = 1, #arr do
        copy[i] = arr[i]
    end
    return copy
end

local function clone_amount(amount)
    if type(amount) == "table" then
        return {
            kind = amount.kind,
            contract = amount.contract,
            value = amount.value,
        }
    end
    return amount
end

local function clone_history_entry(entry)
    return {
        player = entry.player,
        action = entry.action,
        amount = clone_amount(entry.amount),
        blind = entry.blind,
        re_entry = entry.re_entry,
    }
end

local function copy_history(history)
    local copy = {}
    for i = 1, #history do
        copy[i] = clone_history_entry(history[i])
    end
    return copy
end

local function clone_doubling(d)
    if d == nil then
        return nil
    end
    local pending = {}
    for i = 1, #d.pending_seats do
        pending[i] = d.pending_seats[i]
    end
    return {
        multiplier = d.multiplier,
        contra_by = d.contra_by,
        redouble_by = d.redouble_by,
        pending_seats = pending,
        redouble_open = d.redouble_open,
    }
end

local function clone_state(state)
    return {
        schema_version = state.schema_version,
        config = state.config,
        dealer = state.dealer,
        forehand = state.forehand,
        player_count = state.player_count,
        sits_out = state.sits_out,
        turn = state.turn,
        current_bid = clone_amount(state.current_bid),
        current_leader = state.current_leader,
        passed = copy_bool_array(state.passed),
        pass_count = state.pass_count,
        re_entered = copy_bool_array(state.re_entered),
        blind = copy_bool_array(state.blind),
        locked = copy_bool_array(state.locked),
        holdings = state.holdings,
        running_totals = state.running_totals,
        doubling = clone_doubling(state.doubling),
        dealer_forced = state.dealer_forced,
        blind_at_win = state.blind_at_win,
        status = state.status,
        declarer = state.declarer,
        final_bid = clone_amount(state.final_bid),
        history = copy_history(state.history),
    }
end

local function append_history(history, entry)
    local copy = copy_history(history)
    copy[#copy + 1] = clone_history_entry(entry)
    return copy
end

-- Walk clockwise from `from` and return the next seat whose `passed`
-- flag is false. The caller is responsible for only invoking this when
-- the auction is still in progress, so at least one such seat exists.
local function next_active_seat(passed, from, player_count)
    local seat = from
    for _ = 1, player_count do
        seat = (seat % player_count) + 1
        if not passed[seat] then
            return seat
        end
    end
    error("auction: no active seats remain — invariant violated")
end

-- The seat (if any) that is excluded from the auction for this deal.
-- 4-player Configuration B has the dealer sit out — they never bid and
-- never become declarer. Other layouts return nil so every seat
-- participates.
local function compute_sits_out(config, dealer)
    if config.players.count == 4 and config.players.four_player_config == "dealer_sits_out" then
        return dealer
    end
    return nil
end

-- Decide whether the just-finalized declarer triggers a `doubling`
-- sub-phase. Mutates `state` in place by setting `status`, `turn`,
-- and (when applicable) `doubling`.
local function open_doubling_or_done(state)
    local final_is_named = type(state.final_bid) == "table"
    if state.config.bidding.contra ~= "off" and not final_is_named then
        local pending = {}
        local seat = state.forehand
        for _ = 1, state.player_count do
            if seat ~= state.declarer and not (state.sits_out and seat == state.sits_out) then
                pending[#pending + 1] = seat
            end
            seat = (seat % state.player_count) + 1
        end
        state.doubling = {
            multiplier = 1,
            contra_by = nil,
            redouble_by = nil,
            pending_seats = pending,
            redouble_open = false,
        }
        state.status = "doubling"
        state.turn = pending[1]
    else
        state.status = "done"
        state.turn = nil
    end
end

-- Set declarer / final_bid (numeric or named-contract winner path),
-- compute blind_at_win, then transition to `doubling` or `done`.
local function finalize_with_winner(state)
    if state.declarer == nil then
        state.declarer = state.current_leader
        state.final_bid = clone_amount(state.current_bid)
    end
    if type(state.final_bid) == "number" and state.blind[state.declarer] then
        state.blind_at_win = true
    end
    open_doubling_or_done(state)
end

-- Three-way termination when a pass leaves only one (or zero) active
-- seats: numeric-winner / forced-dealer-bid / all-pass. Mutates
-- `state` in place.
local function finalize_after_pass(state)
    if state.current_bid ~= nil then
        finalize_with_winner(state)
        return
    end
    local bidding = state.config.bidding
    if
        bidding.forced_dealer_bid == "on"
        and not state.locked[state.dealer]
        and not (state.sits_out and state.sits_out == state.dealer)
    then
        state.declarer = state.dealer
        state.final_bid = bidding.opening_min
        state.dealer_forced = true
        state.history[#state.history + 1] = {
            player = state.dealer,
            action = "forced_dealer_bid",
            amount = bidding.opening_min,
        }
        finalize_with_winner(state)
        return
    end
    state.status = "all_pass"
    state.turn = nil
end

function M.new(config, dealer, opts)
    if not rule_config.is_rule_config(config) then
        return failure("not_a_rule_config", "auction.new requires a RuleConfig", {
            actual = type(config),
        })
    end
    local player_count = config.players.count
    if not is_valid_player(dealer, player_count) then
        return failure(
            "bad_dealer_position",
            "dealer must be an integer in 1.." .. player_count,
            { actual = dealer, player_count = player_count }
        )
    end

    opts = opts or {}
    local holdings = opts.holdings
    local running_totals = opts.running_totals

    local sits_out = compute_sits_out(config, dealer)
    local forehand = (dealer % player_count) + 1
    local passed = {}
    local re_entered = {}
    local blind = {}
    local locked = {}
    local pass_count = 0

    local lock_active = config.bidding.negative_score_restriction == "on" and running_totals ~= nil

    for i = 1, player_count do
        re_entered[i] = false
        blind[i] = false
        -- Locked seats keep their turn — the rule lets them accept the
        -- forced minimum-100 contract or pass; it does not remove them
        -- from the auction. The locked flag drives view-model gating
        -- and the validate_bid_amount check below.
        locked[i] = lock_active and (running_totals[i] or 0) < 0 or false
        if sits_out and i == sits_out then
            passed[i] = true
            pass_count = pass_count + 1
        else
            passed[i] = false
        end
    end

    local turn
    if pass_count < player_count then
        if passed[forehand] then
            turn = next_active_seat(passed, forehand, player_count)
        else
            turn = forehand
        end
    end

    local state = tag_as_auction({
        schema_version = M.SCHEMA_VERSION,
        config = config,
        dealer = dealer,
        forehand = forehand,
        player_count = player_count,
        sits_out = sits_out,
        turn = turn,
        current_bid = nil,
        current_leader = nil,
        passed = passed,
        pass_count = pass_count,
        re_entered = re_entered,
        blind = blind,
        locked = locked,
        holdings = holdings,
        running_totals = running_totals,
        doubling = nil,
        dealer_forced = false,
        blind_at_win = false,
        status = "in_progress",
        declarer = nil,
        final_bid = nil,
        history = {},
    })

    -- Edge case: every seat is locked or sits-out at construction. The
    -- auction has nobody to act — finalize immediately. With no bids
    -- and no eligible dealer this collapses to all_pass; the locked-
    -- dealer guard in finalize_after_pass keeps forced_dealer_bid from
    -- forcing a digging-deeper-into-negative declaration.
    if pass_count >= player_count then
        finalize_after_pass(state)
    end

    return { ok = true, auction = state }
end

function M.is_auction(value)
    if type(value) ~= "table" then
        return false
    end
    return getmetatable(value) == AUCTION_TYPE
end

-- Round number the auction is currently in. Round 1 spans the first
-- action (bid or pass) by each active seat; round 2 begins after every
-- active seat has acted once. Returns 1 on a freshly-constructed
-- auction (no history yet). The `flip_after_first_round` talon rule
-- reads this to decide whether the talon stays closed during round 1.
-- Locked seats (negative_score_restriction) are excluded from the
-- active count just like sits_out seats. Doubling-phase actions
-- (`contra`, `redouble`, `skip_contra`, `forced_dealer_bid`) are
-- ignored — only `bid` and `pass` advance the bidding round counter.
-- Pure: no RuleConfig lookup, no mutation.
function M.round_number(state)
    if not M.is_auction(state) then
        return failure("not_an_auction", "first argument is not an auction", {
            actual = type(state),
        })
    end
    local active_seat_count = state.player_count - (state.sits_out and 1 or 0)
    if state.locked then
        for i = 1, state.player_count do
            if state.locked[i] then
                active_seat_count = active_seat_count - 1
            end
        end
    end
    if active_seat_count <= 0 then
        return { ok = true, round = 1 }
    end
    local action_count = 0
    for i = 1, #state.history do
        local action = state.history[i].action
        if action == "bid" or action == "pass" then
            action_count = action_count + 1
        end
    end
    local round = math.floor(action_count / active_seat_count) + 1
    return { ok = true, round = round }
end

local function ensure_in_progress(auction)
    if not M.is_auction(auction) then
        return failure("not_an_auction", "first argument is not an auction", {
            actual = type(auction),
        })
    end
    if auction.status ~= "in_progress" then
        return failure(
            "auction_already_done",
            "auction has already terminated",
            { status = auction.status }
        )
    end
    return nil
end

-- Locked seats are still on turn, but their only legal bid is the
-- opening minimum (and pass remains available). The check fires inside
-- validate_bid_amount for bids; bid_re_entry calls this directly for
-- the (rare) re-entry case.
local function check_locked_bid(auction, player, amount)
    if not auction.locked or not auction.locked[player] then
        return nil
    end
    if amount ~= auction.config.bidding.opening_min then
        return failure(
            "negative_score_locked",
            "this seat is locked at the forced minimum-100 contract",
            {
                player = player,
                amount = amount,
                opening_min = auction.config.bidding.opening_min,
            }
        )
    end
    return nil
end

local function validate_actor(state, player)
    if not is_valid_player(player, state.player_count) then
        return failure(
            "bad_player",
            "player must be an integer in 1.." .. state.player_count,
            { actual = player, player_count = state.player_count }
        )
    end
    if player ~= state.turn then
        return failure(
            "not_your_turn",
            "it is not this player's turn to act",
            { player = player, turn = state.turn }
        )
    end
    return nil
end

local function validate_pass(state, player)
    if
        state.config.bidding.forced_opening == "on"
        and player == state.forehand
        and #state.history == 0
    then
        return failure("forced_opening", "forehand must open at the minimum bid", {
            forehand = state.forehand,
            opening_min = state.config.bidding.opening_min,
        })
    end
    return nil
end

-- Search history for any prior action by `player`. Used to gate blind-
-- bid eligibility (only legal on the seat's first action this auction).
local function player_has_acted(history, player)
    for i = 1, #history do
        if history[i].player == player then
            return true
        end
    end
    return false
end

local function validate_blind(auction, player)
    if auction.config.bidding.blind_bid == "off" then
        return failure("blind_bid_disabled", "blind bidding is not enabled", {})
    end
    if player_has_acted(auction.history, player) then
        return failure("blind_after_first_action", "blind only legal on first action", {
            player = player,
        })
    end
    return nil
end

local function validate_bid_amount(state, player, amount)
    if not is_integer(amount) then
        return failure("bid_not_integer", "bid amount must be an integer", {
            actual = amount,
        })
    end

    local bidding = state.config.bidding
    if state.current_bid == nil then
        if amount < bidding.opening_min then
            return failure(
                "bid_below_minimum",
                "opening bid must be at least " .. bidding.opening_min,
                { amount = amount, min = bidding.opening_min }
            )
        end
    else
        if amount <= state.current_bid then
            return failure(
                "bid_not_higher",
                "bid must be strictly higher than the current bid",
                { amount = amount, current_bid = state.current_bid }
            )
        end
    end

    local step
    if amount < bidding.increment_threshold then
        step = bidding.increment_below_200
    else
        step = bidding.increment_from_200
    end
    if amount % step ~= 0 then
        return failure(
            "bad_bid_increment",
            "bid amount must respect the increment rule",
            { amount = amount, step = step }
        )
    end

    if amount > bidding.pre_talon_max then
        return failure(
            "bid_above_pre_talon_max",
            "bid above pre-talon maximum " .. bidding.pre_talon_max,
            { amount = amount, max = bidding.pre_talon_max }
        )
    end

    -- negative_score_restriction: locked seats may only bid the
    -- opening minimum. Pass remains available. The check is here so
    -- the bid validator surfaces the right error for any bid above
    -- the floor.
    if state.locked and state.locked[player] and amount ~= bidding.opening_min then
        return failure(
            "negative_score_locked",
            "this seat is locked at the forced minimum-100 contract",
            {
                player = player,
                amount = amount,
                opening_min = bidding.opening_min,
            }
        )
    end

    -- no_contract_without_marriage caps the bid based on the player's
    -- starting marriage holdings. The session passes the derived
    -- holdings into M.new; tests that build auctions in isolation can
    -- omit `opts.holdings` and the rule is then inert.
    local mc_mode = bidding.no_contract_without_marriage
    if mc_mode ~= "off" and state.holdings and state.holdings[player] then
        local marriage_total = state.holdings[player].marriage_total or 0
        if mc_mode == "no_120_without_marriage" then
            if amount >= 120 and marriage_total == 0 then
                return failure(
                    "needs_marriage_for_120",
                    "bids 120 and above require a marriage in hand",
                    {
                        player = player,
                        amount = amount,
                        marriage_total = marriage_total,
                    }
                )
            end
        elseif mc_mode == "capped_by_marriages" then
            local cap = 120 + marriage_total
            if amount > cap then
                return failure("bid_above_marriage_cap", "bid above marriage-derived cap", {
                    player = player,
                    amount = amount,
                    cap = cap,
                    marriage_total = marriage_total,
                })
            end
        end
    end

    return nil
end

-- Map a named-contract `kind` to the specials toggle that gates it.
-- The schema uses `slam_contract` as the toggle name but the canonical
-- `kind` (and the UI / locale strings) use `slam`.
local function specials_toggle_for(kind)
    if kind == "mizere" then
        return "mizere"
    end
    if kind == "slam" then
        return "slam_contract"
    end
    if kind == "open_hand" then
        return "open_hand"
    end
    return nil
end

local function validate_named_amount(auction, amount)
    if amount.kind ~= "named" then
        return failure("type_mismatch", "structured bid amount requires kind = 'named'", {
            actual_kind = amount.kind,
        })
    end
    if type(amount.contract) ~= "string" then
        return failure("type_mismatch", "named bid requires a string contract", {
            actual = type(amount.contract),
        })
    end
    if not is_integer(amount.value) then
        return failure("type_mismatch", "named bid requires an integer value", {
            actual = type(amount.value),
        })
    end
    local bidding = auction.config.bidding
    if bidding.named_contracts ~= "on" then
        return failure("named_contracts_disabled", "named contracts not enabled", {})
    end
    local toggle = specials_toggle_for(amount.contract)
    if not toggle then
        return failure("unknown_named_contract", "unknown named contract", {
            contract = amount.contract,
        })
    end
    if auction.config.specials[toggle] ~= "on" then
        return failure("unknown_named_contract", "specials toggle for this contract is off", {
            contract = amount.contract,
            toggle = toggle,
        })
    end
    return nil
end

local function bid_named(auction, player, amount, opts)
    local err = validate_named_amount(auction, amount)
    if err then
        return err
    end
    if type(auction.current_bid) == "table" then
        return failure(
            "cannot_overcall_named",
            "named-over-named overcalls are not yet supported",
            {
                current_named = auction.current_bid.contract,
                new_named = amount.contract,
            }
        )
    end
    if opts.blind then
        return failure("blind_named_not_supported", "named bids cannot be declared blind", {})
    end

    local next_state = clone_state(auction)
    next_state.current_bid = clone_amount(amount)
    next_state.current_leader = player
    next_state.history = append_history(auction.history, {
        player = player,
        action = "bid_named",
        amount = next_state.current_bid,
    })
    next_state.turn = next_active_seat(next_state.passed, player, next_state.player_count)
    return { ok = true, auction = tag_as_auction(next_state) }
end

function M.bid(auction, player, amount, opts)
    local progress_err = ensure_in_progress(auction)
    if progress_err then
        return progress_err
    end
    local actor_err = validate_actor(auction, player)
    if actor_err then
        return actor_err
    end
    if type(amount) == "number" then
        local locked_err = check_locked_bid(auction, player, amount)
        if locked_err then
            return locked_err
        end
    end

    opts = opts or {}

    -- Structured named-contract bids dispatch to a separate path.
    -- Only well-formed tables with kind="named" are recognised; any
    -- other table value falls through to the numeric path and gets
    -- rejected as a non-integer bid (preserves the existing
    -- bid_not_integer contract for malformed amounts).
    if type(amount) == "table" and amount.kind == "named" then
        return bid_named(auction, player, amount, opts)
    end

    -- Numeric bid path. Reject overcalls of a named contract leader.
    if type(auction.current_bid) == "table" then
        return failure(
            "cannot_overcall_named",
            "cannot place a numeric bid over a named contract",
            { current_named = auction.current_bid.contract, amount = amount }
        )
    end

    local amount_err = validate_bid_amount(auction, player, amount)
    if amount_err then
        return amount_err
    end

    if opts.blind then
        local blind_err = validate_blind(auction, player)
        if blind_err then
            return blind_err
        end
    end

    local next_state = clone_state(auction)
    next_state.current_bid = amount
    next_state.current_leader = player
    if opts.blind then
        next_state.blind[player] = true
    end
    next_state.history = append_history(auction.history, {
        player = player,
        action = "bid",
        amount = amount,
        blind = opts.blind or nil,
    })
    next_state.turn = next_active_seat(next_state.passed, player, next_state.player_count)
    return { ok = true, auction = tag_as_auction(next_state) }
end

-- Out-of-turn re-entry by a previously-passed seat. Gated on
-- `bidding.re_entry_after_pass = "on"`; each seat may exercise its
-- single re-entry once. Re-entry is closed once the auction leaves
-- `in_progress` (e.g. enters `doubling`).
function M.bid_re_entry(auction, player, amount, opts)
    local progress_err = ensure_in_progress(auction)
    if progress_err then
        return progress_err
    end
    local bidding = auction.config.bidding
    if bidding.re_entry_after_pass ~= "on" then
        return failure("re_entry_disabled", "re-entry after pass is not enabled", {})
    end
    if not is_valid_player(player, auction.player_count) then
        return failure(
            "bad_player",
            "player must be an integer in 1.." .. auction.player_count,
            { actual = player, player_count = auction.player_count }
        )
    end
    if not auction.passed[player] then
        return failure("not_passed", "this seat has not passed; use M.bid", {
            player = player,
        })
    end
    if auction.locked and auction.locked[player] then
        return failure(
            "negative_score_locked",
            "locked seats may not re-enter the auction",
            { player = player }
        )
    end
    if auction.re_entered[player] then
        return failure(
            "already_re_entered",
            "this seat has already used its single re-entry",
            { player = player }
        )
    end
    if auction.current_bid == nil then
        return failure("no_bid_to_overcall", "re-entry requires a current bid to overcall", {})
    end
    if type(auction.current_bid) == "table" then
        return failure(
            "cannot_overcall_named",
            "cannot re-enter on a named contract",
            { current_named = auction.current_bid.contract }
        )
    end

    if type(amount) == "table" then
        return failure("re_entry_named_not_supported", "re-entry must overcall numerically", {})
    end

    local amount_err = validate_bid_amount(auction, player, amount)
    if amount_err then
        return amount_err
    end

    opts = opts or {}

    local next_state = clone_state(auction)
    next_state.passed[player] = false
    next_state.pass_count = next_state.pass_count - 1
    next_state.re_entered[player] = true
    next_state.current_bid = amount
    next_state.current_leader = player
    next_state.history = append_history(auction.history, {
        player = player,
        action = "bid",
        amount = amount,
        re_entry = true,
        blind = opts.blind or nil,
    })
    if opts.blind then
        -- Re-entry can be blind only if the player's prior passes did
        -- not reveal their hand. The session is responsible for
        -- enforcing the curtain semantics; the engine just records
        -- the flag. (validate_blind would reject because the player
        -- has acted before — re-entry intentionally bypasses that
        -- check.)
        if bidding.blind_bid == "off" then
            return failure("blind_bid_disabled", "blind bidding is not enabled", {})
        end
        next_state.blind[player] = true
    end
    next_state.turn = next_active_seat(next_state.passed, player, next_state.player_count)
    return { ok = true, auction = tag_as_auction(next_state) }
end

function M.pass(auction, player, opts)
    local progress_err = ensure_in_progress(auction)
    if progress_err then
        return progress_err
    end
    local actor_err = validate_actor(auction, player)
    if actor_err then
        return actor_err
    end
    local pass_err = validate_pass(auction, player)
    if pass_err then
        return pass_err
    end

    opts = opts or {}
    if opts.blind then
        local blind_err = validate_blind(auction, player)
        if blind_err then
            return blind_err
        end
    end

    local next_state = clone_state(auction)
    next_state.passed[player] = true
    next_state.pass_count = next_state.pass_count + 1
    if opts.blind then
        next_state.blind[player] = true
    end
    next_state.history = append_history(auction.history, {
        player = player,
        action = "pass",
        blind = opts.blind or nil,
    })

    if next_state.pass_count >= next_state.player_count - 1 then
        finalize_after_pass(next_state)
    else
        next_state.turn = next_active_seat(next_state.passed, player, next_state.player_count)
    end
    return { ok = true, auction = tag_as_auction(next_state) }
end

local function ensure_doubling(auction)
    if not M.is_auction(auction) then
        return failure("not_an_auction", "first argument is not an auction", {
            actual = type(auction),
        })
    end
    if auction.status ~= "doubling" then
        return failure("wrong_phase", "doubling-phase action requires status='doubling'", {
            status = auction.status,
        })
    end
    return nil
end

local function defender_index(pending, player)
    for i = 1, #pending do
        if pending[i] == player then
            return i
        end
    end
    return nil
end

-- Defender doubles the contract value. Multiplier picks up the
-- configured `bidding.contra_multiplier` (default 2). Subsequent
-- contras by other defenders are not allowed; the queue drains.
function M.contra(auction, player)
    local err = ensure_doubling(auction)
    if err then
        return err
    end
    if not is_valid_player(player, auction.player_count) then
        return failure("bad_player", "...", { actual = player })
    end
    if defender_index(auction.doubling.pending_seats, player) == nil then
        return failure("bad_actor", "this seat is not eligible to declare contra", {
            player = player,
            declarer = auction.declarer,
        })
    end
    if auction.doubling.multiplier > 1 then
        return failure("already_contra", "contra already declared", {
            multiplier = auction.doubling.multiplier,
        })
    end

    local next_state = clone_state(auction)
    next_state.doubling.multiplier = next_state.config.bidding.contra_multiplier
    next_state.doubling.contra_by = player
    next_state.doubling.pending_seats = {}
    next_state.history = append_history(auction.history, {
        player = player,
        action = "contra",
    })
    if next_state.config.bidding.contra == "contra_and_redouble" then
        next_state.doubling.redouble_open = true
        next_state.turn = next_state.declarer
    else
        next_state.status = "done"
        next_state.turn = nil
    end
    return { ok = true, auction = tag_as_auction(next_state) }
end

-- Declarer responds to a contra. Only legal under
-- `bidding.contra = "contra_and_redouble"` and only by the declarer.
function M.redouble(auction, player)
    local err = ensure_doubling(auction)
    if err then
        return err
    end
    if auction.config.bidding.contra ~= "contra_and_redouble" then
        return failure("redouble_disabled", "redouble not enabled", {
            contra = auction.config.bidding.contra,
        })
    end
    if not auction.doubling.redouble_open then
        return failure("no_contra", "redouble requires a prior contra", {})
    end
    if player ~= auction.declarer then
        return failure("not_declarer", "only the declarer may redouble", {
            player = player,
            declarer = auction.declarer,
        })
    end

    local next_state = clone_state(auction)
    local config_redouble = next_state.config.bidding.redouble_multiplier
    next_state.doubling.multiplier = next_state.doubling.multiplier * config_redouble
    next_state.doubling.redouble_by = player
    next_state.doubling.redouble_open = false
    next_state.status = "done"
    next_state.turn = nil
    next_state.history = append_history(auction.history, {
        player = player,
        action = "redouble",
    })
    return { ok = true, auction = tag_as_auction(next_state) }
end

-- Defender declines to declare contra. Pops the head of the pending
-- queue; the next defender in clockwise order is offered the choice.
-- When the queue empties without any contra, the auction transitions
-- to `done`.
function M.skip_contra(auction, player)
    local err = ensure_doubling(auction)
    if err then
        return err
    end
    if #auction.doubling.pending_seats == 0 then
        return failure("no_pending_contra", "no contra decision pending", {})
    end
    if auction.doubling.pending_seats[1] ~= player then
        return failure("not_your_turn", "wait for prior defenders to decide", {
            player = player,
            expected = auction.doubling.pending_seats[1],
        })
    end

    local next_state = clone_state(auction)
    local new_pending = {}
    for i = 2, #next_state.doubling.pending_seats do
        new_pending[#new_pending + 1] = next_state.doubling.pending_seats[i]
    end
    next_state.doubling.pending_seats = new_pending
    next_state.history = append_history(auction.history, {
        player = player,
        action = "skip_contra",
    })
    if #new_pending == 0 then
        next_state.status = "done"
        next_state.turn = nil
    else
        next_state.turn = new_pending[1]
    end
    return { ok = true, auction = tag_as_auction(next_state) }
end

return M
