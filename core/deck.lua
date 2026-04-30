-- The Thousand 24-card deck.
--
-- A deck is a fresh ordered list of all 24 cards in the stripped pack: every
-- combination of `core.card.SUITS` × `core.card.RANKS`, with no duplicates and
-- no extras. `build()` returns the deck in a fixed canonical order; `shuffle`
-- returns a permutation given an integer seed and never mutates its input.
--
-- The shuffle is intentionally seeded by a small private LCG rather than the
-- global `math.random` state. Lua's stdlib RNG is process-global, so threading
-- shuffles through it would let unrelated code (other tests, the engine,
-- third-party libraries) perturb our determinism contract. A self-contained
-- generator keeps reproducibility local to the call site, which the tests
-- depend on.
--
-- LCG choice: Numerical Recipes constants `a=1664525, c=1013904223, m=2^32`.
-- One step is `state := (a*state + c) mod m`. The intermediate product fits
-- inside Lua's 53-bit double mantissa (max ≈ 7.15e15 ≪ 2^53 ≈ 9e15), so no
-- precision loss on LuaJIT or stock Lua 5.1.

local card = require("core.card")

local M = {}

local LCG_A = 1664525
local LCG_C = 1013904223
local LCG_M = 4294967296 -- 2^32

local function lcg_next(state)
    return (LCG_A * state + LCG_C) % LCG_M
end

-- Returns an integer uniformly in [1, n] derived from the LCG state. Uses the
-- top bits of the 32-bit output for a slightly better distribution than the
-- low bits, which is the conventional advice for LCGs of this family.
local function lcg_int(state, n)
    local next_state = lcg_next(state)
    local top = math.floor(next_state / 65536) -- top 16 bits of the 32-bit word
    local index = (top % n) + 1
    return next_state, index
end

local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

function M.build()
    local cards = {}
    local i = 0
    for _, suit in ipairs(card.SUITS) do
        for _, rank in ipairs(card.RANKS) do
            i = i + 1
            cards[i] = card.new(suit, rank)
        end
    end
    return cards
end

function M.shuffle(deck, seed)
    if type(deck) ~= "table" then
        error("deck.shuffle: deck must be a table, got " .. type(deck))
    end
    if not is_integer(seed) then
        error("deck.shuffle: seed must be an integer")
    end

    local copy = {}
    for i, c in ipairs(deck) do
        copy[i] = c
    end

    -- Fold the seed into the LCG state. The +1 keeps a seed of 0 from
    -- collapsing the first step to a constant offset.
    local state = (seed % LCG_M + 1) % LCG_M

    -- In-place Fisher-Yates over the copy, walking from the end down. At each
    -- step we draw j ∈ [1, i] and swap positions i and j. Every permutation of
    -- the n! possibilities is reachable; the LCG just decides which.
    for i = #copy, 2, -1 do
        local j
        state, j = lcg_int(state, i)
        copy[i], copy[j] = copy[j], copy[i]
    end

    return copy
end

return M
