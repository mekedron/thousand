-- The Thousand standard 3-player deal.
--
-- Given a 24-card deck (already shuffled by the caller — we want `deal` to
-- be pure and reproducible) and a `RuleConfig`, returns three 7-card hands
-- and a 3-card talon. The walk follows the canonical pattern documented in
-- docs/rules/dealing.md:
--
--   3 + 3 + 3   to each player                (9 in hands, 0 in talon)
--   2           to the talon
--   2 + 2       to each player                (15 in hands, 2 in talon)
--   1           to the talon
--   2 + 2       to each player                (21 in hands, 3 in talon)
--
-- Each "x to each player" step is encoded as a per-player chunk of x cards
-- handed to player 1, then to player 2, then to player 3, before the next
-- step starts. This is the simplest reading consistent with the documented
-- totals (7 / 7 / 7 / 3) and is what the engine encodes.
--
-- Player count and talon size are read from `RuleConfig` so this module
-- never hard-codes a value a future variant could change. Phase 1 ships
-- support for the canonical 3-player / 3-card-talon shape; non-canonical
-- shapes (Phase 3 variants) are explicitly rejected with typed errors and
-- will gain real support when their pattern lands alongside the variant.
--
-- "Misdeal" in the rules doc covers a handful of physical-table accidents
-- (a card flipped, the wrong number dealt, an exposed talon card). At the
-- engine level the analogue is "deck integrity error": the input deck is
-- the wrong size, contains duplicates, or contains non-card entries. Each
-- failure returns a typed error rather than raising, so callers can
-- surface the misdeal without an exception path.
--
-- The returned hands and talon are plain Lua lists. Hands evolve through
-- play (cards leave them as tricks resolve), so it is the calling layer's
-- job to manage immutability via update-and-replace rather than the engine
-- locking the lists down. The input deck is never mutated.

local card = require("core.card")
local rule_config = require("core.rule_config")

local M = {}

local EXPECTED_DECK_SIZE = 24
local SUPPORTED_PLAYER_COUNT = 3
local SUPPORTED_TALON_SIZE = 3

local SUIT_SET = {}
for _, suit in ipairs(card.SUITS) do
    SUIT_SET[suit] = true
end

local RANK_SET = {}
for _, rank in ipairs(card.RANKS) do
    RANK_SET[rank] = true
end

-- The deal pattern as a flat schedule. Reading top-to-bottom, the dealer
-- hands chunks of cards either to the next player in rotation (`to =
-- "player"`) or to the talon (`to = "talon"`). Sizes sum to 24.
local DEAL_SCHEDULE = {
    { to = "player", size = 3 },
    { to = "player", size = 3 },
    { to = "player", size = 3 },
    { to = "talon", size = 2 },
    { to = "player", size = 2 },
    { to = "player", size = 2 },
    { to = "player", size = 2 },
    { to = "talon", size = 1 },
    { to = "player", size = 2 },
    { to = "player", size = 2 },
    { to = "player", size = 2 },
}

local function failure(code, message, extra)
    local err = { code = code, message = message }
    if extra then
        for k, v in pairs(extra) do
            err[k] = v
        end
    end
    return { ok = false, error = err }
end

local function is_card_like(value)
    if type(value) ~= "table" then
        return false
    end
    if type(value.suit) ~= "string" or type(value.rank) ~= "string" then
        return false
    end
    return SUIT_SET[value.suit] == true and RANK_SET[value.rank] == true
end

local function validate_deck(deck)
    if type(deck) ~= "table" then
        return failure("wrong_deck_size", "deck must be a list of 24 cards", {
            actual = type(deck),
            expected = EXPECTED_DECK_SIZE,
        })
    end
    if #deck ~= EXPECTED_DECK_SIZE then
        return failure("wrong_deck_size", "deck must contain exactly 24 cards", {
            actual = #deck,
            expected = EXPECTED_DECK_SIZE,
        })
    end
    local seen = {}
    for i = 1, EXPECTED_DECK_SIZE do
        local c = deck[i]
        if not is_card_like(c) then
            return failure("not_a_card", "deck contains a non-card entry", { index = i })
        end
        local key = c.suit .. ":" .. c.rank
        if seen[key] then
            return failure("duplicate_card", "deck contains a duplicate card", {
                suit = c.suit,
                rank = c.rank,
                index = i,
            })
        end
        seen[key] = true
    end
    return nil
end

function M.deal(deck, config)
    if not rule_config.is_rule_config(config) then
        return failure("not_a_rule_config", "deal requires a RuleConfig", {
            actual = type(config),
        })
    end
    if config.players.count ~= SUPPORTED_PLAYER_COUNT then
        return failure(
            "unsupported_player_count",
            "Phase 1 dealer supports only 3-player Thousand",
            { player_count = config.players.count }
        )
    end
    if config.talon.size ~= SUPPORTED_TALON_SIZE then
        return failure(
            "unsupported_talon_size",
            "Phase 1 dealer supports only a 3-card talon",
            { talon_size = config.talon.size }
        )
    end

    local deck_error = validate_deck(deck)
    if deck_error then
        return deck_error
    end

    local hands = {}
    for i = 1, SUPPORTED_PLAYER_COUNT do
        hands[i] = {}
    end
    local talon = {}

    local idx = 1
    local current_player = 1
    for _, chunk in ipairs(DEAL_SCHEDULE) do
        if chunk.to == "player" then
            local hand = hands[current_player]
            for _ = 1, chunk.size do
                hand[#hand + 1] = deck[idx]
                idx = idx + 1
            end
            current_player = current_player % SUPPORTED_PLAYER_COUNT + 1
        else
            for _ = 1, chunk.size do
                talon[#talon + 1] = deck[idx]
                idx = idx + 1
            end
        end
    end

    return { ok = true, hands = hands, talon = talon }
end

return M
