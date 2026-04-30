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
--     declarations = { { player=, suit=, value= }, ... },
--   }
--
-- Each transition returns a fresh state; the input is never mutated.

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
        if state.declarations[i].suit == suit then
            return true
        end
    end
    return false
end

function M.declare(state, player, suit, hand)
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

    local value = state.config.marriages.values[suit]
    if type(value) ~= "number" then
        return failure("bad_suit", "config has no marriage value for " .. suit, {
            suit = suit,
        })
    end

    local next_state = clone_state(state)
    next_state.trump = suit
    next_state.bonuses[player] = next_state.bonuses[player] + value
    next_state.declarations[#next_state.declarations + 1] = {
        player = player,
        suit = suit,
        value = value,
    }
    return { ok = true, marriages = tag_as_marriages(next_state) }
end

return M
