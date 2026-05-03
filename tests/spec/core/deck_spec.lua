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

        -- Book rule: a 9 or J at the bottom of the cut deck forces a
        -- re-cut; the third occurrence penalises the dealer. The
        -- shuffle's optional bottom-card guard closes the loophole at
        -- construction time so the penalty cannot fire (see
        -- `dealing.cut_deck_safety` in core/rule_config.lua). The
        -- guard is on by default and can be disabled per call via
        -- `{ ensure_bottom_safe = false }`.
        describe("bottom-card guard (default on)", function()
            it("never lands a 9 or J at the bottom across a wide seed sweep", function()
                local d = deck.build()
                for seed = 1, 500 do
                    local rank = deck.shuffle(d, seed)[24].rank
                    assert.are_not.equal("9", rank, "seed " .. seed)
                    assert.are_not.equal("J", rank, "seed " .. seed)
                end
            end)

            it("preserves the 24-card multiset after the swap", function()
                local d = deck.build()
                for seed = 1, 50 do
                    local s = deck.shuffle(d, seed)
                    local got = pair_multiset(s)
                    local want = expected_pairs()
                    local ok, err = are_pair_multisets_equal(got, want)
                    assert.is_true(ok, "seed " .. seed .. ": " .. tostring(err))
                end
            end)

            it("stays deterministic even when the swap fires", function()
                for _, seed in ipairs({ 0, 1, 7, 42, 12345, 1000003 }) do
                    local a = deck.shuffle(deck.build(), seed)
                    local b = deck.shuffle(deck.build(), seed)
                    for i = 1, #a do
                        assert.is_true(
                            card.equals(a[i], b[i]),
                            "seed " .. seed .. " differs at index " .. i
                        )
                    end
                end
            end)
        end)

        describe("bottom-card guard opt-out", function()
            it("returns the raw Fisher-Yates ordering when ensure_bottom_safe is false", function()
                -- Pick a seed for which Fisher-Yates leaves a 9 or J at
                -- deck[24]; assert the raw shuffle keeps it there.
                local function raw_bottom_rank(seed)
                    local copy = deck.build()
                    local state = (seed % 4294967296 + 1) % 4294967296
                    for i = #copy, 2, -1 do
                        state = (1664525 * state + 1013904223) % 4294967296
                        local j = (math.floor(state / 65536) % i) + 1
                        copy[i], copy[j] = copy[j], copy[i]
                    end
                    return copy[24].rank, copy
                end
                local seen_offence = false
                for seed = 1, 200 do
                    local rank, raw = raw_bottom_rank(seed)
                    if rank == "9" or rank == "J" then
                        seen_offence = true
                        local s = deck.shuffle(deck.build(), seed, {
                            ensure_bottom_safe = false,
                        })
                        for i = 1, #s do
                            assert.is_true(
                                card.equals(s[i], raw[i]),
                                "seed " .. seed .. " mismatch at " .. i
                            )
                        end
                    end
                end
                assert.is_true(
                    seen_offence,
                    "Fisher-Yates never produced a 9/J at deck[24] in [1, 200] "
                        .. "— widen the test sweep"
                )
            end)

            it("rejects a non-table opts argument", function()
                local d = deck.build()
                assert.has_error(function()
                    deck.shuffle(d, 1, "not a table")
                end)
                assert.has_error(function()
                    deck.shuffle(d, 1, 42)
                end)
            end)
        end)

        describe("ensure_bottom_safe()", function()
            it("returns a fresh deck with the bottom forced to a safe rank", function()
                -- Seed 1 in the canonical-then-shuffle pipeline does
                -- not trigger the guard for the first 200 seeds; pick a
                -- seed where it does, so the helper has work to do.
                local raw = deck.shuffle(deck.build(), 1, {
                    ensure_bottom_safe = false,
                })
                -- Force a known offence by swapping the first 9 we
                -- find into the bottom slot, then verify the helper
                -- repairs it without losing any cards.
                local nine_index
                for i = 1, #raw do
                    if raw[i].rank == "9" then
                        nine_index = i
                        break
                    end
                end
                assert.is_not_nil(nine_index, "no 9 in the deck — impossible")
                raw[nine_index], raw[#raw] = raw[#raw], raw[nine_index]
                assert.are.equal("9", raw[#raw].rank)

                local repaired = deck.ensure_bottom_safe(raw)
                assert.are_not.equal("9", repaired[#repaired].rank)
                assert.are_not.equal("J", repaired[#repaired].rank)

                local got = pair_multiset(repaired)
                local want = expected_pairs()
                local ok, err = are_pair_multisets_equal(got, want)
                assert.is_true(ok, tostring(err))
            end)

            it("does not mutate its input", function()
                local raw = deck.shuffle(deck.build(), 1, {
                    ensure_bottom_safe = false,
                })
                local snapshot = {}
                for i, c in ipairs(raw) do
                    snapshot[i] = c
                end
                deck.ensure_bottom_safe(raw)
                for i = 1, #snapshot do
                    assert.is_true(card.equals(snapshot[i], raw[i]))
                end
            end)

            it("is a clone-only no-op when the bottom is already safe", function()
                local d = deck.shuffle(deck.build(), 42)
                -- The default shuffle already guarantees a safe bottom.
                local repaired = deck.ensure_bottom_safe(d)
                for i = 1, #d do
                    assert.is_true(card.equals(d[i], repaired[i]))
                end
            end)

            it("rejects a non-table input", function()
                assert.has_error(function()
                    deck.ensure_bottom_safe(nil)
                end)
                assert.has_error(function()
                    deck.ensure_bottom_safe("deck")
                end)
            end)
        end)
    end)

    -- Phase 3.8: shared predicate behind both the shuffle-time guard
    -- and the procedural cut ritual. The two callers must agree on
    -- "what counts as a bad bottom card", which is why this lives as
    -- a single public helper.
    describe("is_bottom_disallowed()", function()
        it("returns true for a 9 of any suit", function()
            for _, suit in ipairs(card.SUITS) do
                assert.is_true(
                    deck.is_bottom_disallowed(card.new(suit, "9")),
                    suit .. " 9 should be disallowed"
                )
            end
        end)

        it("returns true for a J of any suit", function()
            for _, suit in ipairs(card.SUITS) do
                assert.is_true(
                    deck.is_bottom_disallowed(card.new(suit, "J")),
                    suit .. " J should be disallowed"
                )
            end
        end)

        it("returns false for Q, K, 10, A of any suit", function()
            for _, suit in ipairs(card.SUITS) do
                for _, rank in ipairs({ "Q", "K", "10", "A" }) do
                    assert.is_false(
                        deck.is_bottom_disallowed(card.new(suit, rank)),
                        suit .. " " .. rank .. " should be allowed"
                    )
                end
            end
        end)

        it("returns false for nil", function()
            assert.is_false(deck.is_bottom_disallowed(nil))
        end)
    end)
end)
