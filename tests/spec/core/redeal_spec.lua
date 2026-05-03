local redeal = require("core.redeal")
local card = require("core.card")
local rule_config = require("core.rule_config")

-- Cards are constructed fresh per fixture so each test owns its hand.
local function c(suit, rank)
    return card.new(suit, rank)
end

local FOUR_NINES = {
    c("spades", "9"),
    c("clubs", "9"),
    c("diamonds", "9"),
    c("hearts", "9"),
}

local FOUR_JACKS = {
    c("spades", "J"),
    c("clubs", "J"),
    c("diamonds", "J"),
    c("hearts", "J"),
}

local THREE_NINES_PLUS_K = {
    c("spades", "9"),
    c("clubs", "9"),
    c("diamonds", "9"),
    c("hearts", "K"),
}

local STRICT_WEAK = {
    -- Only 9s and 10s; no marriage, no Ace.
    c("spades", "9"),
    c("clubs", "9"),
    c("diamonds", "10"),
    c("hearts", "10"),
    c("spades", "10"),
    c("clubs", "10"),
}

local LOOSE_WEAK = {
    -- No marriage (no K+Q same suit) and no Ace, but holds K and Q in
    -- different suits, so face-cards above 10 disqualify it from strict.
    c("spades", "K"),
    c("clubs", "Q"),
    c("diamonds", "J"),
    c("hearts", "9"),
    c("spades", "10"),
    c("clubs", "9"),
}

local HAS_MARRIAGE = {
    c("spades", "K"),
    c("spades", "Q"),
    c("clubs", "J"),
    c("hearts", "9"),
    c("diamonds", "10"),
    c("clubs", "10"),
}

local HAS_ACE = {
    c("spades", "A"),
    c("clubs", "10"),
    c("diamonds", "9"),
    c("hearts", "9"),
}

-- Plain hand of mixed mid-rank cards, no entitlement under any rule.
local NEUTRAL_HAND = {
    c("spades", "K"),
    c("spades", "Q"), -- spades marriage
    c("clubs", "A"),
    c("hearts", "10"),
    c("diamonds", "J"),
    c("hearts", "K"),
    c("clubs", "9"),
}

