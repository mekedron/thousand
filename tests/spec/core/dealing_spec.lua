local dealing = require("core.dealing")
local deck_module = require("core.deck")
local card = require("core.card")
local rule_config = require("core.rule_config")

local config = rule_config.canonical_russian

-- Build a representative table: spec helper that mirrors the canonical
-- shape so a single field can be perturbed without redefining everything.
local function valid_config_table()
    return {
        schema_version = 1,
        cards = {
            point_values = {
                ["A"] = 11,
                ["10"] = 10,
                ["K"] = 4,
                ["Q"] = 3,
                ["J"] = 2,
                ["9"] = 0,
            },
            trick_rank_order = { "9", "J", "Q", "K", "10", "A" },
        },
        players = {
            count = 3,
            partnership_mode = "none",
            four_player_config = "dealer_plays_no_talon",
            two_player_config = "closed_talon_draw_stock",
        },
        dealing = {
            four_nine_redeal = "off",
            three_nine_redeal = "off",
            four_jack_redeal = "off",
            weak_hand_redeal = "off",
            weak_hand_threshold = 14,
            misdeal_handling = "standard",
            misdeal_flat_penalty = 20,
            all_pass_handling = "redeal",
        },
        talon = {
            size = 3,
            distribution = "declarer_takes_then_passes",
            flip_after_first_round = "off",
            pass_the_talon = "off",
            buyback = "off",
            hidden_on_minimum_100 = "off",
            bad_talon_redeal = "off",
            rebuy = "off",
            open_discard = "off",
        },
        bidding = {
            opening_min = 100,
            pre_talon_max = 120,
            increment_threshold = 200,
            increment_below_200 = 5,
            increment_from_200 = 10,
            forced_opening = "off",
            forced_dealer_bid = "off",
            blind_bid = "off",
            re_entry_after_pass = "off",
            contra = "off",
            forced_bid_concession = "off",
            no_contract_without_marriage = "off",
            negative_score_restriction = "off",
            named_contracts = "off",
        },
        marriages = {
            values = { hearts = 100, diamonds = 80, clubs = 60, spades = 40 },
            half_marriage_capture_bonus = "off",
            trump_activation_timing = "next_trick",
            marriage_announcement_timing = "on_lead",
            drowned_marriage = "off",
            ace_marriage = "off",
            one_trump_per_deal = "off",
        },
        tricks = {
            must_follow = true,
            must_beat = true,
            must_trump = true,
            must_overtrump = true,
            must_overtake_strictness = "standard",
            must_trump_strictness = "standard",
            defender_must_overtrump_declarer = "off",
            lazy_revoke = "off",
            partial_trumping = "off",
            last_trick_bonus = "off",
            slam_bonus = "off",
            slam_against_penalty = "off",
            lead_trump_after_marriage = "off",
        },
        scoring = {
            round_to_nearest = 5,
            actual_points_on_success = "off",
            defender_contributions = "standard",
            failed_contract_distribution = "lost",
            declarer_rounding_before_contract_check = "off",
        },
        opening_game = { golden_deal = "off" },
        barrel = {
            threshold = 880,
            deal_count = 3,
            fall_off_penalty = -120,
            pit_lock_in = "off",
            collision_rule = "last_mounter",
            overshoot_penalty = "off",
            reverse_barrel = "off",
        },
        endgame = {
            target_score = 1000,
            going_over_target = "win_immediately",
            tiebreaker = "declarer_wins",
            dump_truck = "off",
        },
        specials = {
            mizere = "off",
            slam_contract = "off",
            open_hand = "off",
        },
        penalties = {
            revoke = "standard",
            talon_look = "standard",
            showing_hand = "standard",
            zero_tricks = "off",
            cross = "off",
        },
    }
end

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

local function expected_pair_multiset()
    local pairs_set = {}
    for _, suit in ipairs(card.SUITS) do
        for _, rank in ipairs(card.RANKS) do
            pairs_set[suit .. ":" .. rank] = 1
        end
    end
    return pairs_set
