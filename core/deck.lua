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
--
-- Bottom-card guard. The reference book's procedural rule forbids a 9 or J
-- from landing at the very end of the deck after the cut: physical play
-- re-cuts up to three times before penalising the dealer. The shuffle's
-- final step swaps the bottom card with the first non-{9,J} card it finds
-- when the offence applies, so the case never arises in software and the
-- procedural penalty (`dealing.cut_deck_nine_jack_penalty`) is always inert.
-- The guard is gated by the caller through the `ensure_bottom_safe` option
-- on `M.shuffle`; the session layer drives it from the
-- `dealing.cut_deck_safety` config field. Determinism is preserved either
-- way because the swap is a function of the post-Fisher-Yates ordering —
-- same seed, same opts, same outcome.

local card = require("core.card")

local M = {}

local LCG_A = 1664525
local LCG_C = 1013904223
local LCG_M = 4294967296 -- 2^32

local BOTTOM_DISALLOWED_RANKS = {
    ["9"] = true,
    ["J"] = true,
}

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

-- Public predicate: true when a card is one of the disallowed bottom
-- ranks (9 or J). Single source of truth for the bottom-of-deck check
-- shared by `apply_bottom_safe` (the shuffle-time guard) and
-- `Session:cut_deck()` (the procedural ritual under
-- `dealing.cut_deck_nine_jack_penalty = "on"`). Returns false for nil
-- so callers can pipe an optional bottom card straight through.
function M.is_bottom_disallowed(c)
    if c == nil then
        return false
    end
    return BOTTOM_DISALLOWED_RANKS[c.rank] == true
end

-- Book rule: a 9 or J at the end of the deck must trigger a re-cut at the
-- physical table. We close the loophole at shuffle time so the procedural
-- penalty cannot fire: walk forward to find the first card with a safe
-- rank, swap it with the bottom. Every standard Thousand deck holds at
-- least 16 safe cards (everything except the four 9s and four Js), so a
-- partner is always available.
local function apply_bottom_safe(deck)
    if not M.is_bottom_disallowed(deck[#deck]) then
        return
    end
    for i = 1, #deck - 1 do
        if not M.is_bottom_disallowed(deck[i]) then
            deck[i], deck[#deck] = deck[#deck], deck[i]
            return
        end
    end
end

-- Public helper: returns a fresh deck with deck[#deck] guaranteed not to
-- be a 9 or J. Idempotent — applying it to an already-safe deck is a
-- no-op clone. Pulled out so callers can apply the guard to any deck
-- shape, not just one freshly off `M.shuffle`.
function M.ensure_bottom_safe(deck)
    if type(deck) ~= "table" then
        error("deck.ensure_bottom_safe: deck must be a table, got " .. type(deck))
    end
    local copy = {}
    for i, c in ipairs(deck) do
        copy[i] = c
    end
    apply_bottom_safe(copy)
    return copy
end

function M.shuffle(deck, seed, opts)
    if type(deck) ~= "table" then
        error("deck.shuffle: deck must be a table, got " .. type(deck))
    end
    if not is_integer(seed) then
        error("deck.shuffle: seed must be an integer")
    end
    -- Default guard on. Callers that want the raw Fisher-Yates ordering
    -- pass `{ ensure_bottom_safe = false }`; the session layer drives
    -- this from `dealing.cut_deck_safety`.
    local guard = true
    if opts ~= nil then
        if type(opts) ~= "table" then
            error("deck.shuffle: opts must be a table, got " .. type(opts))
        end
        if opts.ensure_bottom_safe == false then
            guard = false
        end
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

    if guard then
        apply_bottom_safe(copy)
    end

    return copy
end

return M