-- Build a config that has every dealing toggle "off" except the named
-- overrides. Mirrors `valid_table()` from `rule_config_spec.lua` but
-- exposes a `dealing = {...}` perturbation.
local function config_with_dealing(overrides)
    overrides = overrides or {}
    local d = {
        four_nine_redeal = "off",
        three_nine_redeal = "off",
        four_jack_redeal = "off",
        weak_hand_redeal = "off",
        weak_hand_threshold = 14,
        two_nines_in_talon_redeal = "off",
        misdeal_handling = "standard",
        misdeal_flat_penalty = 20,
        all_pass_handling = "redeal",
        deck_size = "24",
        cut_deck_nine_jack_penalty = "off",
    }
    for k, v in pairs(overrides) do
        d[k] = v
    end
    local blob = {
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
        dealing = d,
        talon = {
            size = 3,
            distribution = "declarer_takes_then_passes",
            flip_after_first_round = "off",
            pass_the_talon = "off",
            buyback = "off",
            buyback_penalty = 50,
            hidden_on_minimum_100 = "off",
            bad_talon_redeal = "off",
            bad_talon_threshold = 5,
            rebuy = "off",
            rebuy_contract_value = 240,
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
            blind_bid_success_multiplier = 2,
            blind_bid_failure_multiplier = 2,
            re_entry_after_pass = "off",
            contra = "off",
            contra_multiplier = 2,
            redouble_multiplier = 2,
            forced_bid_concession = "off",
            forced_bid_concession_preset_ratio = { 0.5, 0.5 },
            write_off = "off",
            write_off_split = "half_to_each",
            no_contract_without_marriage = "off",
            negative_score_restriction = "off",
            named_contracts = "off",
            named_contracts_precedence = { "mizere", "open_hand", "slam" },
        },
        marriages = {
            values = { hearts = 100, diamonds = 80, clubs = 60, spades = 40 },
            half_marriage_capture_bonus = "off",
            half_marriage_capture_bonus_value = 20,
            trump_activation_timing = "next_trick",
            marriage_announcement_timing = "on_lead",
            drowned_marriage = "off",
            ace_marriage = "off",
            ace_marriage_value = 200,
            one_trump_per_deal = "off",
            trick_required = "on",
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
            last_trick_bonus_value = 10,
            slam_bonus = "off",
            slam_bonus_value = 60,
            slam_against_penalty = "off",
            slam_against_penalty_value = 120,
            lead_trump_after_marriage = "off",
        },
        scoring = {
            round_to_nearest = 5,
            actual_points_on_success = "off",
            defender_contributions = "standard",
            failed_contract_distribution = "lost",
            declarer_rounding_before_contract_check = "off",
        },
        opening_game = {
            golden_deal = "off",
            golden_deal_count = 3,
            golden_deal_marriages_doubled = "off",
            golden_deal_blind_allowed = "off",
            golden_deal_penalty_doubled = "off",
            golden_deal_failure_handling = "continue",
        },
        barrel = {
            threshold = 880,
            deal_count = 3,
            fall_off_penalty = -120,
            pit_lock_in = "off",
            pit_score = 700,
            collision_rule = "last_mounter",
            overshoot_penalty = "off",
            fall_count_resets_to_zero = "off",
            reverse_barrel = "off",
            reverse_barrel_fallback = -760,
        },
        endgame = {
            target_score = 1000,
            going_over_target = "win_immediately",
            tiebreaker = "declarer_wins",
            dump_truck = "off",
            dump_truck_threshold = 555,
        },
        specials = {
            mizere = "off",
            mizere_contract_value = 120,
            slam_contract = "off",
            slam_contract_value = 240,
            open_hand = "off",
        },
        penalties = {
            revoke = "standard",
            revoke_configurable_amount = 120,
            talon_look = "standard",
            showing_hand = "standard",
            zero_tricks = "off",
            zero_tricks_threshold = 3,
            zero_tricks_penalty_amount = 120,
            zero_tricks_declarer_exempt = "off",
            zero_tricks_golden_deal_doubled = "off",
            zero_tricks_dark_game_doubled = "off",
            write_off_streak = "off",
            write_off_streak_threshold = 3,
            write_off_streak_penalty_amount = 120,
            no_win_streak = "off",
            no_win_streak_threshold = 3,
            no_win_streak_penalty_amount = 120,
            cross = "off",
            cross_penalty_amount = 120,
        },
    }
    return rule_config.new(blob)
end

