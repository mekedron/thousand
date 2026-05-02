local talon = require("core.talon")
local auction = require("core.auction")
local card = require("core.card")
local rule_config = require("core.rule_config")

local config = rule_config.canonical_russian

-- A finalized auction where forehand (player 2 with dealer 1) wins at 100.
local function finalized_auction(opts)
    opts = opts or {}
    local dealer = opts.dealer or 1
    local final_bid = opts.final_bid or 100
    local result = auction.new(config, dealer)
    assert.is_true(result.ok)
    local a = result.auction
    -- Forehand opens at the requested final_bid; the other two pass.
    a = assert(auction.bid(a, a.forehand, final_bid).auction)
    -- Pass the remaining two seats clockwise.
    while a.status == "in_progress" do
        a = assert(auction.pass(a, a.turn).auction)
    end
    return a
end

-- Build hands and talon out of distinct cards. We don't need a real deal
-- here — just three 7-card hands and a 3-card talon, all unique.
local function build_dealable_set()
    -- 24 unique cards, listed in a fixed order so tests can target a
    -- specific card by index without coupling to deck shuffle order.
    local cards = {}
    for _, suit in ipairs(card.SUITS) do
        for _, rank in ipairs(card.RANKS) do
            cards[#cards + 1] = card.new(suit, rank)
        end
    end
    -- 7 + 7 + 7 + 3 = 24
    local hands = { {}, {}, {} }
    for player = 1, 3 do
        for i = 1, 7 do
            hands[player][i] = cards[(player - 1) * 7 + i]
        end
    end
    local talon_cards = { cards[22], cards[23], cards[24] }
    return hands, talon_cards
end

local function fresh_talon(opts)
    opts = opts or {}
    local a = opts.auction or finalized_auction(opts)
    local hands, talon_cards = build_dealable_set()
    local result = talon.new(config, a, hands, talon_cards)
    assert.is_true(result.ok, "fixture: talon.new must succeed")
    return result.talon, hands, talon_cards
end

local function take(state)
    local result = talon.take(state)
    assert.is_true(result.ok, "fixture: take must succeed")
    return result.talon
end

local function pass(state, target, c)
    local result = talon.pass(state, target, c)
    assert.is_true(result.ok, "fixture: pass must succeed")
    return result.talon
end

local function snapshot(state)
    local hand_sizes = {}
    for i = 1, #state.hands do
        hand_sizes[i] = #state.hands[i]
    end
    local passes = {}
    for p in pairs(state.passes_received) do
        passes[#passes + 1] = p
    end
    table.sort(passes)
    return {
        status = state.status,
        declarer = state.declarer,
        original_bid = state.original_bid,
        final_bid = state.final_bid,
        talon_size = #state.talon,
        hand_sizes = hand_sizes,
        passes = passes,
        history_len = #state.history,
    }
end

describe("core.talon", function()
    describe("new()", function()
        it("rejects a non-RuleConfig", function()
            local a = finalized_auction()
            local hands, talon_cards = build_dealable_set()
            for _, bad in ipairs({ 42, "config", {}, true }) do
                local result = talon.new(bad, a, hands, talon_cards)
                assert.is_false(result.ok)
                assert.are.equal("not_a_rule_config", result.error.code)
            end
            local nil_result = talon.new(nil, a, hands, talon_cards)
            assert.is_false(nil_result.ok)
            assert.are.equal("not_a_rule_config", nil_result.error.code)
        end)

        it("rejects a non-auction", function()
            local hands, talon_cards = build_dealable_set()
            for _, bad in ipairs({ 42, "auction", {}, true }) do
                local result = talon.new(config, bad, hands, talon_cards)
                assert.is_false(result.ok)
                assert.are.equal("not_an_auction", result.error.code)
            end
            local nil_result = talon.new(config, nil, hands, talon_cards)
            assert.is_false(nil_result.ok)
            assert.are.equal("not_an_auction", nil_result.error.code)
        end)

        it("rejects an in-progress auction", function()
            local result = auction.new(config, 1)
            assert.is_true(result.ok)
            local hands, talon_cards = build_dealable_set()
            local talon_result = talon.new(config, result.auction, hands, talon_cards)
            assert.is_false(talon_result.ok)
            assert.are.equal("auction_not_done", talon_result.error.code)
            assert.are.equal("in_progress", talon_result.error.status)
        end)

        it("rejects an all-pass auction", function()
            local a = assert(auction.new(config, 1).auction)
            a = assert(auction.pass(a, a.turn).auction)
            a = assert(auction.pass(a, a.turn).auction)
            assert.are.equal("all_pass", a.status)
            local hands, talon_cards = build_dealable_set()
            local result = talon.new(config, a, hands, talon_cards)
            assert.is_false(result.ok)
            assert.are.equal("auction_was_all_pass", result.error.code)
        end)

        it("rejects bad hands shape", function()
            local a = finalized_auction()
            local _, talon_cards = build_dealable_set()
            -- Wrong outer type
            local r1 = talon.new(config, a, "hands", talon_cards)
            assert.is_false(r1.ok)
            assert.are.equal("bad_hands_shape", r1.error.code)
            -- Wrong number of hands
            local r2 = talon.new(config, a, { {}, {} }, talon_cards)
            assert.is_false(r2.ok)
            assert.are.equal("bad_hands_shape", r2.error.code)
            -- Wrong cards-per-hand
            local short_hands = { {}, {}, {} }
            local r3 = talon.new(config, a, short_hands, talon_cards)
            assert.is_false(r3.ok)
            assert.are.equal("bad_hands_shape", r3.error.code)
            -- Non-card entry
            local hands_with_junk = build_dealable_set()
            hands_with_junk[1][1] = "not a card"
            local r4 = talon.new(config, a, hands_with_junk, talon_cards)
            assert.is_false(r4.ok)
            assert.are.equal("bad_hands_shape", r4.error.code)
        end)

        it("rejects bad talon shape", function()
            local a = finalized_auction()
            local hands = build_dealable_set()
            local r1 = talon.new(config, a, hands, "talon")
            assert.is_false(r1.ok)
            assert.are.equal("bad_talon_shape", r1.error.code)
            local short_talon = { card.new("hearts", "9"), card.new("hearts", "J") }
            local r2 = talon.new(config, a, hands, short_talon)
            assert.is_false(r2.ok)
            assert.are.equal("bad_talon_shape", r2.error.code)
            local r3 = talon.new(config, a, hands, {
                card.new("hearts", "9"),
                "not a card",
                card.new("hearts", "Q"),
            })
            assert.is_false(r3.ok)
            assert.are.equal("bad_talon_shape", r3.error.code)
        end)

        it("returns a fresh state with status 'revealed'", function()
            local state = fresh_talon()
            assert.is_true(talon.is_talon(state))
            assert.are.equal("revealed", state.status)
            assert.are.equal(3, #state.talon)
            assert.are.equal(7, #state.hands[1])
            assert.are.equal(7, #state.hands[2])
            assert.are.equal(7, #state.hands[3])
            assert.are.equal(0, #state.history)
            -- Forehand for dealer=1 is player 2; that's the declarer at 100.
            assert.are.equal(2, state.declarer)
            assert.are.equal(100, state.original_bid)
            assert.are.equal(100, state.final_bid)
        end)

        it("preserves declarer and bid for higher final bids", function()
            local a = finalized_auction({ dealer = 2, final_bid = 120 })
            local hands, talon_cards = build_dealable_set()
            local result = talon.new(config, a, hands, talon_cards)
            assert.is_true(result.ok)
            assert.are.equal(3, result.talon.declarer)
            assert.are.equal(120, result.talon.original_bid)
            assert.are.equal(120, result.talon.final_bid)
        end)
    end)

    describe("take()", function()
        it("declarer hand grows to 10 and talon empties", function()
            local state = fresh_talon()
            local result = talon.take(state)
            assert.is_true(result.ok)
            local taken = result.talon
            assert.are.equal("awaiting_pass", taken.status)
            assert.are.equal(0, #taken.talon)
            assert.are.equal(10, #taken.hands[taken.declarer])
            for i = 1, 3 do
                if i ~= taken.declarer then
                    assert.are.equal(7, #taken.hands[i])
                end
            end
            assert.are.equal(1, #taken.history)
            assert.are.equal("take", taken.history[1].action)
            assert.are.equal(taken.declarer, taken.history[1].player)
        end)

        it("rejects take on a non-talon", function()
            for _, bad in ipairs({ 42, "talon", {}, true }) do
                local result = talon.take(bad)
                assert.is_false(result.ok)
                assert.are.equal("not_a_talon", result.error.code)
            end
            local nil_result = talon.take(nil)
            assert.is_false(nil_result.ok)
            assert.are.equal("not_a_talon", nil_result.error.code)
        end)

        it("rejects take when not in 'revealed' phase", function()
            local state = take(fresh_talon())
            local result = talon.take(state)
            assert.is_false(result.ok)
            assert.are.equal("wrong_phase", result.error.code)
            assert.are.equal("awaiting_pass", result.error.status)
        end)

        it("does not mutate the input state", function()
            local state = fresh_talon()
            local before = snapshot(state)
            local _ = take(state)
            assert.same(before, snapshot(state))
        end)
    end)

    describe("pass()", function()
        it("first pass moves a card to the named opponent and stays awaiting_pass", function()
            local state = take(fresh_talon())
            local declarer = state.declarer
            local target = (declarer % 3) + 1
            local card_to_pass = state.hands[declarer][1]
            local result = talon.pass(state, target, card_to_pass)
            assert.is_true(result.ok)
            local next_state = result.talon
            assert.are.equal("awaiting_pass", next_state.status)
            assert.are.equal(9, #next_state.hands[declarer])
            assert.are.equal(8, #next_state.hands[target])
            assert.is_true(next_state.passes_received[target])
            assert.are.equal(2, #next_state.history)
            local entry = next_state.history[2]
            assert.are.equal("pass", entry.action)
            assert.are.equal(declarer, entry.player)
            assert.are.equal(target, entry.target)
            assert.are.equal(card_to_pass.suit, entry.card.suit)
            assert.are.equal(card_to_pass.rank, entry.card.rank)
        end)

        it("second pass produces 8/8/8 and transitions to awaiting_raise", function()
            local state = take(fresh_talon())
            local declarer = state.declarer
            local target1 = (declarer % 3) + 1
            local target2 = (declarer + 1) % 3 + 1
            state = pass(state, target1, state.hands[declarer][1])
            state = pass(state, target2, state.hands[declarer][1])
            assert.are.equal("awaiting_raise", state.status)
            assert.are.equal(8, #state.hands[1])
            assert.are.equal(8, #state.hands[2])
            assert.are.equal(8, #state.hands[3])
        end)

        it("rejects pass before take", function()
            local state = fresh_talon()
            local declarer = state.declarer
            local target = (declarer % 3) + 1
            local result = talon.pass(state, target, state.hands[declarer][1])
            assert.is_false(result.ok)
            assert.are.equal("wrong_phase", result.error.code)
            assert.are.equal("revealed", result.error.status)
        end)

        it("rejects pass to the declarer", function()
            local state = take(fresh_talon())
            local declarer = state.declarer
            local result = talon.pass(state, declarer, state.hands[declarer][1])
            assert.is_false(result.ok)
            assert.are.equal("bad_target", result.error.code)
            assert.are.equal(declarer, result.error.declarer)
        end)

        it("rejects pass to a target that already received one", function()
            local state = take(fresh_talon())
            local declarer = state.declarer
            local target = (declarer % 3) + 1
            state = pass(state, target, state.hands[declarer][1])
            local result = talon.pass(state, target, state.hands[declarer][1])
            assert.is_false(result.ok)
            assert.are.equal("target_already_received", result.error.code)
            assert.are.equal(target, result.error.target)
        end)

        it("rejects a card not in the declarer's hand", function()
            local state = take(fresh_talon())
            local declarer = state.declarer
            local target = (declarer % 3) + 1
            -- Pick a card that lives in a defender's hand instead.
            local foreign = state.hands[target][1]
            local result = talon.pass(state, target, foreign)
            assert.is_false(result.ok)
            assert.are.equal("card_not_in_hand", result.error.code)
        end)

        it("rejects a non-card payload", function()
            local state = take(fresh_talon())
            local declarer = state.declarer
            local target = (declarer % 3) + 1
            for _, bad in ipairs({ 42, "card", {}, true }) do
                local result = talon.pass(state, target, bad)
                assert.is_false(result.ok)
                assert.are.equal("card_not_in_hand", result.error.code)
            end
            local nil_result = talon.pass(state, target, nil)
            assert.is_false(nil_result.ok)
            assert.are.equal("card_not_in_hand", nil_result.error.code)
        end)

        it("rejects a bad target index", function()
            local state = take(fresh_talon())
            local c = state.hands[state.declarer][1]
            for _, bad in ipairs({ 0, 4, -1, 1.5, "2", true, {} }) do
                local result = talon.pass(state, bad, c)
                assert.is_false(result.ok)
                assert.are.equal("bad_target", result.error.code)
            end
            local nil_result = talon.pass(state, nil, c)
            assert.is_false(nil_result.ok)
            assert.are.equal("bad_target", nil_result.error.code)
        end)

        it("rejects pass after passes are complete", function()
            local state = take(fresh_talon())
            local declarer = state.declarer
            local target1 = (declarer % 3) + 1
            local target2 = (declarer + 1) % 3 + 1
            state = pass(state, target1, state.hands[declarer][1])
            state = pass(state, target2, state.hands[declarer][1])
            local result = talon.pass(state, target1, state.hands[declarer][1])
            assert.is_false(result.ok)
            assert.are.equal("wrong_phase", result.error.code)
            assert.are.equal("awaiting_raise", result.error.status)
        end)

        it("does not mutate the input state", function()
            local state = take(fresh_talon())
            local before = snapshot(state)
            local declarer = state.declarer
            local target = (declarer % 3) + 1
            local _ = pass(state, target, state.hands[declarer][1])
            assert.same(before, snapshot(state))
        end)

        it("does not share hand or passes_received tables with the next state", function()
            local state = take(fresh_talon())
            local declarer = state.declarer
            local target = (declarer % 3) + 1
            local result = talon.pass(state, target, state.hands[declarer][1])
            assert.is_true(result.ok)
            -- Mutate the new talon's hand and passes; the original must be untouched.
            result.talon.hands[declarer][1] = nil
            result.talon.passes_received[target] = nil
            assert.are.equal(10, #state.hands[declarer])
            assert.is_nil(state.passes_received[target])
        end)
    end)

    describe("raise()", function()
        local function awaiting_raise(opts)
            local state = take(fresh_talon(opts))
            local declarer = state.declarer
            local target1 = (declarer % 3) + 1
            local target2 = (declarer + 1) % 3 + 1
            state = pass(state, target1, state.hands[declarer][1])
            state = pass(state, target2, state.hands[declarer][1])
            return state
        end

        it("happy path: raise from 100 to 105 (step 5 below 200)", function()
            local state = awaiting_raise()
            local result = talon.raise(state, 105)
            assert.is_true(result.ok)
            assert.are.equal("done", result.talon.status)
            assert.are.equal(105, result.talon.final_bid)
            assert.are.equal(100, result.talon.original_bid)
            local last = result.talon.history[#result.talon.history]
            assert.are.equal("raise", last.action)
            assert.are.equal(105, last.amount)
        end)

        it("happy path: post-talon raise can exceed the pre-talon ceiling", function()
            -- pre_talon_max is 120; the post-talon raise has no cap.
            local state = awaiting_raise()
            local result = talon.raise(state, 150)
            assert.is_true(result.ok)
            assert.are.equal(150, result.talon.final_bid)
        end)

        it("happy path: raise above 200 uses step 10", function()
            local state = awaiting_raise()
            local result = talon.raise(state, 200)
            assert.is_true(result.ok)
            assert.are.equal(200, result.talon.final_bid)
            local further = talon.raise(state, 210)
            assert.is_true(further.ok)
            assert.are.equal(210, further.talon.final_bid)
        end)

        it("rejects raise on a non-talon", function()
            for _, bad in ipairs({ 42, "talon", {}, true }) do
                local result = talon.raise(bad, 110)
                assert.is_false(result.ok)
                assert.are.equal("not_a_talon", result.error.code)
            end
            local nil_result = talon.raise(nil, 110)
            assert.is_false(nil_result.ok)
            assert.are.equal("not_a_talon", nil_result.error.code)
        end)

        it("rejects raise before passes are complete", function()
            local state = take(fresh_talon())
            local result = talon.raise(state, 110)
            assert.is_false(result.ok)
            assert.are.equal("wrong_phase", result.error.code)
            assert.are.equal("awaiting_pass", result.error.status)
        end)

        it("rejects raise before take", function()
            local state = fresh_talon()
            local result = talon.raise(state, 110)
            assert.is_false(result.ok)
            assert.are.equal("wrong_phase", result.error.code)
            assert.are.equal("revealed", result.error.status)
        end)

        it("rejects a non-integer amount", function()
            local state = awaiting_raise()
            for _, bad in ipairs({ 100.5, "110", true, {} }) do
                local result = talon.raise(state, bad)
                assert.is_false(result.ok)
                assert.are.equal("raise_not_integer", result.error.code)
            end
            local nil_result = talon.raise(state, nil)
            assert.is_false(nil_result.ok)
            assert.are.equal("raise_not_integer", nil_result.error.code)
        end)

        it("rejects an amount equal to or below the current bid", function()
            local state = awaiting_raise()
            for _, bad in ipairs({ 100, 95, 0, -10 }) do
                local result = talon.raise(state, bad)
                assert.is_false(result.ok)
                assert.are.equal("raise_not_higher", result.error.code)
                assert.are.equal(100, result.error.current_bid)
            end
        end)

        it("rejects an amount with the wrong increment", function()
            local state = awaiting_raise()
            for _, bad in ipairs({ 102, 107, 113, 119, 121, 198 }) do
                local result = talon.raise(state, bad)
                assert.is_false(result.ok)
                assert.are.equal("bad_raise_increment", result.error.code)
                assert.are.equal(5, result.error.step)
            end
            -- Above 200 the step is 10, so 205 / 215 are invalid.
            for _, bad in ipairs({ 205, 215, 295 }) do
                local result = talon.raise(state, bad)
                assert.is_false(result.ok)
                assert.are.equal("bad_raise_increment", result.error.code)
                assert.are.equal(10, result.error.step)
            end
        end)

        it("rejects raise after the talon phase is done", function()
            local state = awaiting_raise()
            state = assert(talon.raise(state, 110).talon)
            assert.are.equal("done", state.status)
            local result = talon.raise(state, 120)
            assert.is_false(result.ok)
            assert.are.equal("wrong_phase", result.error.code)
            assert.are.equal("done", result.error.status)
        end)

        it("does not mutate the input state", function()
            local state = awaiting_raise()
            local before = snapshot(state)
            local _ = talon.raise(state, 110)
            assert.same(before, snapshot(state))
        end)

        it("uses the configured increment_threshold for the step pivot", function()
            -- Custom config: pivot at 150 instead of 200, otherwise canonical.
            local custom = rule_config.new({
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
            })

            -- Drive a finalized auction under the custom config: forehand
            -- opens at 100, the other two pass.
            local a = assert(auction.new(custom, 1).auction)
            a = assert(auction.bid(a, a.forehand, 100).auction)
            while a.status == "in_progress" do
                a = assert(auction.pass(a, a.turn).auction)
            end

            local hands, talon_cards = build_dealable_set()
            local state = assert(talon.new(custom, a, hands, talon_cards).talon)
            state = take(state)
            local declarer = state.declarer
            local t1 = (declarer % 3) + 1
            local t2 = (declarer + 1) % 3 + 1
            state = pass(state, t1, state.hands[declarer][1])
            state = pass(state, t2, state.hands[declarer][1])
            assert.are.equal("awaiting_raise", state.status)

            -- 145 is still below the 150 pivot → step = 5; 145 % 5 = 0 → legal.
            assert.is_true(talon.raise(state, 145).ok)

            -- 150 is at the pivot → step = 10; 150 % 10 = 0 → legal.
            assert.is_true(talon.raise(state, 150).ok)

            -- 155 is above pivot → step = 10; 155 % 10 = 5 → rejected.
            local rejected = talon.raise(state, 155)
            assert.is_false(rejected.ok)
            assert.are.equal("bad_raise_increment", rejected.error.code)
            assert.are.equal(10, rejected.error.step)
        end)
    end)

    describe("skip_raise()", function()
        local function awaiting_raise(opts)
            local state = take(fresh_talon(opts))
            local declarer = state.declarer
            local target1 = (declarer % 3) + 1
            local target2 = (declarer + 1) % 3 + 1
            state = pass(state, target1, state.hands[declarer][1])
            state = pass(state, target2, state.hands[declarer][1])
            return state
        end

        it("happy path: keeps the original bid and marks the phase done", function()
            local state = awaiting_raise()
            local result = talon.skip_raise(state)
            assert.is_true(result.ok)
            assert.are.equal("done", result.talon.status)
            assert.are.equal(100, result.talon.final_bid)
            assert.are.equal(100, result.talon.original_bid)
            local last = result.talon.history[#result.talon.history]
            assert.are.equal("skip_raise", last.action)
        end)

        it("rejects skip_raise on a non-talon", function()
            for _, bad in ipairs({ 42, "talon", {}, true }) do
                local result = talon.skip_raise(bad)
                assert.is_false(result.ok)
                assert.are.equal("not_a_talon", result.error.code)
            end
            local nil_result = talon.skip_raise(nil)
            assert.is_false(nil_result.ok)
            assert.are.equal("not_a_talon", nil_result.error.code)
        end)

        it("rejects skip_raise before passes complete", function()
            local state = take(fresh_talon())
            local result = talon.skip_raise(state)
            assert.is_false(result.ok)
            assert.are.equal("wrong_phase", result.error.code)
            assert.are.equal("awaiting_pass", result.error.status)
        end)

        it("rejects skip_raise after the talon phase is done", function()
            local state = awaiting_raise()
            state = assert(talon.skip_raise(state).talon)
            assert.are.equal("done", state.status)
            local result = talon.skip_raise(state)
            assert.is_false(result.ok)
            assert.are.equal("wrong_phase", result.error.code)
        end)

        it("does not mutate the input state", function()
            local state = awaiting_raise()
            local before = snapshot(state)
            local _ = talon.skip_raise(state)
            assert.same(before, snapshot(state))
        end)
    end)

    describe("rebuy()", function()
        it("happy path: claimant becomes declarer and final_bid jumps to contract", function()
            local state = fresh_talon()
            local declarer_before = state.declarer
            -- Forehand (player 2) is declarer at 100; player 3 buys it
            -- away at 240.
            local result = talon.rebuy(state, 3, 240)
            assert.is_true(result.ok)
            local taken = result.talon
            assert.are.equal("revealed", taken.status)
            assert.are.equal(3, taken.declarer)
            assert.are.equal(240, taken.final_bid)
            -- original_bid preserves the auction-time outcome for audit.
            assert.are.equal(100, taken.original_bid)
            -- Hands and talon cards are untouched.
            assert.are.equal(7, #taken.hands[1])
            assert.are.equal(7, #taken.hands[2])
            assert.are.equal(7, #taken.hands[3])
            assert.are.equal(3, #taken.talon)
            -- A history entry records the swap with the previous declarer.
            local last = taken.history[#taken.history]
            assert.are.equal("rebuy", last.action)
            assert.are.equal(3, last.player)
            assert.are.equal(declarer_before, last.target)
            assert.are.equal(240, last.amount)
        end)

        it("happy path: after rebuy, take/pass/raise advance the new declarer", function()
            local state = fresh_talon()
            state = assert(talon.rebuy(state, 3, 240).talon)
            -- Continue with the new declarer (3): take, then pass to 1
            -- and 2, then skip the raise.
            state = take(state)
            assert.are.equal(10, #state.hands[3])
            assert.are.equal(7, #state.hands[1])
            assert.are.equal(7, #state.hands[2])
            state = pass(state, 1, state.hands[3][1])
            state = pass(state, 2, state.hands[3][1])
            assert.are.equal("awaiting_raise", state.status)
            local skip_result = talon.skip_raise(state)
            assert.is_true(skip_result.ok)
            assert.are.equal("done", skip_result.talon.status)
            -- final_bid still 240 (skip_raise leaves it alone).
            assert.are.equal(240, skip_result.talon.final_bid)
        end)

        it("happy path: post-rebuy raise validates against the new contract floor", function()
            local state = fresh_talon()
            state = assert(talon.rebuy(state, 3, 240).talon)
            state = take(state)
            state = pass(state, 1, state.hands[3][1])
            state = pass(state, 2, state.hands[3][1])
            assert.are.equal("awaiting_raise", state.status)
            -- 250 is the next legal step at 240 (step = 10 above the
            -- 200 pivot); 245 is not.
            local r1 = talon.raise(state, 245)
            assert.is_false(r1.ok)
            assert.are.equal("bad_raise_increment", r1.error.code)
            local r2 = talon.raise(state, 250)
            assert.is_true(r2.ok)
            assert.are.equal(250, r2.talon.final_bid)
        end)

        it("rejects rebuy on a non-talon", function()
            for _, bad in ipairs({ 42, "talon", {}, true }) do
                local result = talon.rebuy(bad, 3, 240)
                assert.is_false(result.ok)
                assert.are.equal("not_a_talon", result.error.code)
            end
            local nil_result = talon.rebuy(nil, 3, 240)
            assert.is_false(nil_result.ok)
            assert.are.equal("not_a_talon", nil_result.error.code)
        end)

        it("rejects rebuy when not in 'revealed' phase", function()
            local state = take(fresh_talon())
            local result = talon.rebuy(state, 3, 240)
            assert.is_false(result.ok)
            assert.are.equal("wrong_phase", result.error.code)
            assert.are.equal("awaiting_pass", result.error.status)
        end)

        it("rejects the current declarer as claimant", function()
            local state = fresh_talon()
            local result = talon.rebuy(state, state.declarer, 240)
            assert.is_false(result.ok)
            assert.are.equal("bad_claimant", result.error.code)
            assert.are.equal(state.declarer, result.error.declarer)
        end)

        it("rejects an out-of-range or non-integer claimant", function()
            local state = fresh_talon()
            for _, bad in ipairs({ 0, 4, -1, 1.5, "2", true, {} }) do
                local result = talon.rebuy(state, bad, 240)
                assert.is_false(result.ok)
                assert.are.equal("bad_claimant", result.error.code)
            end
            local nil_result = talon.rebuy(state, nil, 240)
            assert.is_false(nil_result.ok)
            assert.are.equal("bad_claimant", nil_result.error.code)
        end)

        it("rejects a contract_value outside [100, 240]", function()
            local state = fresh_talon()
            for _, bad in ipairs({ 0, 50, 99, 241, 9999 }) do
                local result = talon.rebuy(state, 3, bad)
                assert.is_false(result.ok)
                assert.are.equal("bad_contract_value", result.error.code)
            end
        end)

        it("rejects a non-integer contract_value", function()
            local state = fresh_talon()
            for _, bad in ipairs({ 240.5, "240", true, {} }) do
                local result = talon.rebuy(state, 3, bad)
                assert.is_false(result.ok)
                assert.are.equal("bad_contract_value", result.error.code)
            end
            local nil_result = talon.rebuy(state, 3, nil)
            assert.is_false(nil_result.ok)
            assert.are.equal("bad_contract_value", nil_result.error.code)
        end)

        it("rejects a contract_value not strictly higher than the current bid", function()
            -- Forehand wins at 120; a 120 rebuy is not "higher" and a
            -- 100 rebuy is below — both rejected.
            local a = finalized_auction({ final_bid = 120 })
            local hands, talon_cards = build_dealable_set()
            local state = assert(talon.new(config, a, hands, talon_cards).talon)
            for _, bad in ipairs({ 100, 105, 115, 120 }) do
                local result = talon.rebuy(state, 3, bad)
                assert.is_false(result.ok, "value=" .. bad .. " should be rejected")
                assert.are.equal("contract_not_higher", result.error.code)
                assert.are.equal(120, result.error.current_bid)
            end
            -- 125 is strictly higher → accepted.
            local ok_result = talon.rebuy(state, 3, 125)
            assert.is_true(ok_result.ok)
        end)

        it("does not mutate the input state", function()
            local state = fresh_talon()
            local before = snapshot(state)
            local _ = talon.rebuy(state, 3, 240)
            assert.same(before, snapshot(state))
        end)
    end)

    describe("is_talon()", function()
        it("recognises talon states", function()
            assert.is_true(talon.is_talon(fresh_talon()))
        end)

        it("rejects everything else", function()
            for _, bad in ipairs({ 42, "talon", {}, true, finalized_auction() }) do
                assert.is_false(talon.is_talon(bad))
            end
            assert.is_false(talon.is_talon(nil))
        end)
    end)

    describe("is_bad_talon()", function()
        local nines = {
            card.new("spades", "9"),
            card.new("clubs", "9"),
            card.new("diamonds", "9"),
        }
        local single_jack = {
            card.new("spades", "9"),
            card.new("clubs", "9"),
            card.new("hearts", "J"),
        }
        local mixed = {
            card.new("spades", "K"),
            card.new("clubs", "Q"),
            card.new("diamonds", "9"),
        }
        local high = {
            card.new("spades", "A"),
            card.new("clubs", "10"),
            card.new("diamonds", "K"),
        }

        it("returns true when total points are below the default threshold", function()
            -- Three nines = 0 points; below the canonical threshold of 5.
            assert.is_true(talon.is_bad_talon(nines, 5, config))
        end)

        it("returns false when total points equal the threshold", function()
            -- 9 + 9 + J = 0 + 0 + 2 = 2 points; threshold 2 is not strictly above.
            assert.is_false(talon.is_bad_talon(single_jack, 2, config))
        end)

        it("returns false when total points exceed the threshold", function()
            -- K + Q + 9 = 4 + 3 + 0 = 7; threshold 5.
            assert.is_false(talon.is_bad_talon(mixed, 5, config))
            -- A + 10 + K = 11 + 10 + 4 = 25; well above any reasonable threshold.
            assert.is_false(talon.is_bad_talon(high, 5, config))
        end)

        it("honours custom thresholds", function()
            -- 9 + 9 + J = 2 points; threshold 3 makes it bad.
            assert.is_true(talon.is_bad_talon(single_jack, 3, config))
            -- K + Q + 9 = 7 points; threshold 8 makes it bad.
            assert.is_true(talon.is_bad_talon(mixed, 8, config))
        end)

        it("rejects non-card-shaped inputs", function()
            assert.is_false(talon.is_bad_talon({ "not a card" }, 5, config))
            assert.is_false(talon.is_bad_talon(nil, 5, config))
            assert.is_false(talon.is_bad_talon("talon", 5, config))
        end)

        it("rejects non-integer or negative thresholds", function()
            assert.is_false(talon.is_bad_talon(nines, -1, config))
            assert.is_false(talon.is_bad_talon(nines, 1.5, config))
            assert.is_false(talon.is_bad_talon(nines, "five", config))
        end)

        it("rejects non-RuleConfig configs", function()
            assert.is_false(talon.is_bad_talon(nines, 5, nil))
            assert.is_false(talon.is_bad_talon(nines, 5, { cards = {} }))
        end)
    end)

    describe("polish layout (pass_without_taking)", function()
        local polish_config = rule_config.builtins.polish

        local function build_polish_dealable_set()
            -- 24 unique cards in a stable order so tests can target by
            -- index. Polish hands are 7/7/7 + 2-card talon (drained to
            -- the two opponents) + 1-card leftover (handed to declarer
            -- when the second pass closes the talon out).
            local cards = {}
            for _, suit in ipairs(card.SUITS) do
                for _, rank in ipairs(card.RANKS) do
                    cards[#cards + 1] = card.new(suit, rank)
                end
            end
            local hands = { {}, {}, {} }
            for player = 1, 3 do
                for i = 1, 7 do
                    hands[player][i] = cards[(player - 1) * 7 + i]
                end
            end
            local talon_cards = { cards[22], cards[23] }
            local leftover_for_declarer = { cards[24] }
            return hands, talon_cards, leftover_for_declarer
        end

        local function polish_finalized_auction(opts)
            opts = opts or {}
            local dealer = opts.dealer or 1
            local final_bid = opts.final_bid or 100
            local result = auction.new(polish_config, dealer)
            assert.is_true(result.ok)
            local a = result.auction
            a = assert(auction.bid(a, a.forehand, final_bid).auction)
            while a.status == "in_progress" do
                a = assert(auction.pass(a, a.turn).auction)
            end
            return a
        end

        local function fresh_polish_talon(opts)
            opts = opts or {}
            local a = opts.auction or polish_finalized_auction(opts)
            local hands, talon_cards, leftover_for_declarer = build_polish_dealable_set()
            local result = talon.new(polish_config, a, hands, talon_cards, {
                leftover_for_declarer = leftover_for_declarer,
            })
            assert.is_true(result.ok, "fixture: polish talon.new must succeed")
            return result.talon, hands, talon_cards, leftover_for_declarer
        end

        it("constructs a 2-card talon + 1-card leftover under the Polish builtin", function()
            local state = fresh_polish_talon()
            assert.are.equal("revealed", state.status)
            assert.are.equal("pass_without_taking", state.distribution)
            assert.are.equal(2, state.opponent_count)
            assert.is_nil(state.sits_out)
            assert.is_false(state.requires_discard)
            assert.are.equal(2, #state.talon)
            assert.are.equal(7, #state.hands[1])
            assert.are.equal(7, #state.hands[2])
            assert.are.equal(7, #state.hands[3])
            assert.is_table(state.leftover_for_declarer)
            assert.are.equal(1, #state.leftover_for_declarer)
        end)

        it("rejects new() under pass_without_taking when leftover is missing", function()
            local hands, talon_cards = build_polish_dealable_set()
            local a = polish_finalized_auction()
            local result = talon.new(polish_config, a, hands, talon_cards)
            assert.is_false(result.ok)
            assert.are.equal("missing_leftover_for_declarer", result.error.code)
        end)

        it("rejects new() under pass_without_taking when leftover has wrong size", function()
            local hands, talon_cards = build_polish_dealable_set()
            local a = polish_finalized_auction()
            local result = talon.new(polish_config, a, hands, talon_cards, {
                leftover_for_declarer = {},
            })
            assert.is_false(result.ok)
            assert.are.equal("missing_leftover_for_declarer", result.error.code)
        end)

        it("rejects M.take with wrong_distribution_for_take", function()
            local state = fresh_polish_talon()
            local result = talon.take(state)
            assert.is_false(result.ok)
            assert.are.equal("wrong_distribution_for_take", result.error.code)
            assert.are.equal("pass_without_taking", result.error.distribution)
        end)

        it("rejects M.pass (declarer-hand pass) with wrong_phase", function()
            local state = fresh_polish_talon()
            -- M.pass requires status `awaiting_pass`; Polish stays at
            -- `revealed` until pass_from_talon drains the talon.
            local declarer = state.declarer
            local target = declarer == 3 and 1 or declarer + 1
            local card_in_hand = state.hands[declarer][1]
            local result = talon.pass(state, target, card_in_hand)
            assert.is_false(result.ok)
            assert.are.equal("wrong_phase", result.error.code)
        end)

        it("drains the talon via two pass_from_talon calls and lands at 8/8/8 done", function()
            local state, _, _, leftover_for_declarer = fresh_polish_talon()
            local declarer = state.declarer
            local count = polish_config.players.count
            local opp_a = (declarer % count) + 1
            local opp_b = (opp_a % count) + 1
            local leftover_card = leftover_for_declarer[1]

            local first_card = state.talon[1]
            local r1 = talon.pass_from_talon(state, opp_a, 1)
            assert.is_true(r1.ok, r1.error and r1.error.message or "")
            local s1 = r1.talon
            assert.are.equal("revealed", s1.status, "still revealed after one pass")
            assert.are.equal(1, #s1.talon)
            assert.are.equal(8, #s1.hands[opp_a])
            assert.are.equal(card.tostring(first_card), card.tostring(s1.hands[opp_a][8]))
            assert.is_true(s1.passes_received[opp_a])
            -- Declarer still at 7 between passes — leftover only lands
            -- when the talon closes out.
            assert.are.equal(7, #s1.hands[declarer])
            assert.are.equal(1, #s1.leftover_for_declarer)

            local second_card = s1.talon[1]
            local r2 = talon.pass_from_talon(s1, opp_b, 1)
            assert.is_true(r2.ok)
            local s2 = r2.talon
            assert.are.equal("done", s2.status, "done after both opponents received a card")
            assert.are.equal(0, #s2.talon)
            assert.are.equal(8, #s2.hands[opp_b])
            assert.are.equal(card.tostring(second_card), card.tostring(s2.hands[opp_b][8]))
            -- Declarer reaches 8 thanks to the leftover (consumed).
            assert.are.equal(8, #s2.hands[declarer])
            assert.are.equal(card.tostring(leftover_card), card.tostring(s2.hands[declarer][8]))
            assert.are.equal(0, #s2.leftover_for_declarer)
            -- History records both pass_from_talon actions.
            assert.are.equal(2, #s2.history)
            assert.are.equal("pass_from_talon", s2.history[1].action)
            assert.are.equal("pass_from_talon", s2.history[2].action)
        end)

        it("rejects pass_from_talon with bad_target on declarer self-pass", function()
            local state = fresh_polish_talon()
            local result = talon.pass_from_talon(state, state.declarer, 1)
            assert.is_false(result.ok)
            assert.are.equal("bad_target", result.error.code)
        end)

        it("rejects pass_from_talon with target_already_received on duplicate seat", function()
            local state = fresh_polish_talon()
            local declarer = state.declarer
            local count = polish_config.players.count
            local opp_a = (declarer % count) + 1
            local s1 = assert(talon.pass_from_talon(state, opp_a, 1).talon)
            local result = talon.pass_from_talon(s1, opp_a, 1)
            assert.is_false(result.ok)
            assert.are.equal("target_already_received", result.error.code)
        end)

        it("rejects pass_from_talon with bad_talon_index on out-of-bounds index", function()
            local state = fresh_polish_talon()
            local declarer = state.declarer
            local count = polish_config.players.count
            local opp_a = (declarer % count) + 1
            for _, bad in ipairs({ 0, 3, -1 }) do
                local result = talon.pass_from_talon(state, opp_a, bad)
                assert.is_false(result.ok, "talon_index=" .. bad .. " should be rejected")
                assert.are.equal("bad_talon_index", result.error.code)
            end
        end)

        it("rejects pass_from_talon under the canonical Russian distribution", function()
            -- Build a Russian state (default distribution) and try the
            -- new method against it. Should return the typed
            -- wrong_distribution_for_pass_from_talon.
            local a = finalized_auction()
            local hands, talon_cards = build_dealable_set()
            local state = assert(talon.new(config, a, hands, talon_cards).talon)
            local result = talon.pass_from_talon(state, 1, 1)
            assert.is_false(result.ok)
            assert.are.equal("wrong_distribution_for_pass_from_talon", result.error.code)
        end)

        it("rejects M.raise/skip_raise on Polish state (never reaches awaiting_raise)", function()
            local state = fresh_polish_talon()
            local raise_result = talon.raise(state, 110)
            assert.is_false(raise_result.ok)
            assert.are.equal("wrong_phase", raise_result.error.code)
            local skip_result = talon.skip_raise(state)
            assert.is_false(skip_result.ok)
            assert.are.equal("wrong_phase", skip_result.error.code)
        end)
    end)
end)
