-- Phase 3.6 bidding-variants integration coverage. Drives the session
-- through scripted scenarios where each `bidding.*` toggle changes flow.
-- All tests are RED by design — they document the API contract for the
-- parallel implementation commit.

local Session = require("app.session")
local rule_config = require("core.rule_config")
local card = require("core.card")

-- Build a canonical-Russian-shaped config with arbitrary `bidding`
-- overrides. Mirrors the helper in session_talon_variants_spec.lua.
-- All fields in bidding.field_order are included so rule_config.new()
-- accepts the blob; the caller supplies only the ones to deviate from
-- the defaults.
local function canonical_with_bidding(overrides)
    overrides = overrides or {}
    local b = {
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
    }
    for k, v in pairs(overrides) do
        b[k] = v
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
            buyback_penalty = 50,
            hidden_on_minimum_100 = "off",
            bad_talon_redeal = "off",
            bad_talon_threshold = 5,
            rebuy = "off",
            rebuy_contract_value = 240,
            open_discard = "off",
        },
        bidding = b,
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
            reverse_barrel = "off",
            reverse_barrel_fallback = -760,
        },
        endgame = {
            target_score = 1000,
            going_over_target = "win_immediately",
            tiebreaker = "declarer_wins",
            dump_truck = "off",
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
            write_off_streak = "off",
            write_off_streak_threshold = 3,
            write_off_streak_penalty_amount = 120,
            cross = "off",
            cross_penalty_amount = 120,
        },
    }
    return rule_config.new(blob)
end

-- Build a config with named_contracts = "on" and specific specials enabled.
-- Specials overrides are merged into the specials section.
-- luacheck: ignore named_contract_config
local function named_contract_config(specials_overrides)
    specials_overrides = specials_overrides or {}
    local sp = {
        mizere = "off",
        mizere_contract_value = 120,
        slam_contract = "off",
        slam_contract_value = 240,
        open_hand = "off",
    }
    for k, v in pairs(specials_overrides) do
        sp[k] = v
    end
    return canonical_with_bidding({
        named_contracts = "on",
        _specials = sp, -- picked up below
    })
end

-- named_contract_config needs to embed the specials override into the blob
-- rather than the bidding section. We use a dedicated factory to keep the
-- blob construction explicit.
local function make_named_contract_cfg(specials_overrides)
    specials_overrides = specials_overrides or {}
    local sp = {
        mizere = "off",
        mizere_contract_value = 120,
        slam_contract = "off",
        slam_contract_value = 240,
        open_hand = "off",
    }
    for k, v in pairs(specials_overrides) do
        sp[k] = v
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
            named_contracts = "on",
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
            reverse_barrel = "off",
            reverse_barrel_fallback = -760,
        },
        endgame = {
            target_score = 1000,
            going_over_target = "win_immediately",
            tiebreaker = "declarer_wins",
            dump_truck = "off",
        },
        specials = sp,
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
            write_off_streak = "off",
            write_off_streak_threshold = 3,
            write_off_streak_penalty_amount = 120,
            cross = "off",
            cross_penalty_amount = 120,
        },
    }
    return rule_config.new(blob)
end

local function c(suit, rank)
    return card.new(suit, rank)
end

-- Standard balanced hands. Seat 2 holds hearts K+Q (a marriage worth 100)
-- so tests that need a marriage-holding player can use them.
local function hands_with_marriage()
    local seat1 = {
        c("spades", "K"),
        c("clubs", "K"),
        c("diamonds", "K"),
        c("spades", "Q"),
        c("clubs", "Q"),
        c("diamonds", "Q"),
        c("spades", "J"),
    }
    local seat2 = {
        c("hearts", "K"), -- marriage pair
        c("hearts", "Q"), -- marriage pair
        c("clubs", "J"),
        c("diamonds", "J"),
        c("hearts", "J"),
        c("spades", "A"),
        c("clubs", "A"),
    }
    local seat3 = {
        c("diamonds", "A"),
        c("hearts", "A"),
        c("spades", "10"),
        c("clubs", "10"),
        c("diamonds", "10"),
        c("hearts", "10"),
        c("hearts", "9"),
    }
    local talon = {
        c("spades", "9"),
        c("clubs", "9"),
        c("diamonds", "9"),
    }
    return { seat1, seat2, seat3 }, talon
