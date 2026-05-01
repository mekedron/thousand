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

local function copy_passed(passed)
    local copy = {}
    for i = 1, #passed do
        copy[i] = passed[i]
    end
    return copy
end

local function copy_history(history)
    local copy = {}
    for i = 1, #history do
        local entry = history[i]
        copy[i] = { player = entry.player, action = entry.action, amount = entry.amount }
    end
    return copy
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
        current_bid = state.current_bid,
        current_leader = state.current_leader,
        passed = copy_passed(state.passed),
        pass_count = state.pass_count,
        status = state.status,
        declarer = state.declarer,
        final_bid = state.final_bid,
        history = copy_history(state.history),
    }
end

local function append_history(history, entry)
    local copy = copy_history(history)
    copy[#copy + 1] = entry
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

function M.new(config, dealer)
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

    local sits_out = compute_sits_out(config, dealer)
    local forehand = (dealer % player_count) + 1
    local passed = {}
    local pass_count = 0
    for i = 1, player_count do
        if sits_out and i == sits_out then
            passed[i] = true
            pass_count = pass_count + 1
        else
            passed[i] = false
        end
    end

    local state = tag_as_auction({
        schema_version = M.SCHEMA_VERSION,
        config = config,
        dealer = dealer,
        forehand = forehand,
        player_count = player_count,
        sits_out = sits_out,
        turn = forehand,
        current_bid = nil,
        current_leader = nil,
        passed = passed,
        pass_count = pass_count,
        status = "in_progress",
        declarer = nil,
        final_bid = nil,
        history = {},
    })
    return { ok = true, auction = state }
end

function M.is_auction(value)
    if type(value) ~= "table" then
        return false
    end
    return getmetatable(value) == AUCTION_TYPE
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

local function validate_bid_amount(state, amount)
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

    return nil
end

function M.bid(auction, player, amount)
    local progress_err = ensure_in_progress(auction)
    if progress_err then
        return progress_err
    end
    local actor_err = validate_actor(auction, player)
    if actor_err then
        return actor_err
    end
    local amount_err = validate_bid_amount(auction, amount)
    if amount_err then
        return amount_err
    end

    local next_state = clone_state(auction)
    next_state.current_bid = amount
    next_state.current_leader = player
    next_state.history = append_history(auction.history, {
        player = player,
        action = "bid",
        amount = amount,
    })
    -- A bid never ends the auction; it only updates the leader and
    -- advances the turn to the next non-passed seat.
    next_state.turn = next_active_seat(next_state.passed, player, next_state.player_count)
    return { ok = true, auction = tag_as_auction(next_state) }
end

local function finalize_after_pass(state)
    if state.current_bid ~= nil then
        state.status = "done"
        state.declarer = state.current_leader
        state.final_bid = state.current_bid
    else
        state.status = "all_pass"
    end
    state.turn = nil
end

function M.pass(auction, player)
    local progress_err = ensure_in_progress(auction)
    if progress_err then
        return progress_err
    end
    local actor_err = validate_actor(auction, player)
    if actor_err then
        return actor_err
    end

    local next_state = clone_state(auction)
    next_state.passed[player] = true
    next_state.pass_count = next_state.pass_count + 1
    next_state.history = append_history(auction.history, {
        player = player,
        action = "pass",
    })

    if next_state.pass_count >= next_state.player_count - 1 then
        finalize_after_pass(next_state)
    else
        next_state.turn = next_active_seat(next_state.passed, player, next_state.player_count)
    end
    return { ok = true, auction = tag_as_auction(next_state) }
end

return M
