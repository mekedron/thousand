-- The Thousand marriage state.
--
-- Phase 1.5 of the engine: a marriage is the King + Queen of the same suit
-- held in one player's hand. Declared by leading the K or Q while on lead,
-- a marriage immediately credits its bonus to the declaring player's deal
-- score and switches the trump suit. Until the first marriage is declared
-- there is no trump at all; subsequent marriages replace the current trump.
--
-- This module owns the marriage mechanics — detection, declaration, bonus
-- bookkeeping, and trump state. It does NOT own the "must be on lead" or
-- "K/Q is leading the trick" preconditions: those belong to the trick layer
-- (Phase 1.6), which decides when to call `declare`. The trick layer will
-- read `state.trump` at trick boundaries to enforce trick-play rules; the
-- timing rule that the new trump only takes effect from the *next* trick
-- (the marriage trick itself plays under whatever trump preceded it) is a
-- trick-layer concern as well — this module simply records "trump as last
-- declared".
--
-- Rule constants (marriage values per suit, supported player count) come
-- from `RuleConfig`. Marriages produced via the talon are legal without
-- special-casing — the only fact that matters at declaration time is
-- whether the player's current hand holds K+Q of the suit.
--
-- State shape (type-tagged via `__metatable`, like `core.talon`):
--   {
--     schema_version = 1,
--     config = <RuleConfig>,
--     trump = nil | "hearts" | "diamonds" | "clubs" | "spades",
--     bonuses = { [1]=0, [2]=0, ..., [N]=0 },
--     declarations = {
--       { player=, suit=, value=, kind="kq"|"ace_marriage", cancelled=bool? },
--       ...
--     },
--     pending_ace_trump = nil | <player>,
--   }
--
-- Each transition returns a fresh state; the input is never mutated.
--
-- Phase 3.6 marriage house-rule additions:
--   * `M.declare` honours `marriages.one_trump_per_deal`. When `"on"` and a
--     prior K-Q declaration exists, the new trump is NOT applied to
--     `state.trump` — the bonus posts but the trump suit stands.
--   * `M.announce_from_hand` mirrors `declare`'s validation but is the
--     entry point for `marriage_announcement_timing = "hand_announcement"`
--     and `"pre_first_trick"`. Lead-position checking belongs to the
--     session/trick layer.
--   * `M.declare_ace_marriage` admits the тузовый марьяж under
--     `marriages.ace_marriage in {"on","sets_trump"}`. Under
--     `"sets_trump"`, the state records `pending_ace_trump` so the
--     orchestrator can flip trump when that seat next leads an Ace.
--     Under `"on"`, only the bonus posts.
--   * `M.cancel_drowned` is the reversal entry for
--     `drowned_marriage = "retroactive_cancel"`: reverses the bonus and
--     marks the declaration `cancelled = true`. The orchestrator owns
--     the detection; the engine just applies the reversal.

local rule_config = require("core.rule_config")

local M = {}

M.SCHEMA_VERSION = 1

local MARRIAGES_TYPE = "thousand.marriages"

M.SUITS = { "hearts", "diamonds", "clubs", "spades" }

local SUIT_SET = {}
for _, suit in ipairs(M.SUITS) do
    SUIT_SET[suit] = true
end

local MARRIAGE_RANK_KING = "K"
local MARRIAGE_RANK_QUEEN = "Q"

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

local function tag_as_marriages(state)
    return setmetatable(state, { __metatable = MARRIAGES_TYPE })
end

local function copy_bonuses(bonuses)
    local copy = {}
    for i = 1, #bonuses do
        copy[i] = bonuses[i]
    end
    return copy
end

local function copy_declarations(declarations)
    local copy = {}
    for i = 1, #declarations do
        local entry = declarations[i]
        copy[i] = {
            player = entry.player,
            suit = entry.suit,
            value = entry.value,
            kind = entry.kind,
            cancelled = entry.cancelled,
        }
    end
    return copy
end

local function clone_state(state)
    return {
        schema_version = state.schema_version,
        config = state.config,
        trump = state.trump,
        bonuses = copy_bonuses(state.bonuses),
        declarations = copy_declarations(state.declarations),
        pending_ace_trump = state.pending_ace_trump,
    }
