local deck = require("core.deck")
local card = require("core.card")
local rule_config = require("core.rule_config")

local config = rule_config.canonical_russian

-- A small helper: turn a list of cards into a string-keyed set so tests can
-- assert "every (suit, rank) pair appears exactly once" without depending on
-- order.
local function pair_key(c)
    return c.suit .. ":" .. c.rank
end

local function pair_multiset(cards)
    local counts = {}
    for _, c in ipairs(cards) do
        local key = pair_key(c)
        counts[key] = (counts[key] or 0) + 1
    end
    return counts
end

local function expected_pairs()
    local pairs_set = {}
    for _, suit in ipairs(card.SUITS) do
        for _, rank in ipairs(card.RANKS) do
            pairs_set[suit .. ":" .. rank] = 1
        end
    end
    return pairs_set
end

local function are_pair_multisets_equal(a, b)
    for k, v in pairs(a) do
        if b[k] ~= v then
            return false, "mismatch at " .. k
        end
    end
    for k, v in pairs(b) do
        if a[k] ~= v then
            return false, "mismatch at " .. k
        end
    end
    return true
end

describe("core.deck", function()
    describe("build()", function()
        it("returns exactly 24 cards", function()
            local d = deck.build()
            assert.are.equal(24, #d)
        end)

        it("returns one card for every suit/rank pair, with no duplicates", function()
            local d = deck.build()
            local got = pair_multiset(d)
            local want = expected_pairs()
            local ok, err = are_pair_multisets_equal(got, want)
            assert.is_true(ok, err)
        end)

        it("returns cards whose total point value under the canonical config equals 120", function()
            local d = deck.build()
            local total = 0
            for _, c in ipairs(d) do
                total = total + card.point_value(c, config)
            end
            assert.are.equal(120, total)
        end)

        it("returns frozen card instances", function()
            local d = deck.build()
            for _, c in ipairs(d) do
                assert.has_error(function()
                    c.suit = "spades"
                end)
            end
        end)

        it("returns a fresh list on every call", function()
            local first = deck.build()
            local first_len = #first
            -- Mutate the returned list in a way callers might.
            first[1] = nil
            for i = 2, first_len do
                first[i] = nil
            end
            local second = deck.build()
            assert.are.equal(24, #second)
        end)

        it("orders the deck deterministically across calls", function()
            local a = deck.build()
            local b = deck.build()
            assert.are.equal(#a, #b)
            for i = 1, #a do
                assert.is_true(card.equals(a[i], b[i]))
            end
        end)
    end)

    describe("shuffle()", function()
        it("returns a 24-card permutation of the input deck", function()
            local d = deck.build()
            local s = deck.shuffle(d, 42)
            assert.are.equal(24, #s)
            local got = pair_multiset(s)
            local want = expected_pairs()
            local ok, err = are_pair_multisets_equal(got, want)
            assert.is_true(ok, err)
        end)

        it("is reproducible: the same input and seed yield identical orderings", function()
            local d1 = deck.build()
            local d2 = deck.build()
            local a = deck.shuffle(d1, 12345)
            local b = deck.shuffle(d2, 12345)
            assert.are.equal(#a, #b)
            for i = 1, #a do
                local detail = card.tostring(a[i]) .. " vs " .. card.tostring(b[i])
                assert.is_true(card.equals(a[i], b[i]), "mismatch at index " .. i .. ": " .. detail)
            end
        end)

        it("differs from the canonical order for at least one seed", function()
            local d = deck.build()
            local s = deck.shuffle(d, 7)
            local same_order = true
            for i = 1, #d do
                if not card.equals(d[i], s[i]) then
                    same_order = false
                    break
                end
            end
            assert.is_false(same_order, "shuffle produced canonical order — RNG looks broken")
        end)

        it("produces different orderings for different seeds", function()
            local d = deck.build()
            local a = deck.shuffle(d, 1)
            local b = deck.shuffle(d, 2)
            local identical = true
            for i = 1, #a do
                if not card.equals(a[i], b[i]) then
                    identical = false
                    break
                end
            end
            assert.is_false(identical, "two distinct seeds produced identical orderings")
        end)

        it("does not mutate the input deck", function()
            local d = deck.build()
            local snapshot = {}
            for i, c in ipairs(d) do
                snapshot[i] = c
            end
            deck.shuffle(d, 99)
            assert.are.equal(#snapshot, #d)
            for i = 1, #snapshot do
                assert.is_true(card.equals(snapshot[i], d[i]))
            end
        end)

        it("rejects a non-table deck", function()
            assert.has_error(function()
                deck.shuffle(nil, 1)
            end)
            assert.has_error(function()
                deck.shuffle("not a deck", 1)
            end)
            assert.has_error(function()
                deck.shuffle(42, 1)
            end)
        end)

        it("rejects a non-integer seed", function()
            local d = deck.build()
            assert.has_error(function()
                deck.shuffle(d, nil)
            end)
            assert.has_error(function()
                deck.shuffle(d, "42")
            end)
            assert.has_error(function()
                deck.shuffle(d, 1.5)
            end)
        end)
    end)
end)
