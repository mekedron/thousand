-- Phase 3.6 talon-variants integration coverage. Drives the session
-- through scripted scenarios where each `talon.*` toggle changes flow.

local Session = require("app.session")
local rule_config = require("core.rule_config")
local card = require("core.card")

-- Build a canonical-Russian-shaped config with arbitrary `talon`
-- overrides. Mirrors the helper in `tests/spec/app/session_redeal_spec.lua`.
local function canonical_with_talon(overrides)
    overrides = overrides or {}
    local t = {
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
    }
    for k, v in pairs(overrides) do
        t[k] = v
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
            two_nines_in_talon_redeal = "off",
            misdeal_handling = "standard",
            misdeal_flat_penalty = 20,
            all_pass_handling = "redeal",
            deck_size = "24",
            cut_deck_nine_jack_penalty = "off",
        },
        talon = t,
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

local function c(suit, rank)
    return card.new(suit, rank)
end

-- Hands and a low-points talon (3 nines = 0 card-points). Distribution
-- of remaining cards across seats 1/2/3 is balanced so no dealing-time
-- redeal triggers fire for any rule.
local function hands_with_low_talon()
    local seat1 = {
        c("spades", "K"),
        c("clubs", "K"),
        c("diamonds", "K"),
        c("hearts", "K"),
        c("spades", "Q"),
        c("clubs", "Q"),
        c("diamonds", "Q"),
    }
    local seat2 = {
        c("hearts", "Q"),
        c("spades", "J"),
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
    -- Three nines + nothing — 0 card points.
    local talon = {
        c("spades", "9"),
        c("clubs", "9"),
        c("diamonds", "9"),
    }
    return { seat1, seat2, seat3 }, talon
end

-- Hands and a talon with exactly two 9s plus a high card (2 nines +
-- ace = 11 card-points). Designed for the two-nines-in-talon trigger:
-- 11 points is above the default `bad_talon_threshold` of 5, so the
-- bad-talon trigger does NOT fire — only the two-nines trigger does.
local function hands_with_two_nines_talon()
    local seat1 = {
        c("spades", "K"),
        c("clubs", "K"),
        c("diamonds", "K"),
        c("hearts", "K"),
        c("spades", "Q"),
        c("clubs", "Q"),
        c("diamonds", "Q"),
    }
    local seat2 = {
        c("hearts", "Q"),
        c("spades", "J"),
        c("clubs", "J"),
        c("diamonds", "J"),
        c("hearts", "J"),
        c("spades", "A"),
        c("clubs", "A"),
    }
    local seat3 = {
        c("diamonds", "A"),
        c("spades", "10"),
        c("clubs", "10"),
        c("diamonds", "10"),
        c("hearts", "10"),
        c("diamonds", "9"),
        c("hearts", "9"),
    }
    local talon = {
        c("spades", "9"),
        c("clubs", "9"),
        c("hearts", "A"),
    }
    return { seat1, seat2, seat3 }, talon
end

-- Hands and a high-points talon (3 aces = 33 card-points). Used to
-- prove the bad-talon offer does not fire when the talon is rich.
local function hands_with_rich_talon()
    local seat1 = {
        c("spades", "K"),
        c("clubs", "K"),
        c("diamonds", "K"),
        c("hearts", "K"),
        c("spades", "Q"),
        c("clubs", "Q"),
        c("diamonds", "Q"),
    }
    local seat2 = {
        c("hearts", "Q"),
        c("spades", "J"),
        c("clubs", "J"),
        c("diamonds", "J"),
        c("hearts", "J"),
        c("spades", "9"),
        c("clubs", "9"),
    }
    local seat3 = {
        c("diamonds", "9"),
        c("hearts", "9"),
        c("spades", "10"),
        c("clubs", "10"),
        c("diamonds", "10"),
        c("hearts", "10"),
        c("spades", "A"),
    }
    local talon = {
        c("clubs", "A"),
        c("diamonds", "A"),
        c("hearts", "A"),
    }
    return { seat1, seat2, seat3 }, talon
end

local function session_at_auction(test_config, hands, talon, opts)
    opts = opts or {}
    local auction_module = require("core.auction")
    local marriages_module = require("core.marriages")
    local dealer = opts.dealer or 1
    local auction = auction_module.new(test_config, dealer).auction
    local marriages = marriages_module.new(test_config).marriages
    return Session.from_state({
        config = test_config,
        seed = opts.seed or 1,
        dealer = dealer,
        hands = hands,
        talon_cards = talon,
        auction = auction,
        marriages = marriages,
        running_totals = opts.running_totals or { 0, 0, 0 },
        deal_index = opts.deal_index or 1,
    })
end

-- Drive the auction to completion: forehand bids `bid_amount`, the
-- other two seats pass. With dealer = 1 (default) forehand is seat 2.
local function drive_auction_to_done(s, bid_amount)
    bid_amount = bid_amount or 100
    -- Forehand opens.
    assert(s:bid(2, bid_amount).ok, "forehand bid must succeed")
    -- Remaining two seats pass clockwise.
    assert(s:pass(3).ok, "seat 3 pass must succeed")
    assert(s:pass(1).ok, "seat 1 pass must succeed")
end

describe("app.session talon variants", function()
    describe("bad_talon_redeal", function()
        it("does not surface an offer when the rule is off", function()
            local cfg = canonical_with_talon({ bad_talon_redeal = "off" })
            local hands, talon = hands_with_low_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            assert.are.equal("talon", s:current_phase())
            assert.is_nil(s:bad_talon_offer_state())
        end)

        it("surfaces the offer when the rule is any_contract and the talon is low", function()
            local cfg = canonical_with_talon({ bad_talon_redeal = "any_contract" })
            local hands, talon = hands_with_low_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            assert.are.equal("awaiting_bad_talon_decision", s:current_phase())
            local offer = s:bad_talon_offer_state()
            assert.is_not_nil(offer)
            assert.are.equal("bad_talon", offer.kind)
            assert.are.equal(0, offer.points)
            assert.are.equal(2, offer.declarer)
        end)

        it("does not surface an offer when the talon is rich", function()
            local cfg = canonical_with_talon({ bad_talon_redeal = "any_contract" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            assert.are.equal("talon", s:current_phase())
            assert.is_nil(s:bad_talon_offer_state())
        end)

        it("blocks take_talon while the offer is open", function()
            local cfg = canonical_with_talon({ bad_talon_redeal = "any_contract" })
            local hands, talon = hands_with_low_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            local res = s:take_talon()
            assert.is_false(res.ok)
            assert.are.equal("awaiting_bad_talon_decision", res.error.code)
        end)

        it("decline_bad_talon_redeal clears the offer and unblocks take_talon", function()
            local cfg = canonical_with_talon({ bad_talon_redeal = "any_contract" })
            local hands, talon = hands_with_low_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            local res = s:decline_bad_talon_redeal()
            assert.is_true(res.ok)
            assert.is_nil(s:bad_talon_offer_state())
            assert.are.equal("talon", s:current_phase())
            local log = s:bad_talon_log()
            assert.are.equal(1, #log)
            assert.is_false(log[1].accepted)
            -- take_talon should now succeed.
            assert.is_true(s:take_talon().ok)
        end)

        it("accept_bad_talon_redeal redeals at the same dealer", function()
            local cfg = canonical_with_talon({ bad_talon_redeal = "any_contract" })
            local hands, talon = hands_with_low_talon()
            local s = session_at_auction(cfg, hands, talon, { seed = 99 })
            drive_auction_to_done(s)
            local before_seed = s:seed()
            local res = s:accept_bad_talon_redeal()
            assert.is_true(res.ok)
            -- Same dealer; seed bumped.
            assert.are.equal(1, s:dealer())
            assert.is_true(s:seed() > before_seed)
            assert.are.equal("auction", s:current_phase())
            local log = s:bad_talon_log()
            assert.are.equal(1, #log)
            assert.is_true(log[1].accepted)
        end)

        it("ignores the offer when contract is above opening_min under minimum_100_only", function()
            local cfg = canonical_with_talon({ bad_talon_redeal = "minimum_100_only" })
            local hands, talon = hands_with_low_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s, 105)
            assert.are.equal("talon", s:current_phase())
            assert.is_nil(s:bad_talon_offer_state())
        end)
    end)

    describe("pass_the_talon (concede_deal)", function()
        it("rejects concede_deal when the rule is off", function()
            local cfg = canonical_with_talon({ pass_the_talon = "off" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            local res = s:concede_deal()
            assert.is_false(res.ok)
            assert.are.equal("concede_disabled", res.error.code)
        end)

        it("ends the deal with -bid against the declarer when the rule is on", function()
            local cfg = canonical_with_talon({ pass_the_talon = "on" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s, 100)
            local declarer = s._talon.declarer
            local res = s:concede_deal()
            assert.is_true(res.ok)
            assert.are.equal("deal_done", s:current_phase())
            assert.are.equal("talon_conceded", s:deal_done().reason)
            local totals = s:running_totals()
            assert.are.equal(-100, totals[declarer])
        end)
    end)

    describe("two_nines_in_talon_redeal", function()
        local function with_two_nines_rule(value)
            -- Override only the dealing toggle, leaving bad_talon_redeal
            -- off so the offer surfaces purely from the two-nines path.
            local rc = require("core.rule_config")
            local jsmod = require("app.json")
            local blob = jsmod.decode(rc.to_json(canonical_with_talon({})))
            blob.dealing.two_nines_in_talon_redeal = value
            return rc.new(blob)
        end

        it("does not surface an offer when the rule is off", function()
            local cfg = with_two_nines_rule("off")
            local hands, talon = hands_with_two_nines_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            assert.are.equal("talon", s:current_phase())
            assert.is_nil(s:bad_talon_offer_state())
        end)

        it("surfaces the offer when the rule is any_contract and the talon has two 9s", function()
            local cfg = with_two_nines_rule("any_contract")
            local hands, talon = hands_with_two_nines_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            assert.are.equal("awaiting_bad_talon_decision", s:current_phase())
            local offer = s:bad_talon_offer_state()
            assert.is_not_nil(offer)
            assert.are.equal("bad_talon", offer.kind)
            assert.are.equal("two_nines", offer.trigger)
            assert.are.equal(2, offer.declarer)
        end)

        it("does not surface when the talon has zero or one 9s", function()
            local cfg = with_two_nines_rule("any_contract")
            local hands, talon = hands_with_rich_talon() -- talon = 3 aces, no 9s
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            assert.is_nil(s:bad_talon_offer_state())
        end)

        it("minimum_100_only is gated by the contract floor", function()
            local cfg = with_two_nines_rule("minimum_100_only")
            local hands, talon = hands_with_two_nines_talon()
            -- Contract bid = 100 (the floor) → the offer surfaces.
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s, 100)
            assert.are.equal("awaiting_bad_talon_decision", s:current_phase())
        end)

        it("minimum_100_only suppresses the offer when contract is above 100", function()
            local cfg = with_two_nines_rule("minimum_100_only")
            local hands, talon = hands_with_two_nines_talon()
            -- A contract above the opening floor short-circuits the
            -- minimum_100_only gate (heuristic in app/session.lua).
            local s = session_at_auction(cfg, hands, talon)
            -- Forehand opens 105 (above floor); other seats pass.
            assert(s:bid(2, 105).ok)
            assert(s:pass(3).ok)
            assert(s:pass(1).ok)
            assert.are.equal("talon", s:current_phase())
            assert.is_nil(s:bad_talon_offer_state())
        end)

        it("a single offer fires when both bad_talon and two_nines triggers match", function()
            -- Talon with three 9s (0 points): bad_talon fires AND
            -- two_nines fires (count is 3, not 2 — actually let's use
            -- a talon with 2 nines and 0-point third card to match
            -- both predicates simultaneously).
            local rc = require("core.rule_config")
            local jsmod = require("app.json")
            local blob = jsmod.decode(rc.to_json(canonical_with_talon({})))
            blob.dealing.two_nines_in_talon_redeal = "any_contract"
            blob.talon.bad_talon_redeal = "any_contract"
            blob.talon.bad_talon_threshold = 5
            local cfg = rc.new(blob)
            -- Build a talon with 2 nines + a J = 0 + 0 + 2 = 2 points
            -- (below threshold 5 → bad_talon fires; nine count = 2 →
            -- two_nines fires too).
            local seat1 = {
                c("spades", "K"),
                c("clubs", "K"),
                c("diamonds", "K"),
                c("hearts", "K"),
                c("spades", "Q"),
                c("clubs", "Q"),
                c("diamonds", "Q"),
            }
            local seat2 = {
                c("hearts", "Q"),
                c("clubs", "J"),
                c("diamonds", "J"),
                c("hearts", "J"),
                c("spades", "A"),
                c("clubs", "A"),
                c("diamonds", "A"),
            }
            local seat3 = {
                c("hearts", "A"),
                c("spades", "10"),
                c("clubs", "10"),
                c("diamonds", "10"),
                c("hearts", "10"),
                c("diamonds", "9"),
                c("hearts", "9"),
            }
            local talon = {
                c("spades", "9"),
                c("clubs", "9"),
                c("spades", "J"),
            }
            local s = session_at_auction(cfg, { seat1, seat2, seat3 }, talon)
            drive_auction_to_done(s, 100)
            assert.are.equal("awaiting_bad_talon_decision", s:current_phase())
            local offer = s:bad_talon_offer_state()
            assert.is_not_nil(offer)
            -- Single offer collapses; bad_talon trigger wins for
            -- breadcrumb purposes (it carries the points payload).
            assert.are.equal("bad_talon", offer.trigger)
        end)
    end)

    describe("buyback (buyback_hand)", function()
        it("rejects buyback_hand when the rule is off", function()
            local cfg = canonical_with_talon({ buyback = "off" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            local res = s:buyback_hand()
            assert.is_false(res.ok)
            assert.are.equal("buyback_disabled", res.error.code)
        end)

        it("deducts the penalty and re-deals in place when the rule is on", function()
            local cfg = canonical_with_talon({ buyback = "on", buyback_penalty = 80 })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon, { seed = 50 })
            drive_auction_to_done(s)
            local declarer = s._talon.declarer
            local before_seed = s:seed()
            local res = s:buyback_hand()
            assert.is_true(res.ok)
            -- Auction restarts at the same dealer with a bumped seed.
            assert.are.equal("auction", s:current_phase())
            assert.are.equal(1, s:dealer())
            assert.is_true(s:seed() > before_seed)
            local totals = s:running_totals()
            assert.are.equal(-80, totals[declarer])
            local log = s:buyback_log()
            assert.are.equal(1, #log)
            assert.are.equal(80, log[1].penalty)
        end)
    end)

    describe("flip_after_first_round", function()
        it("keeps the talon face-down across the first round when on", function()
            local cfg = canonical_with_talon({ flip_after_first_round = "on" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            -- Round 1 — no actions yet, then forehand bids.
            assert.is_true(s:talon_face_down())
            assert(s:bid(2, 100).ok)
            assert.is_true(s:talon_face_down())
            assert(s:pass(3).ok)
            assert.is_true(s:talon_face_down())
        end)

        it("flips the talon when the auction reaches round 2", function()
            local cfg = canonical_with_talon({ flip_after_first_round = "on" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            assert(s:bid(2, 100).ok)
            assert(s:bid(3, 105).ok)
            assert(s:bid(1, 110).ok)
            -- All three active seats acted; round 2 starts.
            assert.is_false(s:talon_face_down())
        end)

        it("ignores the rule when off (face-down through whole auction)", function()
            local cfg = canonical_with_talon({ flip_after_first_round = "off" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            assert(s:bid(2, 100).ok)
            assert(s:bid(3, 105).ok)
            assert(s:bid(1, 110).ok)
            -- Default behaviour: face-down throughout the auction.
            assert.is_true(s:talon_face_down())
        end)
    end)

    describe("hidden_on_minimum_100", function()
        it("returns false everywhere when the rule is off", function()
            local cfg = canonical_with_talon({ hidden_on_minimum_100 = "off" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s, 100)
            assert.is_false(s:talon_hidden_rule_active())
            for seat = 1, 3 do
                assert.is_false(s:talon_face_down_to_seat(seat))
            end
        end)

        it("hides from defenders only when contract is at the floor", function()
            local cfg = canonical_with_talon({ hidden_on_minimum_100 = "minimum_100_only" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s, 100)
            assert.is_true(s:talon_hidden_rule_active())
            local declarer = s._talon.declarer
            -- Declarer always sees their own talon.
            assert.is_false(s:talon_face_down_to_seat(declarer))
            -- Defenders see it face-down.
            for seat = 1, 3 do
                if seat ~= declarer then
                    assert.is_true(s:talon_face_down_to_seat(seat))
                end
            end
        end)

        it("does not hide once contract climbs above opening_min", function()
            local cfg = canonical_with_talon({ hidden_on_minimum_100 = "minimum_100_only" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s, 105)
            assert.is_false(s:talon_hidden_rule_active())
        end)
    end)

    describe("open_discard", function()
        it("returns false when the rule is off", function()
            local cfg = canonical_with_talon({ open_discard = "off" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            assert.is_false(s:talon_passes_face_up())
        end)

        it("returns true when the rule is on", function()
            local cfg = canonical_with_talon({ open_discard = "on" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            assert.is_true(s:talon_passes_face_up())
        end)
    end)

    describe("rebuy", function()
        it("does not surface an offer when the rule is off", function()
            local cfg = canonical_with_talon({ rebuy = "off" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s)
            assert.are.equal("talon", s:current_phase())
            assert.is_nil(s:rebuy_offer_state())
        end)

        it("opens the offer at the head defender clockwise from declarer", function()
            local cfg = canonical_with_talon({ rebuy = "on" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s, 100)
            assert.are.equal("awaiting_rebuy_decision", s:current_phase())
            local offer = s:rebuy_offer_state()
            assert.is_not_nil(offer)
            -- Forehand (seat 2) wins; queue clockwise is { 3, 1 }.
            assert.are.same({ 3, 1 }, offer.seats)
            assert.are.equal(240, offer.contract)
            assert.are.equal(2, offer.original_declarer)
            assert.are.equal(3, s:current_turn())
        end)

        it("happy path: head defender claims, becomes new declarer at fixed contract", function()
            local cfg = canonical_with_talon({ rebuy = "on" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s, 100)
            assert(s:claim_rebuy(3).ok)
            assert.is_nil(s:rebuy_offer_state())
            assert.are.equal("talon", s:current_phase())
            -- New declarer is seat 3 at the fixed rebuy contract.
            assert.are.equal(3, s:current_leader())
            assert.are.equal(240, s:current_bid())
            -- Take/pass continues for the new declarer; sequencing intact.
            assert(s:take_talon().ok)
            assert.are.equal(10, #s:hands()[3])
            -- Rebuy log records the swap.
            local log = s:rebuy_log()
            assert.are.equal(1, #log)
            assert.is_true(log[1].accepted)
            assert.are.equal(3, log[1].seat)
            assert.are.equal(240, log[1].contract)
            assert.are.equal(2, log[1].from_declarer)
        end)

        it("queue advances clockwise: defender 1 declines, defender 2 claims", function()
            local cfg = canonical_with_talon({ rebuy = "on" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s, 100)
            -- Head is seat 3; decline advances to seat 1.
            assert(s:decline_rebuy(3).ok)
            assert.are.equal("awaiting_rebuy_decision", s:current_phase())
            assert.are.equal(1, s:current_turn())
            -- Seat 1 claims.
            assert(s:claim_rebuy(1).ok)
            assert.are.equal(1, s:current_leader())
            assert.are.equal(240, s:current_bid())
            -- Log captures both decisions in order.
            local log = s:rebuy_log()
            assert.are.equal(2, #log)
            assert.is_false(log[1].accepted)
            assert.are.equal(3, log[1].seat)
            assert.is_true(log[2].accepted)
            assert.are.equal(1, log[2].seat)
        end)

        it("all defenders pass — original declarer keeps the contract", function()
            local cfg = canonical_with_talon({ rebuy = "on" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s, 100)
            assert(s:decline_rebuy(3).ok)
            assert(s:decline_rebuy(1).ok)
            -- Queue empties → fall through to standard talon menu.
            assert.is_nil(s:rebuy_offer_state())
            assert.are.equal("talon", s:current_phase())
            assert.are.equal(2, s:current_leader())
            assert.are.equal(100, s:current_bid())
            assert(s:take_talon().ok)
        end)

        it("blocks declarer pre-take actions while the offer is open", function()
            local cfg = canonical_with_talon({
                rebuy = "on",
                pass_the_talon = "on",
                buyback = "on",
            })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s, 100)
            -- All four declarer-side mutators must reject with the
            -- shared phase-error code.
            for _, fn in ipairs({
                function()
                    return s:take_talon()
                end,
                function()
                    return s:concede_deal()
                end,
                function()
                    return s:buyback_hand()
                end,
                function()
                    return s:skip_raise()
                end,
            }) do
                local res = fn()
                assert.is_false(res.ok)
                assert.are.equal("awaiting_rebuy_decision", res.error.code)
            end
        end)

        it("rejects claim_rebuy / decline_rebuy from the wrong seat", function()
            local cfg = canonical_with_talon({ rebuy = "on" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s, 100)
            -- Head is seat 3; seat 1 cannot act yet.
            for _, res in ipairs({ s:claim_rebuy(1), s:decline_rebuy(1) }) do
                assert.is_false(res.ok)
                assert.are.equal("not_your_turn", res.error.code)
                assert.are.equal(3, res.error.expected)
            end
        end)

        it("rejects claim_rebuy / decline_rebuy when no offer is pending", function()
            local cfg = canonical_with_talon({ rebuy = "off" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s, 100)
            for _, res in ipairs({ s:claim_rebuy(3), s:decline_rebuy(3) }) do
                assert.is_false(res.ok)
                assert.are.equal("no_rebuy_pending", res.error.code)
            end
        end)

        it("does not open when the contract is not strictly higher than the bid", function()
            -- Non-canonical: rebuy contract 100 vs auction 105 → no offer.
            local cfg = canonical_with_talon({
                rebuy = "on",
                rebuy_contract_value = 100,
            })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s, 105)
            assert.are.equal("talon", s:current_phase())
            assert.is_nil(s:rebuy_offer_state())
        end)

        it("sequences after bad-talon: decline opens rebuy", function()
            local cfg = canonical_with_talon({
                rebuy = "on",
                bad_talon_redeal = "any_contract",
            })
            local hands, talon = hands_with_low_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s, 100)
            -- Bad-talon offer comes first; rebuy is dormant.
            assert.are.equal("awaiting_bad_talon_decision", s:current_phase())
            assert.is_nil(s:rebuy_offer_state())
            assert(s:decline_bad_talon_redeal().ok)
            -- After decline the rebuy queue opens.
            assert.are.equal("awaiting_rebuy_decision", s:current_phase())
            local offer = s:rebuy_offer_state()
            assert.is_not_nil(offer)
            assert.are.same({ 3, 1 }, offer.seats)
        end)

        it("sequences after bad-talon: accept short-circuits to redeal, no rebuy", function()
            local cfg = canonical_with_talon({
                rebuy = "on",
                bad_talon_redeal = "any_contract",
            })
            local hands, talon = hands_with_low_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s, 100)
            assert(s:accept_bad_talon_redeal().ok)
            -- Redeal restarted the deal at the same dealer; no rebuy
            -- offer should be open until the new auction crowns a
            -- declarer and reaches the talon phase.
            assert.are.equal("auction", s:current_phase())
            assert.is_nil(s:rebuy_offer_state())
        end)

        it("clears _rebuy_log and _rebuy_pending across start_next_deal", function()
            local cfg = canonical_with_talon({ rebuy = "on" })
            local hands, talon = hands_with_rich_talon()
            local s = session_at_auction(cfg, hands, talon)
            drive_auction_to_done(s, 100)
            assert(s:decline_rebuy(3).ok)
            assert(s:decline_rebuy(1).ok)
            assert.are.equal(2, #s:rebuy_log())
            -- Concede to end the deal; pass_the_talon is off so the
            -- defenders had to all decline above and the declarer now
            -- needs an explicit deal-closer. Use take_talon → pass →
            -- skip_raise → fast-forward not possible without a full
            -- trick scenario, so simulate via deal_done shortcut: drive
            -- a manual all-pass in the next deal instead. Easier: hit
            -- start_next_deal directly after marking the deal done via
            -- the all-pass redeal path.
            -- Manually mark the deal as ended so start_next_deal can
            -- hand off to the next deal.
            s._deal_done = { reason = "scored", declarer = 2, deal_scores = { 0, 0, 0 } }
            assert(s:start_next_deal().ok)
            assert.are.equal(0, #s:rebuy_log())
            assert.is_nil(s:rebuy_offer_state())
        end)
    end)

    describe("polish pass_without_taking", function()
        local polish_config = rule_config.builtins.polish
        local auction_module = require("core.auction")
        local marriages_module = require("core.marriages")

        -- 7/7/7 + 2-card talon + 1-card leftover. Hands assigned so the
        -- forehand (seat 2) opens at minimum and the others pass; seat
        -- 2 wins as declarer with the standard clockwise order.
        local function polish_deal_set()
            local hands = {
                {
                    c("spades", "9"),
                    c("spades", "J"),
                    c("spades", "Q"),
                    c("spades", "K"),
                    c("spades", "10"),
                    c("spades", "A"),
                    c("clubs", "9"),
                },
                {
                    c("clubs", "J"),
                    c("clubs", "Q"),
                    c("clubs", "K"),
                    c("clubs", "10"),
                    c("clubs", "A"),
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                },
                {
                    c("diamonds", "Q"),
                    c("diamonds", "K"),
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                    c("hearts", "9"),
                    c("hearts", "J"),
                    c("hearts", "Q"),
                },
            }
            local talon = { c("hearts", "K"), c("hearts", "10") }
            local leftover_for_declarer = { c("hearts", "A") }
            return hands, talon, leftover_for_declarer
        end

        local function polish_session_at_auction(opts)
            opts = opts or {}
            local hands, talon, leftover_for_declarer = polish_deal_set()
            local dealer = opts.dealer or 1
            local auction = auction_module.new(polish_config, dealer).auction
            local marriages = marriages_module.new(polish_config).marriages
            local s = Session.from_state({
                config = polish_config,
                seed = 1,
                dealer = dealer,
                hands = hands,
                talon_cards = talon,
                auction = auction,
                marriages = marriages,
                running_totals = { 0, 0, 0 },
                deal_index = 1,
            })
            s._leftover_for_declarer = leftover_for_declarer
            return s
        end

        it("constructs a Polish talon at status 'revealed' after the auction closes", function()
            local s = polish_session_at_auction()
            drive_auction_to_done(s, 100)
            assert.are.equal("talon", s:current_phase())
            assert.are.equal("revealed", s._talon.status)
            assert.are.equal("pass_without_taking", s._talon.distribution)
            assert.are.equal(2, #s._talon.talon)
        end)

        it("rejects take_talon under Polish with wrong_distribution_for_take", function()
            local s = polish_session_at_auction()
            drive_auction_to_done(s, 100)
            local result = s:take_talon()
            assert.is_false(result.ok)
            assert.are.equal("wrong_distribution_for_take", result.error.code)
        end)

        it("drains the talon via pass_polish_talon and lands on tricks at 8/8/8", function()
            local s = polish_session_at_auction()
            drive_auction_to_done(s, 100)
            -- Seat 2 declarer; opponents are 3 (CW) and 1 (next).
            local first = s:pass_polish_talon(3, 1)
            assert.is_true(first.ok)
            assert.are.equal("revealed", s._talon.status)
            assert.are.equal(1, #s._talon.talon)

            local second = s:pass_polish_talon(1, 1)
            assert.is_true(second.ok)
            -- Talon transitioned to done and on_talon_end advanced into tricks.
            assert.are.equal("tricks", s:current_phase())
            local hands = s:hands()
            assert.are.equal(8, #hands[1])
            assert.are.equal(8, #hands[2])
            assert.are.equal(8, #hands[3])
        end)

        it("rejects pass_polish_talon outside the talon phase with wrong_phase", function()
            local s = polish_session_at_auction()
            -- Auction not yet driven; no talon state exists.
            local result = s:pass_polish_talon(3, 1)
            assert.is_false(result.ok)
            assert.are.equal("wrong_phase", result.error.code)
        end)
    end)
end)
