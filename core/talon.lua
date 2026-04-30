-- The Thousand talon phase.
--
-- Phase 1.4 of the engine: after the auction crowns a declarer, the deal
-- enters the talon phase. The three talon cards are publicly revealed,
-- the declarer takes them into hand (10 / 7 / 7), passes one face-down
-- card to each opponent (8 / 8 / 8), and may raise their winning bid
-- without the pre-talon 120 cap. The raise is binding: a declarer who
-- dislikes the talon may not lower the bid.
--
-- Inputs come from the prior phases:
--   * `core.auction` produces a finalized auction with `status == "done"`,
--     a `declarer` and a `final_bid`.
--   * `core.dealing` produces three 7-card hands and a 3-card talon.
--
-- The two are wired together by `talon.new(config, auction, hands,
-- talon_cards)`, which validates the hand-off and returns a state with
-- status `"revealed"`. From there the state machine progresses through
-- `take` -> `pass` (twice) -> `raise` or `skip_raise` -> `"done"`. Every
-- step returns a fresh state; the input is never mutated. The state is
-- type-tagged via `__metatable` so `is_talon` can recognise it; this is
-- the same pattern `core.auction` and `core.rule_config` use.
--
-- Rule constants (bid increments, opening minimum) come from
-- `RuleConfig`. The post-talon raise removes the pre-talon ceiling
-- (`bidding.pre_talon_max`) — the rules doc explicitly contrasts the
-- two phases — so that field is only read during the auction.

local rule_config = require("core.rule_config")
local auction_module = require("core.auction")

local M = {}

M.SCHEMA_VERSION = 1

local TALON_TYPE = "thousand.talon"

local SUPPORTED_PLAYER_COUNT = 3
local DECLARER_HAND_SIZE_BEFORE_TAKE = 7
local TALON_SIZE = 3

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
        status = state.status,
        history = copy_history(state.history),
    }
end

local function append_history(history, entry)
    local copy = copy_history(history)
    copy[#copy + 1] = entry
    return copy
end

local function validate_hands(hands)
    if type(hands) ~= "table" then
        return failure("bad_hands_shape", "hands must be a list of 3 hands", {
            actual = type(hands),
        })
    end
    if #hands ~= SUPPORTED_PLAYER_COUNT then
        return failure(
            "bad_hands_shape",
            "hands must contain exactly 3 player hands",
            { actual = #hands, expected = SUPPORTED_PLAYER_COUNT }
        )
    end
    for i = 1, SUPPORTED_PLAYER_COUNT do
        local hand = hands[i]
        if type(hand) ~= "table" then
            return failure("bad_hands_shape", "each hand must be a list of cards", {
                player = i,
                actual = type(hand),
            })
        end
        if #hand ~= DECLARER_HAND_SIZE_BEFORE_TAKE then
            return failure(
                "bad_hands_shape",
                "each hand must hold 7 cards before the talon take",
                { player = i, actual = #hand, expected = DECLARER_HAND_SIZE_BEFORE_TAKE }
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

local function validate_talon_cards(cards)
    if type(cards) ~= "table" then
        return failure("bad_talon_shape", "talon must be a list of 3 cards", {
            actual = type(cards),
        })
    end
    if #cards ~= TALON_SIZE then
        return failure("bad_talon_shape", "talon must contain exactly 3 cards", {
            actual = #cards,
            expected = TALON_SIZE,
        })
    end
    for i = 1, TALON_SIZE do
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

    local hands_err = validate_hands(hands)
    if hands_err then
        return hands_err
    end
    local talon_err = validate_talon_cards(talon_cards)
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

    local valid_target = is_integer(target_player)
        and target_player >= 1
        and target_player <= SUPPORTED_PLAYER_COUNT
    if not valid_target then
        return failure(
            "bad_target",
            "target must be an integer in 1.." .. SUPPORTED_PLAYER_COUNT,
            { actual = target_player, player_count = SUPPORTED_PLAYER_COUNT }
        )
    end
    if target_player == state.declarer then
        return failure("bad_target", "declarer cannot pass to themselves", {
            target = target_player,
            declarer = state.declarer,
        })
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
    if pass_count >= SUPPORTED_PLAYER_COUNT - 1 then
        next_state.status = "awaiting_raise"
    end
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
    if amount < 200 then
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