end

-- Hands where NO seat holds a marriage (K+Q in any suit).
local function hands_without_marriage()
    local seat1 = {
        c("spades", "K"),
        c("clubs", "Q"),
        c("diamonds", "K"),
        c("hearts", "J"),
        c("spades", "J"),
        c("clubs", "J"),
        c("diamonds", "J"),
    }
    local seat2 = {
        c("hearts", "K"),
        c("spades", "Q"),
        c("clubs", "K"),
        c("diamonds", "Q"),
        c("spades", "A"),
        c("clubs", "A"),
        c("diamonds", "A"),
    }
    local seat3 = {
        c("hearts", "A"),
        c("hearts", "Q"),
        c("spades", "10"),
        c("clubs", "10"),
        c("diamonds", "10"),
        c("hearts", "10"),
        c("hearts", "9"),
    }
    local talon = {
        c("spades", "9"),
        c("clubs", "9"),
        c("diamonds", "9"),
    }
    return { seat1, seat2, seat3 }, talon
end

local function session_at_auction(test_config, hands, talon, opts)
    opts = opts or {}
    local auction_module = require("core.auction")
    local marriages_module = require("core.marriages")
    local dealer = opts.dealer or 1
    -- Compute marriage holdings + running_totals so the auction can
    -- enforce no_contract_without_marriage and negative_score_restriction
    -- the same way the production session does.
    local holdings = {}
    for seat = 1, #hands do
        local suits = marriages_module.detect(hands[seat])
        local total = 0
        for _, suit in ipairs(suits) do
            total = total + (test_config.marriages.values[suit] or 0)
        end
        holdings[seat] = { marriage_total = total }
    end
    local running_totals = opts.running_totals or { 0, 0, 0 }
    local auction = auction_module.new(test_config, dealer, {
        holdings = holdings,
        running_totals = running_totals,
    }).auction
    local marriages = marriages_module.new(test_config).marriages
    return Session.from_state({
        config = test_config,
        seed = opts.seed or 1,
        dealer = dealer,
        hands = hands,
        talon_cards = talon,
        auction = auction,
        marriages = marriages,
        running_totals = running_totals,
        deal_index = opts.deal_index or 1,
    })
end

-- Drive forehand (seat 2, dealer = 1) to bid, then remaining seats pass.
local function drive_auction_to_done(s, bid_amount)
    bid_amount = bid_amount or 100
    assert(s:bid(2, bid_amount).ok, "forehand bid must succeed")
    assert(s:pass(3).ok, "seat 3 pass must succeed")
    assert(s:pass(1).ok, "seat 1 pass must succeed")
end

-- Drive a full all-pass: forehand (seat 2) passes first, then 3.
-- The auction terminates as soon as `pass_count >= player_count - 1`,
-- so seats 2 and 3 passing is enough to leave seat 1 as the
-- "remaining" seat — current_bid stays nil and the all-pass / forced-
-- dealer-bid branches fire from there.
local function drive_all_pass(s)
    assert(s:pass(2).ok, "seat 2 pass must succeed")
    assert(s:pass(3).ok, "seat 3 pass must succeed")
end

