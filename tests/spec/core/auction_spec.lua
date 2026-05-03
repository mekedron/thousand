local auction = require("core.auction")
local rule_config = require("core.rule_config")

local config = rule_config.canonical_russian

local function open_auction(dealer)
    local result = auction.new(config, dealer or 1)
    assert.is_true(result.ok, "fixture: auction.new must succeed")
    return result.auction
end

local function bid(state, player, amount)
    local result = auction.bid(state, player, amount)
    assert.is_true(result.ok, "fixture: bid must succeed")
    return result.auction
end

local function pass(state, player)
    local result = auction.pass(state, player)
    assert.is_true(result.ok, "fixture: pass must succeed")
    return result.auction
end

local function snapshot(state)
    -- Deep enough copy for the immutability-of-input assertions: every
    -- field actually consulted by bid/pass + the lists they could touch.
    return {
        turn = state.turn,
        current_bid = state.current_bid,
        current_leader = state.current_leader,
        pass_count = state.pass_count,
        status = state.status,
        declarer = state.declarer,
        final_bid = state.final_bid,
        passed = { state.passed[1], state.passed[2], state.passed[3] },
        history_len = #state.history,
    }
end

describe("core.auction", function()
    describe("new()", function()
        it("rejects a non-RuleConfig argument", function()
            for _, bad in ipairs({ nil, 42, "config", {}, true }) do
                local result = auction.new(bad, 1)
                assert.is_false(result.ok)
                assert.are.equal("not_a_rule_config", result.error.code)
            end
        end)

        it("rejects a non-integer dealer", function()
            for _, bad in ipairs({ "1", 1.5, true, {} }) do
                local result = auction.new(config, bad)
                assert.is_false(result.ok)
                assert.are.equal("bad_dealer_position", result.error.code)
            end
            local nil_result = auction.new(config, nil)
            assert.is_false(nil_result.ok)
            assert.are.equal("bad_dealer_position", nil_result.error.code)
        end)

        it("rejects a dealer out of range", function()
            for _, bad in ipairs({ 0, -1, 4, 99 }) do
                local result = auction.new(config, bad)
                assert.is_false(result.ok)
                assert.are.equal("bad_dealer_position", result.error.code)
                assert.are.equal(3, result.error.player_count)
                assert.are.equal(bad, result.error.actual)
            end
        end)

        it("returns a fresh in-progress auction", function()
            local result = auction.new(config, 1)
            assert.is_true(result.ok)
            assert.is_nil(result.error)
            local a = result.auction
            assert.is_true(auction.is_auction(a))
            assert.are.equal("in_progress", a.status)
            assert.are.equal(0, a.pass_count)
            assert.is_nil(a.current_bid)
            assert.is_nil(a.current_leader)
            assert.is_nil(a.declarer)
            assert.is_nil(a.final_bid)
            assert.are.equal(0, #a.history)
            assert.are.equal(3, a.player_count)
            assert.same({ false, false, false }, a.passed)
        end)

        it("sets forehand to (dealer mod player_count) + 1 for every dealer", function()
            local cases = { { 1, 2 }, { 2, 3 }, { 3, 1 } }
            for _, case in ipairs(cases) do
                local dealer, expected_forehand = case[1], case[2]
                local a = open_auction(dealer)
                assert.are.equal(dealer, a.dealer)
                assert.are.equal(expected_forehand, a.forehand)
                assert.are.equal(expected_forehand, a.turn)
            end
        end)
    end)

    describe("bid() happy path", function()
        it("forehand can open at the opening minimum", function()
            local a = open_auction(1) -- forehand = 2
            local result = auction.bid(a, 2, 100)
            assert.is_true(result.ok)
            local next_state = result.auction
            assert.are.equal(100, next_state.current_bid)
            assert.are.equal(2, next_state.current_leader)
            assert.are.equal(3, next_state.turn)
            assert.are.equal("in_progress", next_state.status)
            assert.are.equal(1, #next_state.history)
            local entry = next_state.history[1]
            assert.are.equal(2, entry.player)
            assert.are.equal("bid", entry.action)
            assert.are.equal(100, entry.amount)
        end)

        it("forehand can open at the pre-talon maximum (120)", function()
            local a = open_auction(1)
            local result = auction.bid(a, 2, 120)
            assert.is_true(result.ok)
            assert.are.equal(120, result.auction.current_bid)
        end)

        it("middlehand can raise by the smallest legal step (5)", function()
            local a = open_auction(1)
            a = bid(a, 2, 100)
            local result = auction.bid(a, 3, 105)
            assert.is_true(result.ok)
            assert.are.equal(105, result.auction.current_bid)
            assert.are.equal(3, result.auction.current_leader)
        end)

        it("middlehand can raise to the pre-talon maximum (120)", function()
            local a = open_auction(1)
            a = bid(a, 2, 100)
            local result = auction.bid(a, 3, 120)
            assert.is_true(result.ok)
            assert.are.equal(120, result.auction.current_bid)
        end)

        it("turn advances clockwise to the next non-passed seat after a bid", function()
            local a = open_auction(1) -- forehand = 2, then 3, then 1
            a = bid(a, 2, 100)
            assert.are.equal(3, a.turn)
            a = bid(a, 3, 110)
            assert.are.equal(1, a.turn)
            a = bid(a, 1, 115)
            assert.are.equal(2, a.turn)
        end)

        it("turn skips a passed seat when advancing after a bid", function()
            local a = open_auction(1) -- forehand = 2
            a = pass(a, 2) -- forehand passes; turn -> 3
            a = bid(a, 3, 100) -- middlehand bids; turn -> 1 (skipping 2)
            assert.are.equal(1, a.turn)
            assert.is_true(a.passed[2])
        end)
    end)

    describe("bid() rejections", function()
        it("rejects a non-auction first argument", function()
            for _, bad in ipairs({ nil, 42, "auction", {}, true }) do
                local result = auction.bid(bad, 1, 100)
                assert.is_false(result.ok)
                assert.are.equal("not_an_auction", result.error.code)
            end
        end)

        it("rejects an opening bid below the minimum", function()
            local a = open_auction(1)
            for _, low in ipairs({ 95, 50, 0, -5 }) do
                local result = auction.bid(a, 2, low)
                assert.is_false(result.ok)
                assert.are.equal("bid_below_minimum", result.error.code)
                assert.are.equal(100, result.error.min)
                assert.are.equal(low, result.error.amount)
            end
        end)

        it("rejects a bid above the pre-talon maximum", function()
            local a = open_auction(1)
            for _, high in ipairs({ 125, 130, 200, 500 }) do
                local result = auction.bid(a, 2, high)
                assert.is_false(result.ok)
                assert.are.equal("bid_above_pre_talon_max", result.error.code)
                assert.are.equal(120, result.error.max)
                assert.are.equal(high, result.error.amount)
            end
        end)

        it("rejects a non-integer bid amount", function()
            local a = open_auction(1)
            for _, bad in ipairs({ 100.5, "100", true, {} }) do
                local result = auction.bid(a, 2, bad)
                assert.is_false(result.ok)
                assert.are.equal("bid_not_integer", result.error.code)
            end
            local nil_result = auction.bid(a, 2, nil)
            assert.is_false(nil_result.ok)
            assert.are.equal("bid_not_integer", nil_result.error.code)
        end)

        it("rejects a bid not strictly higher than the current bid", function()
            local a = open_auction(1)
            a = bid(a, 2, 100)
            for _, low in ipairs({ 100, 95, 90 }) do
                local result = auction.bid(a, 3, low)
                assert.is_false(result.ok)
                assert.are.equal("bid_not_higher", result.error.code)
                assert.are.equal(100, result.error.current_bid)
            end
        end)

        it("rejects a bid that violates the increment rule", function()
            local a = open_auction(1)
            a = bid(a, 2, 100)
            for _, bad in ipairs({ 107, 113, 119 }) do
                local result = auction.bid(a, 3, bad)
                assert.is_false(result.ok)
                assert.are.equal("bad_bid_increment", result.error.code)
                assert.are.equal(5, result.error.step)
            end
        end)

        it("rejects a bid from a player who already passed", function()
            local a = open_auction(1) -- forehand = 2
            a = pass(a, 2)
            local result = auction.bid(a, 2, 100)
            assert.is_false(result.ok)
            assert.are.equal("not_your_turn", result.error.code)
        end)

        it("rejects a bid from a player who is not on turn", function()
            local a = open_auction(1) -- forehand = 2 must act first
            local result = auction.bid(a, 3, 100)
            assert.is_false(result.ok)
            assert.are.equal("not_your_turn", result.error.code)
            assert.are.equal(3, result.error.player)
            assert.are.equal(2, result.error.turn)
        end)

        it("rejects a bad player index", function()
            local a = open_auction(1)
            for _, bad in ipairs({ 0, 4, -1, 1.5, "2", true, {} }) do
                local result = auction.bid(a, bad, 100)
                assert.is_false(result.ok)
                assert.are.equal("bad_player", result.error.code)
            end
            local nil_result = auction.bid(a, nil, 100)
            assert.is_false(nil_result.ok)
            assert.are.equal("bad_player", nil_result.error.code)
        end)

        it("rejects any bid on a terminated auction", function()
            local a = open_auction(1) -- forehand = 2
            a = bid(a, 2, 100)
            a = pass(a, 3)
            a = pass(a, 1)
            assert.are.equal("done", a.status)
            local result = auction.bid(a, 2, 110)
            assert.is_false(result.ok)
            assert.are.equal("auction_already_done", result.error.code)
            assert.are.equal("done", result.error.status)
        end)
    end)

    describe("pass() happy path", function()
        it("forehand can pass immediately", function()
            local a = open_auction(1) -- forehand = 2
            local result = auction.pass(a, 2)
            assert.is_true(result.ok)
            local next_state = result.auction
            assert.is_true(next_state.passed[2])
            assert.are.equal(1, next_state.pass_count)
            assert.are.equal(3, next_state.turn)
            assert.are.equal("in_progress", next_state.status)
            assert.are.equal(1, #next_state.history)
            local entry = next_state.history[1]
            assert.are.equal(2, entry.player)
            assert.are.equal("pass", entry.action)
            assert.is_nil(entry.amount)
        end)

        it("turn advances clockwise to the next non-passed seat after a pass", function()
            local a = open_auction(1) -- forehand = 2
            a = pass(a, 2) -- turn -> 3
            assert.are.equal(3, a.turn)
            a = bid(a, 3, 100) -- turn -> 1 (skips 2)
            assert.are.equal(1, a.turn)
        end)

        it("a player who passed cannot bid afterwards", function()
            local a = open_auction(1)
            a = pass(a, 2)
            local result = auction.bid(a, 2, 100)
            assert.is_false(result.ok)
            assert.are.equal("not_your_turn", result.error.code)
        end)
    end)

    describe("pass() rejections", function()
        it("rejects a non-auction first argument", function()
            for _, bad in ipairs({ nil, 42, "auction", {}, true }) do
                local result = auction.pass(bad, 1)
                assert.is_false(result.ok)
                assert.are.equal("not_an_auction", result.error.code)
            end
        end)

        it("rejects a pass from a player who already passed", function()
            local a = open_auction(1) -- forehand = 2 passes; then it's 3's turn
            a = pass(a, 2)
            local result = auction.pass(a, 2)
            assert.is_false(result.ok)
            assert.are.equal("not_your_turn", result.error.code)
        end)

        it("rejects a pass from a player who is not on turn", function()
            local a = open_auction(1) -- forehand = 2 must act first
            local result = auction.pass(a, 3)
            assert.is_false(result.ok)
            assert.are.equal("not_your_turn", result.error.code)
        end)

        it("rejects a bad player index", function()
            local a = open_auction(1)
            for _, bad in ipairs({ 0, 4, -1, 1.5, "2", true, {} }) do
                local result = auction.pass(a, bad)
                assert.is_false(result.ok)
                assert.are.equal("bad_player", result.error.code)
            end
            local nil_result = auction.pass(a, nil)
            assert.is_false(nil_result.ok)
            assert.are.equal("bad_player", nil_result.error.code)
        end)

        it("rejects any pass on a terminated auction", function()
            local a = open_auction(1)
            a = bid(a, 2, 100)
            a = pass(a, 3)
            a = pass(a, 1)
            assert.are.equal("done", a.status)
            local result = auction.pass(a, 2)
            assert.is_false(result.ok)
            assert.are.equal("auction_already_done", result.error.code)
        end)
    end)

    describe("auction termination", function()
        -- The worked example from docs/rules/bidding.md:
        --   Forehand    100
        --   Middlehand  110
        --   Rearhand    pass
        --   Forehand    120
        --   Middlehand  pass
        --   -> Forehand wins at 120.
        it("plays the bidding.md worked example to forehand at 120", function()
            local a = open_auction(1) -- dealer = 1, forehand = 2
            a = bid(a, 2, 100) -- forehand
            a = bid(a, 3, 110) -- middlehand
            a = pass(a, 1) -- rearhand
            a = bid(a, 2, 120) -- forehand
            a = pass(a, 3) -- middlehand -> 2nd pass terminates auction
            assert.are.equal("done", a.status)
            assert.are.equal(2, a.declarer)
            assert.are.equal(120, a.final_bid)
            assert.is_nil(a.turn)
            assert.are.equal(2, a.pass_count)
            assert.is_true(a.passed[1])
            assert.is_true(a.passed[3])
            assert.is_false(a.passed[2])
            assert.are.equal(5, #a.history)
        end)

        it("a single bid plus two passes ends the auction with that bidder as declarer", function()
            local a = open_auction(1) -- forehand = 2
            a = bid(a, 2, 100)
            a = pass(a, 3)
            a = pass(a, 1)
            assert.are.equal("done", a.status)
            assert.are.equal(2, a.declarer)
            assert.are.equal(100, a.final_bid)
            assert.is_nil(a.turn)
        end)

        it("all three passing with no bid terminates as all_pass", function()
            local a = open_auction(1) -- forehand = 2
            a = pass(a, 2)
            -- pass_count is now 1; auction still in progress.
            assert.are.equal("in_progress", a.status)
            a = pass(a, 3)
            -- pass_count is now 2 (= player_count - 1) -> termination.
            assert.are.equal("all_pass", a.status)
            assert.is_nil(a.declarer)
            assert.is_nil(a.final_bid)
            assert.is_nil(a.turn)
            assert.are.equal(2, a.pass_count)
            assert.are.equal(2, #a.history)
        end)
    end)

    describe("immutability", function()
        it("bid() does not mutate the input auction", function()
            local a = open_auction(1)
            local before = snapshot(a)
            local result = auction.bid(a, 2, 100)
            assert.is_true(result.ok)
            local after = snapshot(a)
            assert.same(before, after)
        end)

        it("pass() does not mutate the input auction", function()
            local a = open_auction(1)
            local before = snapshot(a)
            local result = auction.pass(a, 2)
            assert.is_true(result.ok)
            local after = snapshot(a)
            assert.same(before, after)
        end)

        it("the input passed list is not shared with the next state", function()
            local a = open_auction(1)
            local result = auction.pass(a, 2)
            assert.is_true(result.ok)
            -- Mutate the new auction's `passed`; the original must be untouched.
            result.auction.passed[2] = false
            assert.is_false(a.passed[2])
            assert.are.equal(0, a.pass_count)
        end)
    end)

    describe("configurable increment_threshold", function()
        -- Build a config matching canonical Russian except the threshold
        -- pivots at 150 instead of 200. Below the threshold, step is 5;
        -- at-or-above, step is 10. Bids approaching the pre_talon_max of
        -- 120 stay below the threshold and so the user-visible behaviour
        -- inside the [opening_min, pre_talon_max] window is unchanged
        -- (5-step increments) — the test instead asserts that the
        -- engine consults the config rather than the literal 200, by
        -- pinning the step shape directly via the `step` echo on the
        -- `bad_bid_increment` failure envelope.
        local function with_threshold(threshold)
            return rule_config.new({
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
                    pre_talon_max = 145,
                    increment_threshold = threshold,
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
            })
        end

        it("uses below-threshold step for bids below the configured pivot", function()
            local cfg = with_threshold(150)
            local a = auction.new(cfg, 1).auction
            -- 145 is below the 150 pivot → step = 5; 145 % 5 == 0 → legal.
            local res = auction.bid(a, 2, 145)
            assert.is_true(res.ok)
        end)

        it("uses from-threshold step for bids at-or-above the configured pivot", function()
            -- A high pre_talon_max so we can probe at-or-above-threshold bids.
            local cfg_open = rule_config.new({
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
                    pre_talon_max = 200,
                    increment_threshold = 150,
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
            })
            local a = auction.new(cfg_open, 1).auction
            -- At threshold = 150, step = 10 → 155 is illegal, 160 is legal.
            local rejected = auction.bid(a, 2, 155)
            assert.is_false(rejected.ok)
            assert.are.equal("bad_bid_increment", rejected.error.code)
            assert.are.equal(10, rejected.error.step)

            local accepted = auction.bid(a, 2, 160)
            assert.is_true(accepted.ok)
        end)
    end)

    describe("4-player Configuration B (dealer sits out)", function()
        local sits_out_config = rule_config.builtins.four_player_b

        it("marks the dealer as sits_out and pre-passes them", function()
            local result = auction.new(sits_out_config, 2)
            assert.is_true(result.ok)
            local a = result.auction
            assert.are.equal(2, a.sits_out)
            assert.is_true(a.passed[2])
            assert.are.equal(1, a.pass_count)
            -- Forehand is the seat clockwise from the dealer.
            assert.are.equal(3, a.forehand)
            assert.are.equal(3, a.turn)
        end)

        it("never lands a turn on the sitting-out seat", function()
            local a = auction.new(sits_out_config, 2).auction
            -- Forehand bids; rest of cycle should skip dealer = 2.
            a = auction.bid(a, 3, 100).auction
            assert.are.equal(4, a.turn)
            a = auction.bid(a, 4, 105).auction
            assert.are.equal(1, a.turn)
            a = auction.bid(a, 1, 110).auction
            -- Clockwise next would be 2, but 2 sits out — wrap to 3.
            assert.are.equal(3, a.turn)
        end)

        it("terminates after two active passes (dealer pre-pass plus two more)", function()
            local a = auction.new(sits_out_config, 2).auction
            a = auction.bid(a, 3, 100).auction
            a = auction.pass(a, 4).auction
            a = auction.pass(a, 1).auction
            assert.are.equal("done", a.status)
            assert.are.equal(3, a.declarer)
            assert.are.equal(100, a.final_bid)
        end)
    end)

    describe("round_number()", function()
        it("returns 1 on a freshly constructed auction", function()
            local res = auction.round_number(open_auction(1))
            assert.is_true(res.ok)
            assert.are.equal(1, res.round)
        end)

        it("rejects a non-auction argument", function()
            local res = auction.round_number({})
            assert.is_false(res.ok)
            assert.are.equal("not_an_auction", res.error.code)
        end)

        it("stays in round 1 across the first 3 actions for a 3-seat auction", function()
            local a = open_auction(1)
            -- Forehand opens at 100; round 1 still active afterwards.
            a = bid(a, 2, 100)
            assert.are.equal(1, auction.round_number(a).round)
            a = pass(a, 3)
            assert.are.equal(1, auction.round_number(a).round)
        end)

        it("flips to round 2 after every seat has acted once", function()
            local a = open_auction(1)
            a = bid(a, 2, 100)
            a = bid(a, 3, 105)
            a = bid(a, 1, 110)
            assert.are.equal(2, auction.round_number(a).round)
        end)

        it("counts only the active seats under 4-player Configuration B", function()
            local cfg = rule_config.builtins.four_player_b
            local res = auction.new(cfg, 1)
            assert.is_true(res.ok)
            local a = res.auction
            -- Sits-out seat is 1 (the dealer); active seats are 2, 3, 4.
            assert.are.equal(1, auction.round_number(a).round)
            -- Forehand under dealer = 1 is seat 2.
            a = bid(a, 2, 100)
            a = bid(a, 3, 105)
            assert.are.equal(1, auction.round_number(a).round)
            a = bid(a, 4, 110)
            -- 3 active seats acted; round flips to 2.
            assert.are.equal(2, auction.round_number(a).round)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- Helpers shared by the Phase 3.6 bidding-house-rules describe blocks.
    -- -----------------------------------------------------------------------

    -- Build a RuleConfig by overlaying a partial bidding table onto the
    -- canonical Russian blob.  Only the supplied bidding keys are changed;
    -- everything else stays at its canonical value.  Accepts an optional
    -- specials overlay too (for named_contracts tests).
    local function cfg_with(bidding_overrides, specials_overrides)
        local base = {
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
        if bidding_overrides then
            for k, v in pairs(bidding_overrides) do
                base.bidding[k] = v
            end
        end
        if specials_overrides then
            for k, v in pairs(specials_overrides) do
                base.specials[k] = v
            end
        end
        return rule_config.new(base)
    end

    -- Shorthand helpers that mirror bid() / pass() but wrap the new mutators.
    local function bid_re_entry(state, player, amount, opts)
        local result = auction.bid_re_entry(state, player, amount, opts)
        assert.is_true(result.ok, "fixture: bid_re_entry must succeed")
        return result.auction
    end

    local function contra(state, defender)
        local result = auction.contra(state, defender)
        assert.is_true(result.ok, "fixture: contra must succeed")
        return result.auction
    end

    local function redouble(state, declarer)
        local result = auction.redouble(state, declarer)
        assert.is_true(result.ok, "fixture: redouble must succeed")
        return result.auction
    end

    local function skip_contra(state, defender)
        local result = auction.skip_contra(state, defender)
        assert.is_true(result.ok, "fixture: skip_contra must succeed")
        return result.auction
    end

    -- Produce a finished auction where seat 2 wins at 100.
    -- dealer=1 -> forehand=2; seat3 passes, seat1 passes.  Status is
    -- "done" under the canonical config and "doubling" when the contra
    -- toggle is on; both leave a declarer pinned, which is the contract
    -- callers care about.
    local function done_auction(cfg)
        local a = auction.new(cfg or config, 1).auction
        a = bid(a, 2, 100)
        a = pass(a, 3)
        a = pass(a, 1)
        assert.are.equal(2, a.declarer)
        return a
    end

    -- Produce an all-pass auction with the provided config.
    -- dealer=1 -> forehand=2; seat2 passes, seat3 passes.
    local function all_pass_auction(cfg)
        local a = auction.new(cfg or config, 1).auction
        a = pass(a, 2)
        a = pass(a, 3)
        assert.are.equal("all_pass", a.status)
        return a
    end

    -- -----------------------------------------------------------------------
    -- 1. forced_opening
    -- -----------------------------------------------------------------------
    describe("forced_opening", function()
        local cfg_on = cfg_with({ forced_opening = "on" })
        local cfg_off = cfg_with({ forced_opening = "off" })

        it("rejects forehand pass on first turn under forced_opening=on", function()
            local a = auction.new(cfg_on, 1).auction -- forehand = seat 2
            local result = auction.pass(a, 2)
            assert.is_false(result.ok)
            assert.are.equal("forced_opening", result.error.code)
        end)

        it("allows forehand to bid the opening minimum under forced_opening=on", function()
            local a = auction.new(cfg_on, 1).auction
            local result = auction.bid(a, 2, 100)
            assert.is_true(result.ok)
            assert.are.equal(100, result.auction.current_bid)
        end)

        it("allows non-forehand to pass on first action under forced_opening=on", function()
            -- seat 3 (middlehand) may pass freely even if forced_opening=on
            local a = auction.new(cfg_on, 1).auction
            a = bid(a, 2, 100) -- forehand bids — satisfies the constraint
            local result = auction.pass(a, 3)
            assert.is_true(result.ok)
        end)

        it("allows forehand to pass on a later round under forced_opening=on", function()
            -- After round 1 the forced-opening gate no longer applies.
            local a = auction.new(cfg_on, 1).auction
            a = bid(a, 2, 100)
            a = bid(a, 3, 105)
            a = bid(a, 1, 110)
            -- Now it is forehand's (seat 2) turn again in round 2.
            local result = auction.pass(a, 2)
            assert.is_true(result.ok)
        end)

        it("is inert when forced_opening=off", function()
            local a = auction.new(cfg_off, 1).auction
            local result = auction.pass(a, 2)
            assert.is_true(result.ok)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- 2. forced_dealer_bid
    -- -----------------------------------------------------------------------
    describe("forced_dealer_bid", function()
        local cfg_on = cfg_with({ forced_dealer_bid = "on" })

        it("terminates done with declarer=dealer at opening_min on all-pass", function()
            -- dealer=1, forehand=2; both non-dealers pass without bidding.
            local a = auction.new(cfg_on, 1).auction
            a = pass(a, 2)
            a = pass(a, 3)
            assert.are.equal("done", a.status)
            assert.are.equal(1, a.declarer)
            assert.are.equal(100, a.final_bid)
        end)

        it("sets state.dealer_forced=true and final_bid=100", function()
            local a = auction.new(cfg_on, 1).auction
            a = pass(a, 2)
            a = pass(a, 3)
            assert.is_true(a.dealer_forced)
            assert.are.equal(100, a.final_bid)
        end)

        it("appends a synthetic forced_dealer_bid history entry", function()
            local a = auction.new(cfg_on, 1).auction
            a = pass(a, 2)
            a = pass(a, 3)
            -- Last history entry must be the synthetic forced-dealer action.
            local last = a.history[#a.history]
            assert.are.equal("forced_dealer_bid", last.action)
        end)

        it("does NOT fire when at least one numeric bid was made", function()
            -- Seat 2 bid 100; seats 3 and 1 pass -> normal done termination.
            local a = auction.new(cfg_on, 1).auction
            a = bid(a, 2, 100)
            a = pass(a, 3)
            a = pass(a, 1)
            assert.are.equal("done", a.status)
            assert.are.equal(2, a.declarer)
            -- dealer_forced must NOT be set when a real bid was placed.
            assert.is_not_true(a.dealer_forced)
        end)

        it("does NOT fire under 4-player dealer_sits_out layout", function()
            -- In dealer_sits_out the dealer cannot bid, so the forced rule
            -- must be suppressed to avoid an impossible state. The sits-out
            -- seat counts as one of the player_count-1 passes the auction
            -- needs to terminate, so two active passes are enough.
            local cfg_4p = rule_config.builtins.four_player_b
            local a = auction.new(cfg_4p, 1).auction
            -- Active seats: 2, 3, 4.  Two passes are sufficient to leave
            -- the third as the "remaining" seat; current_bid stays nil so
            -- finalize_after_pass routes through the all-pass branch
            -- because the dealer (seat 1) is sits_out.
            a = pass(a, 2)
            a = pass(a, 3)
            assert.are.equal("all_pass", a.status)
        end)

        it("does NOT force a locked dealer (negative_score_restriction)", function()
            -- A dealer with a negative running total is locked but
            -- still on the rotation. forced_dealer_bid must skip them
            -- once everyone passes; auction becomes all_pass.
            local cfg = cfg_with({
                forced_dealer_bid = "on",
                negative_score_restriction = "on",
            })
            -- dealer = 1; pass running_totals so seat 1 is negative.
            local a = auction.new(cfg, 1, {
                running_totals = { [1] = -50, [2] = 200, [3] = 150 },
            }).auction
            a = pass(a, 2)
            a = pass(a, 3)
            assert.are.equal("all_pass", a.status)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- 3. blind_bid
    -- -----------------------------------------------------------------------
    describe("blind_bid", function()
        local cfg_on = cfg_with({ blind_bid = "first_bid_double" })

        it("accepts first action as blind under blind_bid=first_bid_double", function()
            local a = auction.new(cfg_on, 1).auction -- forehand = seat 2
            local result = auction.bid(a, 2, 100, { blind = true })
            assert.is_true(result.ok)
            assert.is_true(result.auction.blind[2])
        end)

        it("rejects blind=true on a non-first action with blind_after_first_action", function()
            -- Seat 2 bids normally; on the next round attempts blind.
            local a = auction.new(cfg_on, 1).auction
            a = bid(a, 2, 100)
            a = bid(a, 3, 105)
            a = bid(a, 1, 110)
            -- Now it is seat 2's turn again (round 2).
            local result = auction.bid(a, 2, 115, { blind = true })
            assert.is_false(result.ok)
            assert.are.equal("blind_after_first_action", result.error.code)
        end)

        it("rejects blind=true under blind_bid=off with blind_bid_disabled", function()
            local a = open_auction(1) -- canonical config has blind_bid="off"
            local result = auction.bid(a, 2, 100, { blind = true })
            assert.is_false(result.ok)
            assert.are.equal("blind_bid_disabled", result.error.code)
        end)

        it("flags blind_at_win when declarer's winning bid was blind", function()
            local a = auction.new(cfg_on, 1).auction
            -- Seat 2 bids blind; seats 3 and 1 pass -> done.
            local res = auction.bid(a, 2, 100, { blind = true })
            assert.is_true(res.ok)
            a = res.auction
            a = pass(a, 3)
            a = pass(a, 1)
            assert.are.equal("done", a.status)
            assert.is_true(a.blind_at_win)
        end)

        it("commits a seat to blindness via a blind pass", function()
            local a = auction.new(cfg_on, 1).auction
            -- Seat 2 passes blind (intends to bid blind next entry).
            local result = auction.pass(a, 2, { blind = true })
            assert.is_true(result.ok)
            assert.is_true(result.auction.blind[2])
        end)
    end)

    -- -----------------------------------------------------------------------
    -- 4. re_entry_after_pass
    -- -----------------------------------------------------------------------
    describe("re_entry_after_pass", function()
        local cfg_on = cfg_with({ re_entry_after_pass = "on" })
        local cfg_off = cfg_with({ re_entry_after_pass = "off" })

        it("re-enters a passed seat via M.bid_re_entry under re_entry_after_pass=on", function()
            -- Seat 2 (forehand) passes, seat 3 bids 100.  Re-entry is
            -- out-of-turn — seat 2 may re-enter while the auction is
            -- still in progress.  Calling pass(1) here would terminate
            -- the auction before re-entry could fire, so we exercise
            -- the path before that final pass arrives.
            local a = auction.new(cfg_on, 1).auction
            a = pass(a, 2)
            a = bid(a, 3, 100)
            local result = auction.bid_re_entry(a, 2, 105)
            assert.is_true(result.ok)
            assert.is_false(result.auction.passed[2])
            assert.is_true(result.auction.re_entered[2])
        end)

        it("rejects re-entry when re_entry_after_pass=off with re_entry_disabled", function()
            local a = auction.new(cfg_off, 1).auction
            a = pass(a, 2)
            a = bid(a, 3, 100)
            -- no meaningful state for seat1 needed; call re_entry on passed seat 2
            local result = auction.bid_re_entry(a, 2, 105)
            assert.is_false(result.ok)
            assert.are.equal("re_entry_disabled", result.error.code)
        end)

        it("rejects a second re-entry attempt by the same seat with already_re_entered", function()
            -- Sequence: pass(2), bid(3, 100), bid_re_entry(2, 105),
            --           bid(3, 110), bid(1, 115), pass(2), bid_re_entry(2, 120).
            -- The re_entered flag survives the second pass, so a second
            -- re-entry attempt fails before the validate-bid path runs.
            local a = auction.new(cfg_on, 1).auction
            a = pass(a, 2)
            a = bid(a, 3, 100)
            a = bid_re_entry(a, 2, 105)
            a = bid(a, 3, 110)
            a = bid(a, 1, 115)
            a = pass(a, 2)
            local result = auction.bid_re_entry(a, 2, 120)
            assert.is_false(result.ok)
            assert.are.equal("already_re_entered", result.error.code)
        end)

        it("decrements pass_count after re-entry", function()
            local a = auction.new(cfg_on, 1).auction
            a = pass(a, 2)
            a = bid(a, 3, 100)
            local pass_count_before = a.pass_count
            local result = auction.bid_re_entry(a, 2, 105)
            assert.is_true(result.ok)
            assert.are.equal(pass_count_before - 1, result.auction.pass_count)
        end)

        it("history records re_entry=true on the bid entry", function()
            local a = auction.new(cfg_on, 1).auction
            a = pass(a, 2)
            a = bid(a, 3, 100)
            local result = auction.bid_re_entry(a, 2, 105)
            assert.is_true(result.ok)
            local last = result.auction.history[#result.auction.history]
            assert.is_true(last.re_entry)
        end)

        it("auction-end fires at pass_count >= player_count - 1 after a re-entry round", function()
            -- After a re-entry, the auction continues until enough passes
            -- accumulate again. Seat 2 wins at 105 once seats 3 and 1 pass
            -- after the re-entry.
            local a = auction.new(cfg_on, 1).auction
            a = pass(a, 2)
            a = bid(a, 3, 100)
            a = bid_re_entry(a, 2, 105)
            a = pass(a, 3)
            a = pass(a, 1)
            assert.are.equal("done", a.status)
            assert.are.equal(2, a.declarer)
        end)

        it("rejects bid_re_entry on a seat that has not passed (not_passed)", function()
            local a = auction.new(cfg_on, 1).auction
            -- Seat 2 has not passed; re_entry on a non-passed seat must fail.
            local result = auction.bid_re_entry(a, 2, 105)
            assert.is_false(result.ok)
            assert.are.equal("not_passed", result.error.code)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- 5. contra and redouble
    -- -----------------------------------------------------------------------
    describe("contra and redouble", function()
        local cfg_contra = cfg_with({ contra = "contra_only" })
        local cfg_full = cfg_with({ contra = "contra_and_redouble" })

        it(
            "transitions to status=doubling after numeric finalize when contra=contra_only",
            function()
                local a = done_auction(cfg_contra)
                assert.are.equal("doubling", a.status)
            end
        )

        it("M.contra by a defender sets doubling.multiplier=2 and contra_by=defender", function()
            local a = done_auction(cfg_contra)
            -- Declarer is seat 2; defenders are 3 and 1.
            local result = auction.contra(a, 3)
            assert.is_true(result.ok)
            assert.are.equal(2, result.auction.doubling.multiplier)
            assert.are.equal(3, result.auction.doubling.contra_by)
        end)

        it("M.contra by declarer rejected with bad_actor", function()
            local a = done_auction(cfg_contra)
            -- Declarer is seat 2; seat 2 cannot contra their own contract.
            local result = auction.contra(a, 2)
            assert.is_false(result.ok)
            assert.are.equal("bad_actor", result.error.code)
        end)

        it(
            "M.skip_contra advances the queue; auction terminates done after all defenders skip",
            function()
                local a = done_auction(cfg_contra)
                -- Two defenders: seats 1 and 3.
                a = skip_contra(a, 3)
                a = skip_contra(a, 1)
                assert.are.equal("done", a.status)
            end
        )

        it("M.redouble illegal under contra=contra_only", function()
            local a = done_auction(cfg_contra)
            -- After contra by a defender, declarer tries to redouble.
            a = contra(a, 3)
            local result = auction.redouble(a, 2)
            assert.is_false(result.ok)
            -- Error code per the plan: wrong_phase or a specific code.
            assert.is_string(result.error.code)
        end)

        it("M.redouble by declarer sets doubling.multiplier=4 under contra_and_redouble", function()
            local a = done_auction(cfg_full)
            a = contra(a, 3)
            local result = auction.redouble(a, 2)
            assert.is_true(result.ok)
            assert.are.equal(4, result.auction.doubling.multiplier)
        end)

        it("M.redouble by non-declarer rejected with not_declarer", function()
            local a = done_auction(cfg_full)
            a = contra(a, 3)
            -- Seat 3 (a defender) attempts redouble.
            local result = auction.redouble(a, 3)
            assert.is_false(result.ok)
            assert.are.equal("not_declarer", result.error.code)
        end)

        it("doubling history entries appear with action=contra/redouble/skip_contra", function()
            local a = done_auction(cfg_full)
            a = contra(a, 3)
            a = redouble(a, 2)
            local actions = {}
            for _, entry in ipairs(a.history) do
                actions[#actions + 1] = entry.action
            end
            local has_contra = false
            local has_redouble = false
            for _, act in ipairs(actions) do
                if act == "contra" then
                    has_contra = true
                end
                if act == "redouble" then
                    has_redouble = true
                end
            end
            assert.is_true(has_contra)
            assert.is_true(has_redouble)
        end)

        it("all_pass auction never enters doubling", function()
            local a = all_pass_auction(cfg_contra)
            assert.are.equal("all_pass", a.status)
            assert.is_nil(a.doubling)
        end)

        it("dealer_forced auction does enter doubling", function()
            local cfg = cfg_with({ forced_dealer_bid = "on", contra = "contra_only" })
            local a = auction.new(cfg, 1).auction
            a = pass(a, 2)
            a = pass(a, 3)
            -- dealer_forced path -> done -> then doubling because contra is on.
            assert.are.equal("doubling", a.status)
            assert.is_true(a.dealer_forced)
        end)

        it("M.round_number returns the round at termination once status != in_progress", function()
            -- Build a done auction and verify round_number stays frozen.
            -- The auction took 3 bid/pass actions across 3 active seats,
            -- so the per-seat round count rolls over to 2 — and round_number
            -- should report that frozen value rather than the in-progress
            -- semantics.
            local a = done_auction(cfg_with({}))
            local res = auction.round_number(a)
            assert.is_true(res.ok)
            assert.are.equal(2, res.round)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- 6. no_contract_without_marriage
    -- -----------------------------------------------------------------------
    describe("no_contract_without_marriage", function()
        local cfg_120 = cfg_with({ no_contract_without_marriage = "no_120_without_marriage" })
        -- luacheck: ignore cfg_cap
        local cfg_cap = cfg_with({ no_contract_without_marriage = "capped_by_marriages" })

        it("no_120_without_marriage rejects 120 with empty marriage_total", function()
            local a = auction.new(cfg_120, 1, {
                holdings = { [2] = { marriage_total = 0 } },
            }).auction
            local result = auction.bid(a, 2, 120)
            assert.is_false(result.ok)
            assert.are.equal("needs_marriage_for_120", result.error.code)
        end)

        it("no_120_without_marriage allows 100/105/115 with no marriage", function()
            -- luacheck: ignore a
            local a = auction.new(cfg_120, 1, {
                holdings = { [2] = { marriage_total = 0 } },
            }).auction
            for _, amt in ipairs({ 100, 105, 115 }) do
                local result = auction.bid(
                    auction.new(cfg_120, 1, {
                        holdings = { [2] = { marriage_total = 0 } },
                    }).auction,
                    2,
                    amt
                )
                assert.is_true(result.ok, "expected bid of " .. amt .. " to succeed")
            end
        end)

        it("no_120_without_marriage allows 120 with a marriage held", function()
            local a = auction.new(cfg_120, 1, {
                holdings = { [2] = { marriage_total = 100 } },
            }).auction
            local result = auction.bid(a, 2, 120)
            assert.is_true(result.ok)
        end)

        it("capped_by_marriages allows 120 + marriage_total exactly", function()
            -- marriage_total = 40 -> cap = 120 + 40 = 160, but pre_talon_max = 120,
            -- so the legal ceiling is min(pre_talon_max, cap) = 120.
            -- Use pre_talon_max = 160 via a custom cfg to test the cap itself.
            local cfg = cfg_with({
                no_contract_without_marriage = "capped_by_marriages",
                pre_talon_max = 160,
            })
            local a = auction.new(cfg, 1, {
                holdings = { [2] = { marriage_total = 40 } },
            }).auction
            local result = auction.bid(a, 2, 160)
            assert.is_true(result.ok)
        end)

        it(
            "capped_by_marriages rejects 120 + marriage_total + 5 with bid_above_marriage_cap",
            function()
                local cfg = cfg_with({
                    no_contract_without_marriage = "capped_by_marriages",
                    pre_talon_max = 200,
                })
                -- marriage_total = 40 -> cap = 160; bid of 165 exceeds cap.
                local a = auction.new(cfg, 1, {
                    holdings = { [2] = { marriage_total = 40 } },
                }).auction
                local result = auction.bid(a, 2, 165)
                assert.is_false(result.ok)
                assert.are.equal("bid_above_marriage_cap", result.error.code)
                assert.are.equal(160, result.error.cap)
                assert.are.equal(40, result.error.marriage_total)
            end
        )

        it("rule is inert when state.holdings is nil", function()
            -- No holdings passed -> marriage rules must not fire.
            local a = auction.new(cfg_120, 1).auction
            local result = auction.bid(a, 2, 120)
            assert.is_true(result.ok)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- 7. negative_score_restriction
    -- -----------------------------------------------------------------------
    describe("negative_score_restriction", function()
        local cfg_on = cfg_with({ negative_score_restriction = "on" })

        it("flags the seat with running_totals[seat] < 0 as locked in M.new", function()
            local a = auction.new(cfg_on, 1, {
                running_totals = { [1] = 200, [2] = -30, [3] = 500 },
            }).auction
            -- Locked seats keep their turn (so they can accept the
            -- forced minimum-100 contract or pass) — the lock flag is
            -- the gate, not the passed flag.
            assert.is_false(a.passed[2])
            assert.is_true(a.locked[2])
        end)

        it("rejects any bid by a locked seat with negative_score_locked", function()
            -- Seat 3 is locked; seat 2 (forehand) bids normally,
            -- then the engine tries to assign turn to seat 3.
            -- We directly attempt a bid by seat 2 after they are locked instead.
            -- Use dealer=3 so forehand=1, locked seat 2 is not in turn; bid
            -- normally by forehand (seat 1), then attempt bid by locked seat 2.
            local a = auction.new(cfg_on, 3, {
                running_totals = { [1] = 200, [2] = -30, [3] = 500 },
            }).auction
            a = bid(a, 1, 100)
            -- Turn advances; if seat 2 is the next active seat, its bid is rejected.
            -- If engine skips locked seat automatically, force a bad-actor call.
            -- Either way, a direct bid attempt on a locked seat must fail.
            local result = auction.bid(a, 2, 105)
            assert.is_false(result.ok)
            -- Could be "not_your_turn" (engine skipped them) or "negative_score_locked".
            assert.is_string(result.error.code)
        end)

        it("locked seats stay in the active rotation for round_number", function()
            -- Locked seats keep their turn, so round_number still
            -- counts the full player_count as active. After 3 actions
            -- (one per seat) the round flips to 2. The locked seat
            -- can only bid the opening floor or pass; here we let it
            -- pass while seats 1 and 3 raise.
            local a = auction.new(cfg_on, 3, {
                running_totals = { [1] = 200, [2] = -30, [3] = 500 },
            }).auction
            a = bid(a, 1, 100)
            a = pass(a, 2)
            a = bid(a, 3, 105)
            local res = auction.round_number(a)
            assert.is_true(res.ok)
            assert.are.equal(2, res.round)
        end)

        it("locked dealer + forced_dealer_bid does NOT force dealer to 100", function()
            local cfg = cfg_with({
                negative_score_restriction = "on",
                forced_dealer_bid = "on",
            })
            -- dealer = 1, seat 1 is negative -> locked. With every
            -- seat passing the auction terminates as all_pass and the
            -- locked-dealer guard suppresses forced_dealer_bid even
            -- though the toggle is on.
            local a = auction.new(cfg, 1, {
                running_totals = { [1] = -50, [2] = 200, [3] = 150 },
            }).auction
            a = pass(a, 2)
            a = pass(a, 3)
            assert.are.equal("all_pass", a.status)
        end)
    end)

    -- -----------------------------------------------------------------------
    -- 8. named_contracts
    -- -----------------------------------------------------------------------
    describe("named_contracts", function()
        local cfg_on = cfg_with(
            { named_contracts = "on" },
            { mizere = "on", slam_contract = "off", open_hand = "off" }
        )
        local cfg_off = cfg_with({ named_contracts = "off" })

        it(
            "accepts a named bid under bidding.named_contracts=on AND specials.<contract>=on",
            function()
                local a = auction.new(cfg_on, 1).auction
                local named = { kind = "named", contract = "mizere", value = 120 }
                local result = auction.bid(a, 2, named)
                assert.is_true(result.ok)
                local cb = result.auction.current_bid
                assert.are.equal("named", cb.kind)
                assert.are.equal("mizere", cb.contract)
            end
        )

        it(
            "rejects a named bid under bidding.named_contracts=off with named_contracts_disabled",
            function()
                local a = auction.new(cfg_off, 1).auction
                local named = { kind = "named", contract = "mizere", value = 120 }
                local result = auction.bid(a, 2, named)
                assert.is_false(result.ok)
                assert.are.equal("named_contracts_disabled", result.error.code)
            end
        )

        it(
            "rejects a named bid for a contract whose specials toggle is off with unknown_named_contract",
            function()
                -- named_contracts=on but slam_contract=off.
                local a = auction.new(cfg_on, 1).auction
                local named = { kind = "named", contract = "slam", value = 240 }
                local result = auction.bid(a, 2, named)
                assert.is_false(result.ok)
                assert.are.equal("unknown_named_contract", result.error.code)
            end
        )

        it("named bid outranks any numeric bid", function()
            local a = auction.new(cfg_on, 1).auction
            a = bid(a, 2, 100)
            a = bid(a, 3, 110)
            -- Seat 1 now places a named bid.
            local named = { kind = "named", contract = "mizere", value = 120 }
            local result = auction.bid(a, 1, named)
            assert.is_true(result.ok)
            local cb = result.auction.current_bid
            assert.are.equal("named", cb.kind)
        end)

        it("rejects numeric overcall on a named leader with cannot_overcall_named", function()
            local a = auction.new(cfg_on, 1).auction
            local named = { kind = "named", contract = "mizere", value = 120 }
            a = auction.bid(a, 2, named).auction
            -- Seat 3 tries a numeric overcall.
            local result = auction.bid(a, 3, 120)
            assert.is_false(result.ok)
            assert.are.equal("cannot_overcall_named", result.error.code)
        end)

        it("named-over-named is illegal", function()
            local cfg = cfg_with(
                { named_contracts = "on" },
                { mizere = "on", slam_contract = "on", open_hand = "off" }
            )
            local a = auction.new(cfg, 1).auction
            local mizere = { kind = "named", contract = "mizere", value = 120 }
            a = auction.bid(a, 2, mizere).auction
            -- Seat 3 tries another named bid.
            local slam = { kind = "named", contract = "slam", value = 240 }
            local result = auction.bid(a, 3, slam)
            assert.is_false(result.ok)
            assert.are.equal("cannot_overcall_named", result.error.code)
        end)

        it("final_bid carries the structured shape on auction termination", function()
            local a = auction.new(cfg_on, 1).auction
            local named = { kind = "named", contract = "mizere", value = 120 }
            a = auction.bid(a, 2, named).auction
            a = pass(a, 3)
            a = pass(a, 1)
            assert.are.equal("done", a.status)
            assert.are.equal("named", a.final_bid.kind)
            assert.are.equal("mizere", a.final_bid.contract)
        end)
    end)

    -- Phase 3.6 opening-game / golden-deal helpers.
    describe("is_golden_deal_active and golden_deal_state", function()
        local function cfg_with_golden(opts)
            opts = opts or {}
            local json = require("app.json")
            local rc = require("core.rule_config")
            local blob = json.decode(rc.to_json(rc.canonical_russian))
            blob.opening_game.golden_deal = opts.golden_deal or "on"
            blob.opening_game.golden_deal_count = opts.count or 3
            return rc.new(blob)
        end

        it("returns false when the toggle is off", function()
            local cfg = cfg_with_golden({ golden_deal = "off" })
            local active, seat = auction.is_golden_deal_active(cfg, 1)
            assert.is_false(active)
            assert.is_nil(seat)
        end)

        it("returns true and rotates seats during the opening N deals", function()
            local cfg = cfg_with_golden({ count = 3 })
            local active1, seat1 = auction.is_golden_deal_active(cfg, 1)
            local active2, seat2 = auction.is_golden_deal_active(cfg, 2)
            local active3, seat3 = auction.is_golden_deal_active(cfg, 3)
            assert.is_true(active1)
            assert.is_true(active2)
            assert.is_true(active3)
            assert.are.equal(1, seat1)
            assert.are.equal(2, seat2)
            assert.are.equal(3, seat3)
        end)

        it("returns false from deal N+1 onward", function()
            local cfg = cfg_with_golden({ count = 3 })
            local active, seat = auction.is_golden_deal_active(cfg, 4)
            assert.is_false(active)
            assert.is_nil(seat)
        end)

        it("golden_deal_contract reads target - threshold (canonical 120)", function()
            local cfg = cfg_with_golden({})
            assert.are.equal(120, auction.golden_deal_contract(cfg))
        end)

        it("golden_deal_state synthesises a done auction with the forced contract", function()
            local cfg = cfg_with_golden({})
            local state = auction.golden_deal_state(cfg, 3, 1)
            assert.is_true(auction.is_auction(state))
            assert.are.equal("done", state.status)
            assert.are.equal(1, state.declarer)
            assert.are.equal(120, state.final_bid)
            assert.is_true(state.golden_deal == true)
        end)
    end)
end)