end

local function multisets_equal(a, b)
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

local function flatten(result)
    local all = {}
    for _, hand in ipairs(result.hands) do
        for _, c in ipairs(hand) do
            all[#all + 1] = c
        end
    end
    for _, c in ipairs(result.talon) do
        all[#all + 1] = c
    end
    return all
end

local function snapshot(list)
    local copy = {}
    for i, v in ipairs(list) do
        copy[i] = v
    end
    return copy
end

describe("core.dealing", function()
    describe("deal() happy path", function()
        it("returns ok=true with three 7-card hands and a 3-card talon", function()
            local d = deck_module.build()
            local result = dealing.deal(d, config)
            assert.is_true(result.ok)
            assert.is_nil(result.error)
            assert.are.equal(3, #result.hands)
            for i = 1, 3 do
                assert.are.equal(7, #result.hands[i], "hand " .. i .. " has wrong size")
            end
            assert.are.equal(3, #result.talon)
        end)

        it("partitions all 24 unique cards across hands and talon", function()
            local d = deck_module.build()
            local result = dealing.deal(d, config)
            assert.is_true(result.ok)
            local all = flatten(result)
            assert.are.equal(24, #all)
            local got = pair_multiset(all)
            local want = expected_pair_multiset()
            local ok, err = multisets_equal(got, want)
            assert.is_true(ok, err)
        end)

        it("conserves the 120-point invariant across hands and talon", function()
            local d = deck_module.build()
            local result = dealing.deal(d, config)
            assert.is_true(result.ok)
            local total = 0
            for _, c in ipairs(flatten(result)) do
                total = total + card.point_value(c, config)
            end
            assert.are.equal(120, total)
        end)
    end)

    describe("deal sequence", function()
        -- The documented pattern in docs/rules/dealing.md is:
        --
        --   3 + 3 + 3   to each player                (9 in hands, 0 in talon)
        --   2           to the talon
        --   2 + 2       to each player                (15 in hands, 2 in talon)
        --   1           to the talon
        --   2 + 2       to each player                (21 in hands, 3 in talon)
        --
        -- Implemented as a per-player chunk walk: each "x to each player" step
        -- hands x cards in one chunk to player 1, then x to player 2, then x
        -- to player 3, before the next step starts. This is the simplest
        -- reading consistent with the totals and is what the engine encodes.
        it("places deck positions on the documented hands and talon slots", function()
            local d = deck_module.build()
            local result = dealing.deal(d, config)
            assert.is_true(result.ok)

            local function expect_positions(hand, indices)
                assert.are.equal(#indices, #hand)
                for k, idx in ipairs(indices) do
                    assert.is_true(
                        card.equals(d[idx], hand[k]),
                        "expected card at deck position "
                            .. idx
                            .. " ("
                            .. card.tostring(d[idx])
                            .. "), got "
                            .. card.tostring(hand[k])
                    )
                end
            end

            expect_positions(result.hands[1], { 1, 2, 3, 12, 13, 19, 20 })
            expect_positions(result.hands[2], { 4, 5, 6, 14, 15, 21, 22 })
            expect_positions(result.hands[3], { 7, 8, 9, 16, 17, 23, 24 })
            expect_positions(result.talon, { 10, 11, 18 })
        end)

        it("produces the same partition for the same input deck", function()
            local d = deck_module.build()
            local a = dealing.deal(d, config)
            local b = dealing.deal(d, config)
            assert.is_true(a.ok and b.ok)
            for i = 1, 3 do
                for k = 1, 7 do
                    assert.is_true(card.equals(a.hands[i][k], b.hands[i][k]))
                end
            end
            for k = 1, 3 do
                assert.is_true(card.equals(a.talon[k], b.talon[k]))
            end
        end)

        it("uses a shuffled deck deterministically when the caller seeds it", function()
            local fresh = deck_module.shuffle(deck_module.build(), 42)
            local result_a = dealing.deal(fresh, config)
            local result_b = dealing.deal(deck_module.shuffle(deck_module.build(), 42), config)
            assert.is_true(result_a.ok and result_b.ok)
            for i = 1, 3 do
                for k = 1, 7 do
                    assert.is_true(card.equals(result_a.hands[i][k], result_b.hands[i][k]))
                end
            end
            for k = 1, 3 do
                assert.is_true(card.equals(result_a.talon[k], result_b.talon[k]))
            end
        end)
    end)

    describe("deal() purity", function()
        it("does not mutate the input deck", function()
            local d = deck_module.build()
            local before = snapshot(d)
            dealing.deal(d, config)
            assert.are.equal(#before, #d)
            for i = 1, #before do
                assert.is_true(card.equals(before[i], d[i]))
            end
        end)

        it("returns a fresh hands list on every call", function()
            local d = deck_module.build()
            local first = dealing.deal(d, config)
            assert.is_true(first.ok)
            -- Mutate the returned hand; a second call must not see it.
            first.hands[1][1] = nil
            local second = dealing.deal(d, config)
            assert.is_true(second.ok)
            assert.are.equal(7, #second.hands[1])
        end)
    end)

    describe("deal() rejects bad config", function()
        it("rejects a non-RuleConfig argument", function()
            local d = deck_module.build()
            local cases = { nil, 42, "config", {}, true }
            for _, bad in ipairs(cases) do
                local result = dealing.deal(d, bad)
                assert.is_false(result.ok)
                assert.are.equal("not_a_rule_config", result.error.code)
            end
        end)

        -- Phase 3.6 lifted the count != 3 guard for 2- and 4-player
        -- layouts. The dealer still rejects the Polish 2-card-talon
        -- shape because the talon-variants gameplay task hasn't landed
        -- yet — that pin lives below in the polish-shape test.

        it("rejects the Polish 2-card-talon shape", function()
            local t = valid_config_table()
            t.talon.size = 2
            local odd = rule_config.new(t)
            local result = dealing.deal(deck_module.build(), odd)
            assert.is_false(result.ok)
            assert.are.equal("unsupported_talon_size", result.error.code)
            assert.are.equal(2, result.error.talon_size)
        end)
    end)

    describe("deal() rejects bad decks", function()
        it("rejects a non-table deck", function()
            for _, bad in ipairs({ nil, 42, "deck", true }) do
                local result = dealing.deal(bad, config)
                assert.is_false(result.ok)
                assert.are.equal("wrong_deck_size", result.error.code)
            end
        end)

        it("rejects a deck of the wrong size", function()
            local short = deck_module.build()
            short[24] = nil
            local short_result = dealing.deal(short, config)
            assert.is_false(short_result.ok)
            assert.are.equal("wrong_deck_size", short_result.error.code)
            assert.are.equal(23, short_result.error.actual)
            assert.are.equal(24, short_result.error.expected)

            local long = deck_module.build()
            long[25] = card.new("hearts", "A")
            local long_result = dealing.deal(long, config)
            assert.is_false(long_result.ok)
            assert.are.equal("wrong_deck_size", long_result.error.code)
            assert.are.equal(25, long_result.error.actual)
        end)

        it("rejects a deck containing non-card entries", function()
            local d = deck_module.build()
            d[5] = "not a card"
            local result = dealing.deal(d, config)
            assert.is_false(result.ok)
            assert.are.equal("not_a_card", result.error.code)
            assert.are.equal(5, result.error.index)
        end)

        it("rejects a deck containing duplicate cards", function()
            local d = deck_module.build()
            -- Replace position 24 with a duplicate of position 1.
            d[24] = card.new(d[1].suit, d[1].rank)
            local result = dealing.deal(d, config)
            assert.is_false(result.ok)
            assert.are.equal("duplicate_card", result.error.code)
            assert.are.equal(d[1].suit, result.error.suit)
            assert.are.equal(d[1].rank, result.error.rank)
            assert.are.equal(24, result.error.index)
        end)
    end)
end)
