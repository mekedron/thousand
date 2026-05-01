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
                    misdeal_handling = "standard",
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
                    pre_talon_max = 145,
                    increment_threshold = threshold,
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
                barrel = { threshold = 880, deal_count = 3, fall_off_penalty = -120 },
                endgame = { target_score = 1000 },
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
                    misdeal_handling = "standard",
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
                    pre_talon_max = 200,
                    increment_threshold = 150,
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
                barrel = { threshold = 880, deal_count = 3, fall_off_penalty = -120 },
                endgame = { target_score = 1000 },
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
end)