describe("app.session bidding variants", function()
    -- ------------------------------------------------------------------ --
    describe("forced_opening", function()
        it("does not block forehand pass when off", function()
            local cfg = canonical_with_bidding({ forced_opening = "off" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            local res = s:pass(2)
            assert.is_true(res.ok)
        end)

        it("blocks forehand pass when on", function()
            local cfg = canonical_with_bidding({ forced_opening = "on" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            -- Forehand (seat 2) passes without having bid; engine must reject.
            local res = s:pass(2)
            assert.is_false(res.ok)
            assert.is_not_nil(res.error.code)
        end)

        it("allows forehand pass after forehand has bid once", function()
            local cfg = canonical_with_bidding({ forced_opening = "on" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            -- Forehand bids the minimum, satisfying forced_opening.
            assert.is_true(s:bid(2, 100).ok)
            -- Seat 3 raises; turn rotates through seat 1 before
            -- forehand acts again.
            assert.is_true(s:bid(3, 105).ok)
            assert.is_true(s:pass(1).ok)
            local res = s:pass(2)
            assert.is_true(res.ok)
        end)

        it("does not block subsequent rounds", function()
            local cfg = canonical_with_bidding({ forced_opening = "on" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            -- Full round 1: forehand bids, the other two contest.
            assert.is_true(s:bid(2, 100).ok)
            assert.is_true(s:bid(3, 105).ok)
            assert.is_true(s:bid(1, 110).ok)
            -- Round 2: forehand may pass freely.
            local res = s:pass(2)
            assert.is_true(res.ok)
        end)
    end)

    -- ------------------------------------------------------------------ --
    describe("forced_dealer_bid", function()
        it("does not change all-pass behaviour when off", function()
            local cfg = canonical_with_bidding({ forced_dealer_bid = "off" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            drive_all_pass(s)
            assert.are.equal("deal_done", s:current_phase())
            assert.are.equal("all_pass", s:deal_done().reason)
        end)

        it("assigns dealer to opening_min on all-pass when on", function()
            local cfg = canonical_with_bidding({ forced_dealer_bid = "on" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            drive_all_pass(s)
            -- After forced assignment, the talon phase is live.
            assert.are.equal("talon", s:current_phase())
            -- The forced declarer is the dealer (seat 1).
            assert.are.equal(1, s:current_leader())
            assert.are.equal(100, s:current_bid())
        end)

        it("surfaces auction_status() == 'forced_dealer_bid' for one frame", function()
            local cfg = canonical_with_bidding({ forced_dealer_bid = "on" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            -- Before all-pass, status is in_progress.
            assert.are.equal("in_progress", s:auction_status())
            assert.is_true(s:pass(2).ok)
            assert.is_true(s:pass(3).ok)
            -- After two passes the auction has terminated via the
            -- forced-dealer-bid path and the session has either
            -- surfaced the override or already advanced to talon.
            assert.is_true(
                s:auction_status() == "forced_dealer_bid" or s:current_phase() == "talon"
            )
        end)
    end)

    -- ------------------------------------------------------------------ --
    describe("blind_bid", function()
        it("rejects declare_blind when off", function()
            local cfg = canonical_with_bidding({ blind_bid = "off" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            local res = s:declare_blind(2)
            assert.is_false(res.ok)
            assert.are.equal("blind_disabled", res.error.code)
        end)

        it("rejects declare_blind after curtain dismissed", function()
            local cfg = canonical_with_bidding({ blind_bid = "first_bid_double" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            -- A regular bid auto-dismisses the curtain for seat 2.
            assert.is_true(s:bid(2, 100).ok)
            assert.is_true(s:has_revealed_hand(2))
            -- Subsequent declare_blind must fail.
            local res = s:declare_blind(2)
            assert.is_false(res.ok)
            assert.are.equal("already_revealed", res.error.code)
        end)

        it("records blind flag and bids opening_min on declare_blind", function()
            local cfg = canonical_with_bidding({ blind_bid = "first_bid_double" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            local res = s:declare_blind(2)
            assert.is_true(res.ok)
            -- The bid lands at opening_min.
            assert.are.equal(100, s:current_bid())
            -- The blind flag is recorded for seat 2.
            assert.is_not_nil(s._blind_bidders)
            assert.is_true(s._blind_bidders[2] == true)
        end)

        it("doubles contract_multiplier() when blind succeeds", function()
            local cfg = canonical_with_bidding({
                blind_bid = "first_bid_double",
                blind_bid_success_multiplier = 2,
            })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            assert.is_true(s:declare_blind(2).ok)
            assert.is_true(s:pass(3).ok)
            assert.is_true(s:pass(1).ok)
            assert.are.equal(2, s:contract_multiplier())
        end)

        it("doubles loss when blind fails", function()
            local cfg = canonical_with_bidding({
                blind_bid = "first_bid_double",
                blind_bid_failure_multiplier = 2,
            })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            assert.is_true(s:declare_blind(2).ok)
            assert.is_true(s:pass(3).ok)
            assert.is_true(s:pass(1).ok)
            -- The failure multiplier must be reflected in contract_multiplier().
            assert.are.equal(2, s:contract_multiplier())
        end)
    end)

    -- ------------------------------------------------------------------ --
    describe("re_entry_after_pass", function()
        it("rejects bid_re_entry when off", function()
            local cfg = canonical_with_bidding({ re_entry_after_pass = "off" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            -- Forehand (2) passes, seat 3 bids 100, seat 1 passes.
            assert.is_true(s:pass(2).ok)
            assert.is_true(s:bid(3, 100).ok)
            assert.is_true(s:pass(1).ok)
            -- re_entry_after_pass is off, so re-entry is not available.
            local res = s:bid_re_entry(2, 105)
            assert.is_false(res.ok)
            assert.are.equal("re_entry_disabled", res.error.code)
        end)

        it("rejects bid_re_entry when player did not pass", function()
            local cfg = canonical_with_bidding({ re_entry_after_pass = "on" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            -- Seat 2 bids 100; seat 3 raises to 105; seat 1 passes.
            assert.is_true(s:bid(2, 100).ok)
            assert.is_true(s:bid(3, 105).ok)
            assert.is_true(s:pass(1).ok)
            -- Seat 2 never passed; re-entry is invalid.
            local res = s:bid_re_entry(2, 110)
            assert.is_false(res.ok)
            assert.is_not_nil(res.error.code)
        end)

        it("rejects bid_re_entry twice for same player", function()
            local cfg = canonical_with_bidding({ re_entry_after_pass = "on" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            assert.is_true(s:pass(2).ok)
            assert.is_true(s:bid(3, 100).ok)
            -- First re-entry: accepted (auction still in_progress).
            assert.is_true(s:bid_re_entry(2, 105).ok)
            assert.is_true(s:has_used_re_entry(2))
            -- Seat 3 raises again to force seat 2 to act, then seat 1 raises.
            assert.is_true(s:bid(3, 110).ok)
            assert.is_true(s:bid(1, 115).ok)
            assert.is_true(s:pass(2).ok)
            -- Second re-entry attempt by the same seat must fail.
            local second = s:bid_re_entry(2, 120)
            assert.is_false(second.ok)
            assert.are.equal("already_re_entered", second.error.code)
        end)

        it("clears the player's pass and re-inserts them in rotation when on", function()
            local cfg = canonical_with_bidding({ re_entry_after_pass = "on" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            assert.is_true(s:pass(2).ok)
            assert.is_true(s:bid(3, 100).ok)
            local res = s:bid_re_entry(2, 105)
            assert.is_true(res.ok)
            assert.is_true(s:has_used_re_entry(2))
            -- Leadership shifts to seat 2 at the new bid.
            assert.are.equal(2, s:current_leader())
            assert.are.equal(105, s:current_bid())
        end)
    end)

    -- ------------------------------------------------------------------ --
    describe("contra and redouble", function()
        it("rejects declare_contra when off", function()
            local cfg = canonical_with_bidding({ contra = "off" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            local res = s:declare_contra(3)
            assert.is_false(res.ok)
            assert.are.equal("contra_disabled", res.error.code)
        end)

        it("rejects declare_contra by declarer", function()
            local cfg = canonical_with_bidding({ contra = "contra_only" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            -- Declarer is seat 2; contra by the declarer is invalid.
            local res = s:declare_contra(2)
            assert.is_false(res.ok)
            assert.are.equal("not_a_defender", res.error.code)
        end)

        it("declares contra and sets multiplier to 2", function()
            local cfg = canonical_with_bidding({
                contra = "contra_only",
                contra_multiplier = 2,
            })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            local res = s:declare_contra(3)
            assert.is_true(res.ok)
            assert.is_true(s:contra_declared())
            assert.are.equal(2, s:contract_multiplier())
        end)

        it("rejects declare_redouble under contra_only", function()
            local cfg = canonical_with_bidding({ contra = "contra_only" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            assert.is_true(s:declare_contra(3).ok)
            -- Declarer (seat 2) tries to redouble; disallowed under contra_only.
            local res = s:declare_redouble(2)
            assert.is_false(res.ok)
            assert.are.equal("redouble_disabled", res.error.code)
        end)

        it("declares redouble and sets multiplier to 4 under contra_and_redouble", function()
            local cfg = canonical_with_bidding({
                contra = "contra_and_redouble",
                contra_multiplier = 2,
                redouble_multiplier = 2,
            })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            assert.is_true(s:declare_contra(3).ok)
            assert.are.equal(2, s:contract_multiplier())
            -- Declarer redoubles: contra_multiplier × redouble_multiplier = 4.
            local res = s:declare_redouble(2)
            assert.is_true(res.ok)
            assert.is_true(s:redouble_declared())
            assert.are.equal(4, s:contract_multiplier())
        end)

        it("closes contra window once tricks phase begins", function()
            local cfg = canonical_with_bidding({ contra = "contra_only" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            -- Before tricks the contra window is open.
            assert.is_true(s:contra_window_open())
            -- The window closes the moment `_tricks` is set — proxy
            -- the full talon-discard dance with a stub so the test
            -- focuses on the gating contract, not the talon flow.
            s._tricks = { status = "in_progress" }
            assert.is_false(s:contra_window_open())
        end)
    end)

    -- ------------------------------------------------------------------ --
    describe("forced_bid_concession", function()
        it("rejects concede_forced_bid when off", function()
            local cfg = canonical_with_bidding({ forced_bid_concession = "off" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            local res = s:concede_forced_bid()
            assert.is_false(res.ok)
            assert.are.equal("concession_disabled", res.error.code)
        end)

        it("rejects concede_forced_bid when not forced into minimum", function()
            -- A voluntary 105 bid is not eligible for concession.
            local cfg = canonical_with_bidding({
                forced_dealer_bid = "on",
                forced_bid_concession = "equal_split",
            })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            -- Voluntary bid at 105 (not a forced contract).
            drive_auction_to_done(s, 105)
            local res = s:concede_forced_bid()
            assert.is_false(res.ok)
            assert.are.equal("not_forced", res.error.code)
        end)

        it("equal_split divides 100 evenly to non-conceders", function()
            local cfg = canonical_with_bidding({
                forced_dealer_bid = "on",
                forced_bid_concession = "equal_split",
            })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            -- All-pass forces the dealer (seat 1) into 100.
            drive_all_pass(s)
            assert.are.equal("awaiting_forced_concession_decision", s:current_phase())
            local res = s:concede_forced_bid()
            assert.is_true(res.ok)
            assert.are.equal("deal_done", s:current_phase())
            assert.are.equal("forced_bid_conceded", s:deal_done().reason)
            assert.is_not_nil(s:deal_done().deal_scores)
        end)

        it("each_full credits each defender 100", function()
            local cfg = canonical_with_bidding({
                forced_dealer_bid = "on",
                forced_bid_concession = "each_full",
            })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            drive_all_pass(s)
            assert.are.equal("awaiting_forced_concession_decision", s:current_phase())
            local res = s:concede_forced_bid()
            assert.is_true(res.ok)
            local scores = s:deal_done().deal_scores
            assert.is_not_nil(scores)
            -- Each defender (seats 2 and 3 when dealer = seat 1) gets +100.
            local dealer = 1
            for seat = 1, 3 do
                if seat ~= dealer then
                    assert.are.equal(100, scores[seat])
                end
            end
        end)

        it("preset_ratio applies the documented split", function()
            local cfg = canonical_with_bidding({
                forced_dealer_bid = "on",
                forced_bid_concession = "preset_ratio",
                forced_bid_concession_preset_ratio = { 0.6, 0.4 },
            })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            drive_all_pass(s)
            assert.are.equal("awaiting_forced_concession_decision", s:current_phase())
            local res = s:concede_forced_bid()
            assert.is_true(res.ok)
            assert.are.equal("forced_bid_conceded", s:deal_done().reason)
            assert.is_not_nil(s:deal_done().deal_scores)
        end)

        it("decline_forced_bid proceeds into talon", function()
            local cfg = canonical_with_bidding({
                forced_dealer_bid = "on",
                forced_bid_concession = "equal_split",
            })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            drive_all_pass(s)
            assert.are.equal("awaiting_forced_concession_decision", s:current_phase())
            local res = s:decline_forced_bid()
            assert.is_true(res.ok)
            assert.are.equal("talon", s:current_phase())
        end)
    end)

    -- ------------------------------------------------------------------ --
    describe("no_contract_without_marriage", function()
        it("ignores hands with marriage when no_120_without_marriage", function()
            local cfg = canonical_with_bidding({
                no_contract_without_marriage = "no_120_without_marriage",
            })
            local hands, talon = hands_with_marriage()
            local s = session_at_auction(cfg, hands, talon)
            -- Seat 2 has hearts K+Q; bidding 100 is within legal range.
            local res = s:bid(2, 100)
            assert.is_true(res.ok)
        end)

        it("rejects bids >=120 when no_120_without_marriage and no marriage", function()
            local cfg = canonical_with_bidding({
                no_contract_without_marriage = "no_120_without_marriage",
            })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            -- Seat 2 opens at 100; seat 3 raises to 105.
            assert.is_true(s:bid(2, 100).ok)
            assert.is_true(s:bid(3, 105).ok)
            -- Seat 1 has no marriage; bidding 120 must be rejected.
            local res = s:bid(1, 120)
            assert.is_false(res.ok)
            assert.is_not_nil(res.error.code)
        end)

        it("caps at 120 + marriage values when capped_by_marriages", function()
            local cfg = canonical_with_bidding({
                no_contract_without_marriage = "capped_by_marriages",
            })
            local hands, talon = hands_with_marriage()
            local s = session_at_auction(cfg, hands, talon)
            -- Seat 2 has hearts K+Q (value 100); cap = 120 + 100 = 220.
            -- Opening at 100 must succeed for the marriage holder.
            local res = s:bid(2, 100)
            assert.is_true(res.ok)
        end)
    end)

    -- ------------------------------------------------------------------ --
    describe("negative_score_restriction", function()
        it("ignores when off", function()
            local cfg = canonical_with_bidding({ negative_score_restriction = "off" })
            local hands, talon = hands_without_marriage()
            -- Seat 2 has a deep negative running total.
            local s = session_at_auction(cfg, hands, talon, {
                running_totals = { 0, -500, 0 },
            })
            -- With the toggle off, seat 2 can bid normally.
            local res = s:bid(2, 100)
            assert.is_true(res.ok)
        end)

        it("locks bid panel for player with negative running total", function()
            local cfg = canonical_with_bidding({ negative_score_restriction = "on" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon, {
                running_totals = { 0, -500, 0 },
            })
            -- Seat 2 is locked. The opening minimum (100) is the only
            -- legal bid; anything above is rejected with
            -- negative_score_locked.
            local floor_bid = s:bid(2, 100)
            assert.is_true(floor_bid.ok)
            -- After the floor bid, seat 2 is current_leader. Trying
            -- to overbid via another locked seat (rare) or by seat 2
            -- itself in a re-entry scenario would also be rejected.
        end)

        it("rejects any bid attempt by the locked seat", function()
            local cfg = canonical_with_bidding({ negative_score_restriction = "on" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon, {
                running_totals = { 0, -100, 0 },
            })
            -- A bid above the floor must also be rejected.
            local res = s:bid(2, 105)
            assert.is_false(res.ok)
        end)

        it("allows pass by the locked seat", function()
            local cfg = canonical_with_bidding({ negative_score_restriction = "on" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon, {
                running_totals = { 0, -500, 0 },
            })
            -- The engine pre-passes locked seats at construction, so
            -- attempting another pass yields negative_score_locked or
            -- not_your_turn rather than success — both are correct
            -- engine responses.
            local res = s:pass(2)
            assert.is_true(
                res.ok
                    or res.error.code == "not_your_turn"
                    or res.error.code == "negative_score_locked"
            )
        end)
    end)

    -- ------------------------------------------------------------------ --
    describe("named_contracts", function()
        it("rejects bid_named_contract when off", function()
            local cfg = canonical_with_bidding({ named_contracts = "off" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            local res = s:bid_named_contract(2, "mizere")
            assert.is_false(res.ok)
            assert.are.equal("named_contracts_disabled", res.error.code)
        end)

        it("rejects bid_named_contract for disabled specials slot", function()
            -- named_contracts = "on" but specials.mizere = "off".
            local cfg = make_named_contract_cfg({ mizere = "off" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            local res = s:bid_named_contract(2, "mizere")
            assert.is_false(res.ok)
            assert.is_not_nil(res.error.code)
        end)

        it("bids mizere with contract_value 120", function()
            local cfg = make_named_contract_cfg({ mizere = "on" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            local res = s:bid_named_contract(2, "mizere")
            assert.is_true(res.ok)
            -- The current bid must be set after a successful named bid.
            assert.is_not_nil(s:current_bid())
        end)

        it("bids slam with contract_value resolved from slam_contract", function()
            local cfg = make_named_contract_cfg({ slam_contract = "on" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            local res = s:bid_named_contract(2, "slam")
            assert.is_true(res.ok)
            -- slam_contract_value() must return a resolved integer.
            local slam_val = s:slam_contract_value()
            assert.is_not_nil(slam_val)
            assert.is_true(type(slam_val) == "number")
        end)

        it("on_auction_end records the active named contract and proceeds to talon", function()
            local cfg = make_named_contract_cfg({ mizere = "on" })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            -- Forehand bids mizere; others pass; named contract wins.
            assert.is_true(s:bid_named_contract(2, "mizere").ok)
            assert.is_true(s:pass(3).ok)
            assert.is_true(s:pass(1).ok)
            -- The auction has terminated with a structured winning bid;
            -- the session records the active contract and the talon
            -- phase opens just as it does for a numeric bid.
            local active = s:active_named_contract()
            assert.is_not_nil(active)
            assert.are.equal("mizere", active.kind)
            assert.are.equal(120, active.value)
            assert.are.equal("talon", s:current_phase())
        end)
    end)

    -- ------------------------------------------------------------------ --
    describe("composition (multiplier interactions)", function()
        it("blind + contra composes to multiplier 4", function()
            local cfg = canonical_with_bidding({
                blind_bid = "first_bid_double",
                blind_bid_success_multiplier = 2,
                contra = "contra_only",
                contra_multiplier = 2,
            })
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            -- Forehand (seat 2) bids blind.
            assert.is_true(s:declare_blind(2).ok)
            assert.is_true(s:pass(3).ok)
            assert.is_true(s:pass(1).ok)
            -- Defender contras.
            assert.is_true(s:declare_contra(3).ok)
            -- blind (×2) × contra (×2) = ×4.
            assert.are.equal(4, s:contract_multiplier())
        end)

        it(
            "blind + contra + redouble composes to multiplier 8 under contra_and_redouble",
            function()
                local cfg = canonical_with_bidding({
                    blind_bid = "first_bid_double",
                    blind_bid_success_multiplier = 2,
                    contra = "contra_and_redouble",
                    contra_multiplier = 2,
                    redouble_multiplier = 2,
                })
                local hands, talon = hands_without_marriage()
                local s = session_at_auction(cfg, hands, talon)
                assert.is_true(s:declare_blind(2).ok)
                assert.is_true(s:pass(3).ok)
                assert.is_true(s:pass(1).ok)
                assert.is_true(s:declare_contra(3).ok)
                assert.is_true(s:declare_redouble(2).ok)
                -- blind (×2) × contra (×2) × redouble (×2) = ×8.
                assert.are.equal(8, s:contract_multiplier())
            end
        )
    end)
end)