describe("core.redeal", function()
    describe("has_four_nines", function()
        it("returns true on all four 9s", function()
            assert.is_true(redeal.has_four_nines(FOUR_NINES))
        end)

        it("returns false on three 9s plus another rank", function()
            assert.is_false(redeal.has_four_nines(THREE_NINES_PLUS_K))
        end)

        it("returns false on a hand with no 9s", function()
            assert.is_false(redeal.has_four_nines(STRICT_WEAK)) -- has 9s but not four
            assert.is_false(redeal.has_four_nines(NEUTRAL_HAND))
        end)
    end)

    describe("has_three_nines", function()
        it("returns true on exactly three 9s", function()
            assert.is_true(redeal.has_three_nines(THREE_NINES_PLUS_K))
        end)

        it("returns false on four 9s", function()
            assert.is_false(redeal.has_three_nines(FOUR_NINES))
        end)

        it("returns false on a hand with fewer 9s", function()
            assert.is_false(redeal.has_three_nines(NEUTRAL_HAND))
        end)
    end)

    describe("has_four_jacks", function()
        it("returns true on all four Jacks", function()
            assert.is_true(redeal.has_four_jacks(FOUR_JACKS))
        end)

        it("returns false on three Jacks", function()
            local hand = {
                c("spades", "J"),
                c("clubs", "J"),
                c("diamonds", "J"),
                c("hearts", "10"),
            }
            assert.is_false(redeal.has_four_jacks(hand))
        end)

        it("returns false on a hand with no Jacks", function()
            assert.is_false(redeal.has_four_jacks(FOUR_NINES))
        end)
    end)

    describe("is_weak_hand", function()
        local config = rule_config.canonical_russian

        it("returns false when mode is 'off' or nil", function()
            assert.is_false(redeal.is_weak_hand(STRICT_WEAK, "off", 14, config))
            assert.is_false(redeal.is_weak_hand(STRICT_WEAK, nil, 14, config))
        end)

        describe("strict mode", function()
            it("accepts a hand of only 9s and 10s", function()
                assert.is_true(redeal.is_weak_hand(STRICT_WEAK, "strict", nil, config))
            end)

            it("rejects a hand that contains a Jack", function()
                local hand = {
                    c("spades", "9"),
                    c("clubs", "10"),
                    c("diamonds", "J"),
                }
                assert.is_false(redeal.is_weak_hand(hand, "strict", nil, config))
            end)

            it("rejects a hand that contains a King", function()
                local hand = {
                    c("spades", "9"),
                    c("clubs", "10"),
                    c("diamonds", "K"),
                }
                assert.is_false(redeal.is_weak_hand(hand, "strict", nil, config))
            end)

            it("rejects a hand that contains an Ace", function()
                assert.is_false(redeal.is_weak_hand(HAS_ACE, "strict", nil, config))
            end)
        end)

        describe("loose mode", function()
            it("accepts a hand without marriage and without Ace", function()
                assert.is_true(redeal.is_weak_hand(LOOSE_WEAK, "loose", nil, config))
            end)

            it("rejects a hand with a marriage", function()
                assert.is_false(redeal.is_weak_hand(HAS_MARRIAGE, "loose", nil, config))
            end)

            it("rejects a hand with an Ace", function()
                assert.is_false(redeal.is_weak_hand(HAS_ACE, "loose", nil, config))
            end)
        end)

        describe("counted mode", function()
            it("accepts a hand with card-points strictly below the threshold", function()
                -- STRICT_WEAK has 4 tens (40 pts) + 2 nines (0 pts) = 40 pts.
                -- A threshold of 50 makes it eligible.
                assert.is_true(redeal.is_weak_hand(STRICT_WEAK, "counted", 50, config))
            end)

            it("rejects a hand with card-points equal to or above the threshold", function()
                -- STRICT_WEAK has 40 pts. Threshold 40 → 40 < 40 is false.
                assert.is_false(redeal.is_weak_hand(STRICT_WEAK, "counted", 40, config))
                -- Threshold 30 → 40 < 30 is also false.
                assert.is_false(redeal.is_weak_hand(STRICT_WEAK, "counted", 30, config))
            end)

            it("returns false when threshold is missing", function()
                assert.is_false(redeal.is_weak_hand(STRICT_WEAK, "counted", nil, config))
            end)
        end)
    end)

    describe("entitled_offer", function()
        local function deal_three(h1, h2, h3)
            return { h1, h2, h3 }
        end

        it("returns nil when every dealing toggle is at default", function()
            local config = config_with_dealing()
            local hands = deal_three(FOUR_NINES, FOUR_JACKS, NEUTRAL_HAND)
            assert.is_nil(redeal.entitled_offer(hands, config))
        end)

        it("flags four_nine as forced under mandatory mode", function()
            local config = config_with_dealing({ four_nine_redeal = "mandatory" })
            local hands = deal_three(NEUTRAL_HAND, FOUR_NINES, NEUTRAL_HAND)
            local offer = redeal.entitled_offer(hands, config)
            assert.are.same({ seat = 2, kind = "four_nine", forced = true }, offer)
        end)

        it("flags four_nine as not forced under optional mode", function()
            local config = config_with_dealing({ four_nine_redeal = "optional" })
            local hands = deal_three(FOUR_NINES, NEUTRAL_HAND, NEUTRAL_HAND)
            local offer = redeal.entitled_offer(hands, config)
            assert.are.same({ seat = 1, kind = "four_nine", forced = false }, offer)
        end)

        it("returns nil for four_nine when the rule is off", function()
            local config = config_with_dealing({ four_nine_redeal = "off" })
            local hands = deal_three(FOUR_NINES, NEUTRAL_HAND, NEUTRAL_HAND)
            assert.is_nil(redeal.entitled_offer(hands, config))
        end)

        it("flags four_jack optional when a hand holds all four Jacks", function()
            local config = config_with_dealing({ four_jack_redeal = "optional" })
            local hands = deal_three(NEUTRAL_HAND, NEUTRAL_HAND, FOUR_JACKS)
            local offer = redeal.entitled_offer(hands, config)
            assert.are.same({ seat = 3, kind = "four_jack", forced = false }, offer)
        end)

        it("flags four_jack mandatory as forced", function()
            local config = config_with_dealing({ four_jack_redeal = "mandatory" })
            local hands = deal_three(NEUTRAL_HAND, FOUR_JACKS, NEUTRAL_HAND)
            local offer = redeal.entitled_offer(hands, config)
            assert.are.same({ seat = 2, kind = "four_jack", forced = true }, offer)
        end)

        it("flags three_nine mandatory as forced", function()
            local config = config_with_dealing({ three_nine_redeal = "mandatory" })
            local hands = deal_three(NEUTRAL_HAND, THREE_NINES_PLUS_K, NEUTRAL_HAND)
            local offer = redeal.entitled_offer(hands, config)
            assert.are.same({ seat = 2, kind = "three_nine", forced = true }, offer)
        end)

        it("prefers four_nine mandatory over four_jack when both fire", function()
            local config = config_with_dealing({
                four_nine_redeal = "mandatory",
                four_jack_redeal = "optional",
            })
            local hands = deal_three(FOUR_JACKS, FOUR_NINES, NEUTRAL_HAND)
            local offer = redeal.entitled_offer(hands, config)
            assert.are.same({ seat = 2, kind = "four_nine", forced = true }, offer)
        end)

        it("prefers four_jack over three_nine when both fire", function()
            local config = config_with_dealing({
                four_jack_redeal = "optional",
                three_nine_redeal = "optional",
            })
            local hands = deal_three(THREE_NINES_PLUS_K, FOUR_JACKS, NEUTRAL_HAND)
            local offer = redeal.entitled_offer(hands, config)
            assert.are.same({ seat = 2, kind = "four_jack", forced = false }, offer)
        end)

        it("a mandatory rule of any kind beats every optional rule", function()
            -- four_nine optional + four_jack mandatory: four_jack wins
            -- because mandatory beats optional, even though four_nine is
            -- the higher kind.
            local config = config_with_dealing({
                four_nine_redeal = "optional",
                four_jack_redeal = "mandatory",
            })
            local hands = deal_three(FOUR_NINES, FOUR_JACKS, NEUTRAL_HAND)
            local offer = redeal.entitled_offer(hands, config)
            assert.are.same({ seat = 2, kind = "four_jack", forced = true }, offer)
        end)

        it("flags three_nine when enabled and a hand has exactly three 9s", function()
            local config = config_with_dealing({ three_nine_redeal = "optional" })
            local hands = deal_three(NEUTRAL_HAND, THREE_NINES_PLUS_K, NEUTRAL_HAND)
            local offer = redeal.entitled_offer(hands, config)
            assert.are.same({ seat = 2, kind = "three_nine", forced = false }, offer)
        end)

        it("does not flag three_nine when only four 9s are held", function()
            local config = config_with_dealing({ three_nine_redeal = "optional" })
            local hands = deal_three(FOUR_NINES, NEUTRAL_HAND, NEUTRAL_HAND)
            assert.is_nil(redeal.entitled_offer(hands, config))
        end)

        it("flags weak_hand strict for a hand of only 9s and 10s", function()
            local config = config_with_dealing({ weak_hand_redeal = "strict" })
            local hands = deal_three(NEUTRAL_HAND, NEUTRAL_HAND, STRICT_WEAK)
            local offer = redeal.entitled_offer(hands, config)
            assert.are.same({ seat = 3, kind = "weak_hand", forced = false }, offer)
        end)

        it("flags weak_hand loose for a hand without marriage or Ace", function()
            local config = config_with_dealing({ weak_hand_redeal = "loose" })
            local hands = deal_three(NEUTRAL_HAND, LOOSE_WEAK, NEUTRAL_HAND)
            local offer = redeal.entitled_offer(hands, config)
            assert.are.same({ seat = 2, kind = "weak_hand", forced = false }, offer)
        end)

        it("flags weak_hand counted when the hand is below threshold", function()
            local config = config_with_dealing({
                weak_hand_redeal = "counted",
                weak_hand_threshold = 30,
            })
            -- STRICT_WEAK has 40 card-points (four 10s + two 9s), so 40 <
            -- 30 is false; the only-9s hand has 0, so it qualifies.
            local only_nines = {
                c("spades", "9"),
                c("clubs", "9"),
                c("diamonds", "9"),
            }
            local hands = deal_three(STRICT_WEAK, only_nines, NEUTRAL_HAND)
            local offer = redeal.entitled_offer(hands, config)
            assert.are.same({ seat = 2, kind = "weak_hand", forced = false }, offer)
        end)

        it("returns the lowest-seated entitlement at a given priority", function()
            local config = config_with_dealing({ four_nine_redeal = "optional" })
            local hands = deal_three(FOUR_NINES, FOUR_NINES, NEUTRAL_HAND)
            local offer = redeal.entitled_offer(hands, config)
            assert.are.equal(1, offer.seat)
        end)

        it("walks all four seats under a 4-player config", function()
            local config = config_with_dealing({ four_jack_redeal = "optional" })
            -- Override player count and add a fourth seat.
            local blob = rule_config.to_json(config)
            local res = rule_config.from_json(blob)
            assert.is_true(res.ok)
            -- Re-build via a plain table to flip count to 4.
            local t = {
                schema_version = 1,
                cards = res.config.cards,
                players = {
                    count = 4,
                    partnership_mode = "none",
                    four_player_config = "dealer_plays_no_talon",
                    two_player_config = "closed_talon_draw_stock",
                },
                dealing = res.config.dealing,
                talon = res.config.talon,
                bidding = res.config.bidding,
                marriages = res.config.marriages,
                tricks = res.config.tricks,
                scoring = res.config.scoring,
                opening_game = res.config.opening_game,
                barrel = res.config.barrel,
                endgame = res.config.endgame,
                specials = res.config.specials,
                penalties = res.config.penalties,
            }
            -- 4-player no-talon needs talon.size = 0; flip.
            t.talon = {
                size = 0,
                distribution = res.config.talon.distribution,
                flip_after_first_round = res.config.talon.flip_after_first_round,
                pass_the_talon = res.config.talon.pass_the_talon,
                buyback = res.config.talon.buyback,
                buyback_penalty = res.config.talon.buyback_penalty,
                hidden_on_minimum_100 = res.config.talon.hidden_on_minimum_100,
                bad_talon_redeal = res.config.talon.bad_talon_redeal,
                bad_talon_threshold = res.config.talon.bad_talon_threshold,
                rebuy = res.config.talon.rebuy,
                rebuy_contract_value = res.config.talon.rebuy_contract_value,
                open_discard = res.config.talon.open_discard,
            }
            local four_config = rule_config.new(t)
            local hands = {
                NEUTRAL_HAND,
                NEUTRAL_HAND,
                NEUTRAL_HAND,
                FOUR_JACKS,
            }
            local offer = redeal.entitled_offer(hands, four_config)
            assert.are.same({ seat = 4, kind = "four_jack", forced = false }, offer)
        end)
    end)
end)
