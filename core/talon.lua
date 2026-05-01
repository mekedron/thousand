-- The Thousand talon phase.
--
-- Phase 1.4 of the engine: after the auction crowns a declarer, the deal
-- enters the talon phase. The three talon cards are publicly revealed,
-- the declarer takes them into hand (10 / 7 / 7), passes one face-down
-- card to each opponent (8 / 8 / 8), and may raise their winning bid
-- without the pre-talon 120 cap.
--
-- Phase 3.6 generalises the talon to two more shapes:
--
--   * 4-player B (count = 4, talon = 3, dealer_sits_out) — same flow as
--     the canonical 3-player game, with the dealer's seat skipped: the
--     declarer passes one card to each of the two non-dealer opponents.
--     The dealer's hand stays empty for the deal.
--   * 2-player B (count = 2, talon = 3, fixed_deal_no_draw) — declarer
--     takes the talon (10 / 7), passes one card to the single opponent
--     (9 / 8), then discards one card face-down to the captured pile
--     (8 / 8). The discarded card credits its point value to the
--     declarer's captured-points total via the trick layer.
--
-- Variants where there is no traditional talon (count = 4 / talon = 0,
-- or count = 2 / talon = 0 with a draw stock) skip this module entirely
-- — the orchestrator detects `talon.size == 0` and does not construct a
-- talon state at all.
--
-- The state machine progresses through `revealed → take → awaiting_pass
-- → pass (opponent_count times) → [awaiting_discard → discard]
-- → awaiting_raise → raise / skip_raise → done`. The `awaiting_discard`
-- step is only used by 2-player B; for the other shapes the second
-- (or only) pass advances directly to `awaiting_raise`.
--
-- Rule constants (bid increments, opening minimum) come from
-- `RuleConfig`. The post-talon raise removes the pre-talon ceiling
-- (`bidding.pre_talon_max`) so that field is only read during the
-- auction.

local rule_config = require("core.rule_config")
local auction_module = require("core.auction")

local M = {}

M.SCHEMA_VERSION = 1

local TALON_TYPE = "thousand.talon"

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

local function is_card_like(value)
    if type(value) ~= "table" then
        return false
    end
    return type(value.suit) == "string" and type(value.rank) == "string"
end

local function shallow_copy_list(list)
    local copy = {}
    for i = 1, #list do
        copy[i] = list[i]
    end
    return copy
end

local function shallow_copy_hands(hands)
    local copy = {}
    for i = 1, #hands do
        copy[i] = shallow_copy_list(hands[i])
    end
    return copy
end

local function copy_passes_received(passes)
    local copy = {}
    for player in pairs(passes) do
        copy[player] = true
    end
    return copy
end

local function copy_history(history)
    local copy = {}
    for i = 1, #history do
        local entry = history[i]
        copy[i] = {
            action = entry.action,
            player = entry.player,
            target = entry.target,
            card = entry.card,
            amount = entry.amount,
        }
    end
    return copy
end

local function tag_as_talon(state)
    return setmetatable(state, { __metatable = TALON_TYPE })
end

local function clone_state(state)
    return {
        schema_version = state.schema_version,
        config = state.config,
        declarer = state.declarer,
        original_bid = state.original_bid,
        final_bid = state.final_bid,
        hands = shallow_copy_hands(state.hands),
        talon = shallow_copy_list(state.talon),
        passes_received = copy_passes_received(state.passes_received),
        sits_out = state.sits_out,
        opponent_count = state.opponent_count,
        requires_discard = state.requires_discard,
        discards = shallow_copy_list(state.discards),
        status = state.status,
        history = copy_history(state.history),
    }
end