end

local function hand_contains(hand, suit, rank)
    for i = 1, #hand do
        local c = hand[i]
        if c.suit == suit and c.rank == rank then
            return true
        end
    end
    return false
end

function M.new(config)
    if not rule_config.is_rule_config(config) then
        return failure("not_a_rule_config", "marriages.new requires a RuleConfig", {
            actual = type(config),
        })
    end

    local player_count = config.players.count
    local bonuses = {}
    for i = 1, player_count do
        bonuses[i] = 0
    end

    local state = tag_as_marriages({
        schema_version = M.SCHEMA_VERSION,
        config = config,
        trump = nil,
        bonuses = bonuses,
        declarations = {},
        pending_ace_trump = nil,
    })
    return { ok = true, marriages = state }
end

function M.is_marriages(value)
    if type(value) ~= "table" then
        return false
    end
    return getmetatable(value) == MARRIAGES_TYPE
end

function M.detect(hand)
    if type(hand) ~= "table" then
        error("marriages.detect: hand must be a list of cards, got " .. type(hand))
    end
    for i = 1, #hand do
        if not is_card_like(hand[i]) then
            error("marriages.detect: hand contains a non-card entry at index " .. i)
        end
    end

    local found = {}
    for _, suit in ipairs(M.SUITS) do
        if
            hand_contains(hand, suit, MARRIAGE_RANK_KING)
            and hand_contains(hand, suit, MARRIAGE_RANK_QUEEN)
        then
            found[#found + 1] = suit
        end
    end
    return found
end

local function ensure_marriages(state)
    if not M.is_marriages(state) then
        return failure("not_a_marriages", "first argument is not a marriages state", {
            actual = type(state),
        })
    end
    return nil
end

local function already_declared(state, suit)
    for i = 1, #state.declarations do
        local entry = state.declarations[i]
        if entry.suit == suit and not entry.cancelled then
            return true
        end
    end
    return false
end

local function count_kq_declarations(state)
    local n = 0
    for i = 1, #state.declarations do
        local entry = state.declarations[i]
        if (entry.kind == nil or entry.kind == "kq") and not entry.cancelled then
            n = n + 1
        end
    end
    return n
end

local function validate_kq_declaration(state, player, suit, hand, tricks_won)
    local state_err = ensure_marriages(state)
    if state_err then
        return state_err
    end

    local player_count = state.config.players.count
    if not (is_integer(player) and player >= 1 and player <= player_count) then
        return failure(
            "bad_player",
            "player must be an integer in 1.." .. player_count,
            { actual = player, player_count = player_count }
        )
    end

    if type(suit) ~= "string" or not SUIT_SET[suit] then
        return failure("bad_suit", "suit is not a recognised marriage suit", {
            actual = suit,
        })
    end

    if type(hand) ~= "table" then
        return failure("card_not_in_hand", "hand must be a list of cards", {
            actual = type(hand),
        })
    end
    for i = 1, #hand do
        if not is_card_like(hand[i]) then
            return failure("card_not_in_hand", "hand contains a non-card entry", {
                index = i,
            })
        end
    end

    if not hand_contains(hand, suit, MARRIAGE_RANK_KING) then
        return failure("card_not_in_hand", "hand is missing the K of " .. suit, {
            suit = suit,
            rank = MARRIAGE_RANK_KING,
        })
    end
    if not hand_contains(hand, suit, MARRIAGE_RANK_QUEEN) then
        return failure("card_not_in_hand", "hand is missing the Q of " .. suit, {
            suit = suit,
            rank = MARRIAGE_RANK_QUEEN,
        })
    end

    if already_declared(state, suit) then
        return failure(
            "marriage_suit_already_declared",
            "a marriage in " .. suit .. " has already been declared this deal",
            { suit = suit }
        )
    end

    if state.config.marriages.trick_required == "on" and (tonumber(tricks_won) or 0) < 1 then
        return failure(
            "trick_required_not_met",
            "marriages.trick_required = on; the seat has not yet captured a trick",
            { player = player, suit = suit, tricks_won = tonumber(tricks_won) or 0 }
        )
    end

    local value = state.config.marriages.values[suit]
    if type(value) ~= "number" then
        return failure("bad_suit", "config has no marriage value for " .. suit, {
            suit = suit,
        })
    end
    return { ok = true, value = value }
end

local function apply_kq_declaration(state, player, suit, value)
    local one_trump = state.config.marriages.one_trump_per_deal == "on"
    local next_state = clone_state(state)
    if not one_trump or count_kq_declarations(state) == 0 then
        next_state.trump = suit
    end
    next_state.bonuses[player] = next_state.bonuses[player] + value
    next_state.declarations[#next_state.declarations + 1] = {
        player = player,
        suit = suit,
        value = value,
        kind = "kq",
    }
    return tag_as_marriages(next_state)
end

-- The optional `tricks_won` argument is the count of tricks the
-- declaring seat has captured this deal at the moment of declaration.
-- Under `marriages.trick_required = "on"` (the book default), the call
-- fails with `trick_required_not_met` if the count is below 1. Callers
-- that already gate the precondition externally (or that want the
-- trickless variant) pass a satisfying number or set the rule to "off".
function M.declare(state, player, suit, hand, tricks_won)
    local validated = validate_kq_declaration(state, player, suit, hand, tricks_won)
    if not validated.ok then
        return validated
    end
    return {
        ok = true,
        marriages = apply_kq_declaration(state, player, suit, validated.value),
    }
end

-- Records a K-Q marriage announcement that does not flow through an
-- on-lead K/Q play. Used by `marriage_announcement_timing` variants
-- `hand_announcement` (announce while on lead, then play any card)
-- and `pre_first_trick` (announce before the first lead). The lead /
-- phase precondition is the orchestrator's responsibility — this
-- module only checks the structural rule (hand holds K+Q, suit not
-- already declared, trick captured if `trick_required = on`) and
-- applies the bonus + trump under the `one_trump_per_deal` rule.
function M.announce_from_hand(state, player, suit, hand, tricks_won)
    local validated = validate_kq_declaration(state, player, suit, hand, tricks_won)
    if not validated.ok then
        return validated
    end
    return {
        ok = true,
        marriages = apply_kq_declaration(state, player, suit, validated.value),
    }
end

local function hand_has_all_aces(hand)
    local seen = {}
    for i = 1, #hand do
        local c = hand[i]
        if c.rank == "A" and SUIT_SET[c.suit] then
            seen[c.suit] = true
        end
    end
    for _, suit in ipairs(M.SUITS) do
        if not seen[suit] then
            return false
        end
    end
    return true
end

local function ace_marriage_already_declared(state)
    for i = 1, #state.declarations do
        local entry = state.declarations[i]
        if entry.kind == "ace_marriage" and not entry.cancelled then
            return true
        end
    end
    return false
end

-- Records a four-Aces declaration (тузовый марьяж) under
-- `marriages.ace_marriage in {"on","sets_trump"}`. Returns
-- `ace_marriage_disabled` when the toggle is `"off"`. Under
-- `"sets_trump"` the orchestrator should watch for the next Ace led
-- by the declaring seat and call `tricks.set_trump` (or the
-- in-trick equivalent) with that suit; the marriage state records
-- `pending_ace_trump = player` until cleared.
-- The optional `tricks_won` argument follows the same contract as
-- `M.declare`: under `marriages.trick_required = "on"` the call fails
-- with `trick_required_not_met` if the seat has not yet captured a
-- trick this deal.
function M.declare_ace_marriage(state, player, hand, tricks_won)
    local state_err = ensure_marriages(state)
    if state_err then
        return state_err
    end

    local mode = state.config.marriages.ace_marriage
    if mode == "off" then
        return failure(
            "ace_marriage_disabled",
            "ace_marriage is off in this RuleConfig",
            { mode = mode }
        )
    end

    local player_count = state.config.players.count
    if not (is_integer(player) and player >= 1 and player <= player_count) then
        return failure(
            "bad_player",
            "player must be an integer in 1.." .. player_count,
            { actual = player, player_count = player_count }
        )
    end

    if type(hand) ~= "table" then
        return failure("card_not_in_hand", "hand must be a list of cards", {
            actual = type(hand),
        })
    end
    for i = 1, #hand do
        if not is_card_like(hand[i]) then
            return failure("card_not_in_hand", "hand contains a non-card entry", {
                index = i,
            })
        end
    end

    if not hand_has_all_aces(hand) then
        return failure(
            "ace_marriage_requires_four_aces",
            "ace marriage requires the four Aces in hand",
            {}
        )
    end

    if ace_marriage_already_declared(state) then
        return failure(
            "ace_marriage_already_declared",
            "an ace marriage has already been declared this deal",
            {}
        )
    end

    if state.config.marriages.trick_required == "on" and (tonumber(tricks_won) or 0) < 1 then
        return failure(
            "trick_required_not_met",
            "marriages.trick_required = on; the seat has not yet captured a trick",
            { player = player, kind = "ace_marriage", tricks_won = tonumber(tricks_won) or 0 }
        )
    end

    local value = state.config.marriages.ace_marriage_value
    if type(value) ~= "number" then
        return failure(
            "bad_ace_marriage_value",
            "config has no ace_marriage_value",
            { actual = type(value) }
        )
    end

    local next_state = clone_state(state)
    next_state.bonuses[player] = next_state.bonuses[player] + value
    next_state.declarations[#next_state.declarations + 1] = {
        player = player,
        suit = "aces",
        value = value,
        kind = "ace_marriage",
    }
    if mode == "sets_trump" then
        next_state.pending_ace_trump = player
    end
    return { ok = true, marriages = tag_as_marriages(next_state) }
end

-- Resolves a pending ace-trump activation: marks the trump suit as
-- the led Ace's suit and clears `pending_ace_trump`. Caller (the
-- session) is responsible for checking that the active variant is
-- `ace_marriage = "sets_trump"` and that the led card is the Ace of
-- the named suit.
function M.activate_ace_trump(state, suit)
    local state_err = ensure_marriages(state)
    if state_err then
        return state_err
    end
    if state.pending_ace_trump == nil then
        return failure("no_pending_ace_trump", "no pending ace-trump activation is recorded", {})
    end
    if type(suit) ~= "string" or not SUIT_SET[suit] then
        return failure("bad_suit", "suit is not a recognised marriage suit", {
            actual = suit,
        })
    end
    local next_state = clone_state(state)
    next_state.trump = suit
    next_state.pending_ace_trump = nil
    return { ok = true, marriages = tag_as_marriages(next_state) }
