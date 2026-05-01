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
end)
