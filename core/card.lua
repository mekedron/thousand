-- The Thousand card model.
--
-- A card is the smallest atom in the engine: a `{ suit, rank }` pair drawn
-- from the four suits and six ranks the game uses (24 distinct cards in
-- total). Card identity is structurally invariant across every documented
-- variant — Russian, Polish, Ukrainian, 2-player and 4-player Thousand all
-- share the same suits and ranks. What VARIES — point values and trick
-- ranking — lives in `RuleConfig`, and the lookup helpers here take a
-- config to resolve those values without holding hidden global state.
--
-- Constructed cards are frozen tables: assigning to `card.suit` or any
-- other key raises. Equality is structural via `card.equals`. Display is
-- via `card.tostring` (Unicode suit glyphs, used for debug output; UI text
-- is the responsibility of the presentation layer through `t()`).

local M = {}

local CARD_TYPE = "thousand.card"

M.SUITS = { "spades", "clubs", "diamonds", "hearts" }
M.RANKS = { "9", "J", "Q", "K", "10", "A" }

local SUIT_SET = {}
for _, suit in ipairs(M.SUITS) do
    SUIT_SET[suit] = true
end

local RANK_SET = {}
for _, rank in ipairs(M.RANKS) do
    RANK_SET[rank] = true
end

local SUIT_GLYPHS = {
    spades = "♠",
    clubs = "♣",
    diamonds = "♦",
    hearts = "♥",
}

local rule_config = require("core.rule_config")

local function freeze_card(suit, rank)
    local data = { suit = suit, rank = rank }
    return setmetatable({}, {
        __index = data,
        __newindex = function(_, key)
            error("card is frozen: cannot set key " .. tostring(key), 2)
        end,
        __metatable = CARD_TYPE,
    })
end

local function rank_of(card_or_rank)
    if type(card_or_rank) == "string" then
        return card_or_rank
    end
    if type(card_or_rank) == "table" then
        return card_or_rank.rank
    end
    error("card: expected card table or rank string, got " .. type(card_or_rank))
end

local function require_config(config)
    if not rule_config.is_rule_config(config) then
        error("card: expected a RuleConfig, got " .. type(config))
    end
end

function M.new(suit, rank)
    if type(suit) ~= "string" then
        error("card.new: suit must be a string, got " .. type(suit))
    end
    if not SUIT_SET[suit] then
        error("card.new: unknown suit " .. suit)
    end
    if type(rank) ~= "string" then
        error("card.new: rank must be a string, got " .. type(rank))
    end
    if not RANK_SET[rank] then
        error("card.new: unknown rank " .. rank)
    end
    return freeze_card(suit, rank)
end

function M.equals(a, b)
    return a.suit == b.suit and a.rank == b.rank
end

function M.tostring(card)
    return card.rank .. SUIT_GLYPHS[card.suit]
end

function M.point_value(card_or_rank, config)
    require_config(config)
    local rank = rank_of(card_or_rank)
    local value = config.cards.point_values[rank]
    if value == nil then
        error("card.point_value: unknown rank " .. tostring(rank))
    end
    return value
end

function M.trick_rank(card_or_rank, config)
    require_config(config)
    local rank = rank_of(card_or_rank)
    for i, r in ipairs(config.cards.trick_rank_order) do
        if r == rank then
            return i
        end
    end
    error("card.trick_rank: unknown rank " .. tostring(rank))
end

return M