end

-- Reverses the bonus on a previously-declared K-Q marriage. Used by
-- the orchestrator under `drowned_marriage = "retroactive_cancel"`
-- when an opponent later captures the K or Q of the declared suit.
-- The trump suit is intentionally NOT reverted: the existing
-- declarations still bind play, and reverting trump mid-deal is not
-- documented in docs/variations/house-rules.md "Drowned marriage".
function M.cancel_drowned(state, suit)
    local state_err = ensure_marriages(state)
    if state_err then
        return state_err
    end
    if type(suit) ~= "string" or not SUIT_SET[suit] then
        return failure("bad_suit", "suit is not a recognised marriage suit", {
            actual = suit,
        })
    end
    local index = nil
    for i = 1, #state.declarations do
        local entry = state.declarations[i]
        if
            entry.suit == suit
            and (entry.kind == nil or entry.kind == "kq")
            and not entry.cancelled
        then
            index = i
            break
        end
    end
    if not index then
        return failure(
            "no_active_marriage",
            "no active K-Q marriage in " .. suit .. " to cancel",
            { suit = suit }
        )
    end

    local target = state.declarations[index]
    local next_state = clone_state(state)
    next_state.bonuses[target.player] = next_state.bonuses[target.player] - target.value
    next_state.declarations[index].cancelled = true
    return { ok = true, marriages = tag_as_marriages(next_state) }
end

return M