local function append_history(history, entry)
    local copy = copy_history(history)
    copy[#copy + 1] = entry
    return copy
end

-- Resolve the talon-supporting variant, returning the player layout
-- (hand size before take, opponent count, sits-out seat). Variants
-- without a traditional talon (size == 0) reject loudly because the
-- orchestrator should not construct a talon state for those.
local function resolve_layout(config)
    local count = config.players.count
    local talon_size = config.talon.size

    if talon_size == 0 then
        return failure(
            "talon_skipped",
            "config has no traditional talon — orchestrator should skip the talon phase",
            { talon_size = talon_size, player_count = count }
        )
    end

    if count == 3 and talon_size == 3 then
        return {
            ok = true,
            hand_size = 7,
            opponent_count = 2,
            sits_out = nil,
        }
    end
    if count == 4 and talon_size == 3 then
        if config.players.four_player_config ~= "dealer_sits_out" then
            return failure(
                "unsupported_four_player_config",
                "4-player talon requires four_player_config = 'dealer_sits_out'",
                { four_player_config = config.players.four_player_config }
            )
        end
        return {
            ok = true,
            hand_size = 7,
            opponent_count = 2,
            -- `sits_out` is filled in from the auction's dealer below.
            sits_out_from_dealer = true,
        }
    end
    if count == 2 and talon_size == 3 then
        if config.players.two_player_config ~= "fixed_deal_no_draw" then
            return failure(
                "unsupported_two_player_config",
                "2-player talon requires two_player_config = 'fixed_deal_no_draw'",
                { two_player_config = config.players.two_player_config }
            )
        end
        return {
            ok = true,
            hand_size = 7,
            opponent_count = 1,
            sits_out = nil,
            requires_discard = true,
        }
    end
    return failure(
        "unsupported_talon_size",
        "talon module supports only 3-card talons in the active layout",
        { talon_size = talon_size, player_count = count }
    )
end

local function validate_hands(hands, hand_size, count, sits_out)
    if type(hands) ~= "table" then
        return failure("bad_hands_shape", "hands must be a list of " .. count .. " hands", {
            actual = type(hands),
        })
    end
    if #hands ~= count then
        return failure(
            "bad_hands_shape",
            "hands must contain exactly " .. count .. " player hands",
            { actual = #hands, expected = count }
        )
    end
    for i = 1, count do
        local hand = hands[i]
        if type(hand) ~= "table" then
            return failure("bad_hands_shape", "each hand must be a list of cards", {
                player = i,
                actual = type(hand),
            })
        end
        local expected
        if i == sits_out then
            expected = 0
        else
            expected = hand_size
        end
        if #hand ~= expected then
            return failure(
                "bad_hands_shape",
                "each hand must hold the layout's pre-take size",
                { player = i, actual = #hand, expected = expected }
            )
        end
        for j = 1, #hand do
            if not is_card_like(hand[j]) then
                return failure("bad_hands_shape", "hand contains a non-card entry", {
                    player = i,
                    index = j,
                })
            end
        end
    end
    return nil
end

local function validate_talon_cards(cards, talon_size)
    if type(cards) ~= "table" then
        return failure("bad_talon_shape", "talon must be a list of cards", {
            actual = type(cards),
        })
    end
    if #cards ~= talon_size then
        return failure("bad_talon_shape", "talon must contain exactly " .. talon_size .. " cards", {
            actual = #cards,
            expected = talon_size,
        })
    end
    for i = 1, talon_size do
        if not is_card_like(cards[i]) then
            return failure("bad_talon_shape", "talon contains a non-card entry", {
                index = i,
            })
        end
    end
    return nil
end

function M.new(config, auction, hands, talon_cards)
    if not rule_config.is_rule_config(config) then
        return failure("not_a_rule_config", "talon.new requires a RuleConfig", {
            actual = type(config),
        })
    end
    if not auction_module.is_auction(auction) then
        return failure("not_an_auction", "talon.new requires a finalized auction", {
            actual = type(auction),
        })
    end
    if auction.status == "all_pass" then
        return failure(
            "auction_was_all_pass",
            "talon phase has no declarer when the auction terminated all-pass",
            { status = auction.status }
        )
    end
    if auction.status ~= "done" then
        return failure(
            "auction_not_done",
            "talon phase requires a finalized auction",
            { status = auction.status }
        )
    end

    local layout_result = resolve_layout(config)
    if not layout_result.ok then
        return layout_result
    end
    local sits_out = layout_result.sits_out
    if layout_result.sits_out_from_dealer then
        sits_out = auction.dealer
    end

    local hands_err = validate_hands(hands, layout_result.hand_size, config.players.count, sits_out)
    if hands_err then
        return hands_err
    end
    local talon_err = validate_talon_cards(talon_cards, config.talon.size)
    if talon_err then
        return talon_err
    end

    local state = tag_as_talon({
        schema_version = M.SCHEMA_VERSION,
        config = config,
        declarer = auction.declarer,
        original_bid = auction.final_bid,
        final_bid = auction.final_bid,
        hands = shallow_copy_hands(hands),
        talon = shallow_copy_list(talon_cards),
        passes_received = {},
        sits_out = sits_out,
        opponent_count = layout_result.opponent_count,
        requires_discard = layout_result.requires_discard or false,
        discards = {},
        status = "revealed",
        history = {},
    })
    return { ok = true, talon = state }
end

function M.is_talon(value)
    if type(value) ~= "table" then
        return false
    end
    return getmetatable(value) == TALON_TYPE
end

local function ensure_talon(state)
    if not M.is_talon(state) then
        return failure("not_a_talon", "first argument is not a talon state", {
            actual = type(state),
        })
    end
    return nil
end

local function ensure_status(state, expected, action)
    if state.status ~= expected then
        return failure(
            "wrong_phase",
            action .. " requires status '" .. expected .. "'",
            { status = state.status, expected = expected }
        )
    end
    return nil
end

function M.take(state)
    local talon_err = ensure_talon(state)
    if talon_err then
        return talon_err
    end
    local phase_err = ensure_status(state, "revealed", "take")
    if phase_err then
        return phase_err
    end

    local next_state = clone_state(state)
    local declarer_hand = next_state.hands[next_state.declarer]
    for i = 1, #next_state.talon do
        declarer_hand[#declarer_hand + 1] = next_state.talon[i]
    end
    next_state.talon = {}
    next_state.status = "awaiting_pass"
    next_state.history = append_history(state.history, {
        action = "take",
        player = next_state.declarer,
    })
    return { ok = true, talon = tag_as_talon(next_state) }
end

local function find_card_index(hand, target_card)
    for i = 1, #hand do
        local c = hand[i]
        if c.suit == target_card.suit and c.rank == target_card.rank then
            return i
        end
    end
    return nil
end

function M.pass(state, target_player, card)
    local talon_err = ensure_talon(state)
    if talon_err then
        return talon_err
    end
    local phase_err = ensure_status(state, "awaiting_pass", "pass")
    if phase_err then
        return phase_err
    end

    local count = state.config.players.count
    local valid_target = is_integer(target_player) and target_player >= 1 and target_player <= count
    if not valid_target then
        return failure(
            "bad_target",
            "target must be an integer in 1.." .. count,
            { actual = target_player, player_count = count }
        )
    end
    if target_player == state.declarer then
        return failure("bad_target", "declarer cannot pass to themselves", {
            target = target_player,
            declarer = state.declarer,
        })
    end
    if state.sits_out and target_player == state.sits_out then
        return failure(
            "bad_target",
            "cannot pass to the sitting-out seat",
            { target = target_player, sits_out = state.sits_out }
        )
    end
    if state.passes_received[target_player] then
        return failure(
            "target_already_received",
            "target opponent has already received a pass",
            { target = target_player }
        )
    end
    if not is_card_like(card) then
        return failure("card_not_in_hand", "card argument is not a card", {
            actual = type(card),
        })
    end

    local declarer_hand = state.hands[state.declarer]
    local idx = find_card_index(declarer_hand, card)
    if idx == nil then
        return failure("card_not_in_hand", "card is not in the declarer's hand", {
            suit = card.suit,
            rank = card.rank,
        })
    end

    local next_state = clone_state(state)
    local new_declarer_hand = next_state.hands[next_state.declarer]
    local passed_card = new_declarer_hand[idx]
    table.remove(new_declarer_hand, idx)
    local opponent_hand = next_state.hands[target_player]
    opponent_hand[#opponent_hand + 1] = passed_card
    next_state.passes_received[target_player] = true
    next_state.history = append_history(state.history, {
        action = "pass",
        player = next_state.declarer,
        target = target_player,
        card = passed_card,
    })

    local pass_count = 0
    for _ in pairs(next_state.passes_received) do
        pass_count = pass_count + 1
    end
    if pass_count >= state.opponent_count then
        if state.requires_discard then
            next_state.status = "awaiting_discard"
        else
            next_state.status = "awaiting_raise"
        end
    end
    return { ok = true, talon = tag_as_talon(next_state) }
end

function M.discard(state, card)
    local talon_err = ensure_talon(state)
    if talon_err then
        return talon_err
    end
    local phase_err = ensure_status(state, "awaiting_discard", "discard")
    if phase_err then
        return phase_err
    end
    if not is_card_like(card) then
        return failure("card_not_in_hand", "card argument is not a card", {
            actual = type(card),
        })
    end

    local declarer_hand = state.hands[state.declarer]
    local idx = find_card_index(declarer_hand, card)
    if idx == nil then
        return failure("card_not_in_hand", "card is not in the declarer's hand", {
            suit = card.suit,
            rank = card.rank,
        })
    end

    local next_state = clone_state(state)
    local new_declarer_hand = next_state.hands[next_state.declarer]
    local discarded_card = new_declarer_hand[idx]
    table.remove(new_declarer_hand, idx)
    next_state.discards[#next_state.discards + 1] = discarded_card
    next_state.status = "awaiting_raise"
    next_state.history = append_history(state.history, {
        action = "discard",
        player = next_state.declarer,
        card = discarded_card,
    })
    return { ok = true, talon = tag_as_talon(next_state) }
end

local function validate_raise_amount(state, amount)
    if not is_integer(amount) then
        return failure("raise_not_integer", "raise amount must be an integer", {
            actual = amount,
        })
    end
    if amount <= state.final_bid then
        return failure(
            "raise_not_higher",
            "raise must be strictly higher than the current bid",
            { amount = amount, current_bid = state.final_bid }
        )
    end
    local bidding = state.config.bidding
    local step
    if amount < bidding.increment_threshold then
        step = bidding.increment_below_200
    else
        step = bidding.increment_from_200
    end
    if amount % step ~= 0 then
        return failure(
            "bad_raise_increment",
            "raise amount must respect the increment rule",
            { amount = amount, step = step }
        )
    end
    return nil
end

function M.raise(state, amount)
    local talon_err = ensure_talon(state)
    if talon_err then
        return talon_err
    end
    local phase_err = ensure_status(state, "awaiting_raise", "raise")
    if phase_err then
        return phase_err
    end
    local amount_err = validate_raise_amount(state, amount)
    if amount_err then
        return amount_err
    end

    local next_state = clone_state(state)
    next_state.final_bid = amount
    next_state.status = "done"
    next_state.history = append_history(state.history, {
        action = "raise",
        player = next_state.declarer,
        amount = amount,
    })
    return { ok = true, talon = tag_as_talon(next_state) }
end

function M.skip_raise(state)
    local talon_err = ensure_talon(state)
    if talon_err then
        return talon_err
    end
    local phase_err = ensure_status(state, "awaiting_raise", "skip_raise")
    if phase_err then
        return phase_err
    end

    local next_state = clone_state(state)
    next_state.status = "done"
    next_state.history = append_history(state.history, {
        action = "skip_raise",
        player = next_state.declarer,
    })
    return { ok = true, talon = tag_as_talon(next_state) }
end

return M
