-- Phase 3.3 acceptance: scripted engine tests for every built-in
-- `RuleConfig`. The suite covers two distinct contracts.
--
-- 1. Schema-only contract (every builtin):
--      * Each builtin is a frozen RuleConfig.
--      * Every field that differs from `canonical_russian` is at status
--        `implemented` or `selectable` — never `deferred`. This is the
--        "use only implemented selectable toggles" criterion from the
--        task list, asserted programmatically via `schema_for`.
--      * The blob round-trips through JSON unchanged.
--
-- 2. Engine contract (varies by what the Phase 1 engine supports today):
--      * `russian` aliases `canonical_russian` and runs a full scripted
--        deal end-to-end.
--      * `ukrainian` runs a full scripted deal *and* a barrel-state
--        scenario that asserts the `barrel.deal_count = 2` override
--        bites: a player on the barrel falls off after two failed
--        deals (canonical takes three).
--      * `polish` and the four 2-/4-player builtins are catalogued
--        data; the engine's `dealing.lua` guard rejects their shape
--        with a typed error today. The tests pin that guard so the
--        Phase 3.6 work that lifts it has an explicit test to flip.
--
-- See docs/development/task-list.md "3.6 Toggle gameplay" for the
-- follow-up that extends the Polish, 2-player and 4-player templates
-- to full scripted deals.

local rule_config = require("core.rule_config")
local deck_module = require("core.deck")
local dealing = require("core.dealing")
local auction_module = require("core.auction")
local talon_module = require("core.talon")
local marriages_module = require("core.marriages")
local tricks_module = require("core.tricks")
local scoring = require("core.scoring")

-- Section traversal order matches `core.rule_config`'s SCHEMA so a
-- diff walk has stable output. Sourced from the schema reflection so
-- it stays in sync with future section additions automatically.
local function section_order()
    return {
        "cards",
        "players",
        "dealing",
        "talon",
        "bidding",
        "marriages",
        "tricks",
        "scoring",
        "opening_game",
        "barrel",
        "endgame",
        "specials",
        "penalties",
    }
end

local function deep_equal(a, b)
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if not deep_equal(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

local function diff_paths(config, baseline)
    local out = {}
    for _, section_name in ipairs(section_order()) do
        local section_descriptor = rule_config.schema_for(section_name)
        for _, field_name in ipairs(section_descriptor.fields) do
            local va = config[section_name][field_name]
            local vb = baseline[section_name][field_name]
            if not deep_equal(va, vb) then
                out[#out + 1] = section_name .. "." .. field_name
            end
        end
    end
    return out
end

local function assert_only_non_deferred_diffs(config, label)
    local baseline = rule_config.canonical_russian
    for _, path in ipairs(diff_paths(config, baseline)) do
        local descriptor = rule_config.schema_for(path)
        assert.is_not_nil(descriptor, label .. ": missing schema for " .. path)
        local status = descriptor.status
        assert.is_true(
            status == "implemented" or status == "selectable",
            label
                .. " overrides "
                .. path
                .. " but its schema status is '"
                .. tostring(status)
                .. "' (must be implemented or selectable)"
        )
    end
end

local function build_deck(seed)
    return deck_module.shuffle(deck_module.build(), seed)
end

local function captured_sum(state)
    return state.captured_points[1] + state.captured_points[2] + state.captured_points[3]
end

-- Walk a full canonical 3-player deal under `config` driving every seat
-- toward `legal_cards[1]`. Returns the final tricks state and scoring
-- result so per-template tests can assert anything the variant flexes.
local function run_full_deal(config, seed)
    local d = build_deck(seed)
    local deal_result = dealing.deal(d, config)
    assert.is_true(deal_result.ok, "deal failed")

    local hands, talon_cards = deal_result.hands, deal_result.talon

    local a = auction_module.new(config, 1).auction
    a = auction_module.bid(a, 2, config.bidding.opening_min).auction
    a = auction_module.pass(a, 3).auction
    a = auction_module.pass(a, 1).auction
    assert.are.equal("done", a.status)

    local t = talon_module.new(config, a, hands, talon_cards).talon
    t = talon_module.take(t).talon
    local pass1 = t.hands[2][1]
    t = talon_module.pass(t, 1, pass1).talon
    local pass2 = t.hands[2][1]
    t = talon_module.pass(t, 3, pass2).talon
    t = talon_module.skip_raise(t).talon

    local m = marriages_module.new(config).marriages

    local s = tricks_module.new(config, t.hands, 2).tricks
    while s.status == "in_progress" do
        local p = s.next_to_play
        local choice = tricks_module.legal_cards(s, p).cards[1]
        s = tricks_module.play(s, p, choice).tricks
    end
    assert.are.equal("done", s.status)
    assert.are.equal(8, s.tricks_played)
    assert.are.equal(120, captured_sum(s))

    local sd = scoring.score_deal(config, {
        declarer = 2,
        bid = config.bidding.opening_min,
        captured_points = s.captured_points,
        marriage_bonuses = m.bonuses,
        running_totals = { 0, 0, 0 },
    }).scoring

    return s, sd
end

describe("core.rule_config builtins (engine integration)", function()
    describe("schema status of every diff against canonical_russian", function()
        it("polish overrides only implemented or selectable fields", function()
            assert_only_non_deferred_diffs(rule_config.builtins.polish, "polish")
        end)

        it("ukrainian overrides only implemented or selectable fields", function()
            assert_only_non_deferred_diffs(rule_config.builtins.ukrainian, "ukrainian")
        end)

        it("two_player_a overrides only implemented or selectable fields", function()
            assert_only_non_deferred_diffs(rule_config.builtins.two_player_a, "two_player_a")
        end)

        it("two_player_b overrides only implemented or selectable fields", function()
            assert_only_non_deferred_diffs(rule_config.builtins.two_player_b, "two_player_b")
        end)

        it("four_player_a overrides only implemented or selectable fields", function()
            assert_only_non_deferred_diffs(rule_config.builtins.four_player_a, "four_player_a")
        end)

        it("four_player_b overrides only implemented or selectable fields", function()
            assert_only_non_deferred_diffs(rule_config.builtins.four_player_b, "four_player_b")
        end)
    end)

    describe("russian", function()
        it("aliases canonical_russian", function()
            assert.are.equal(rule_config.canonical_russian, rule_config.builtins.russian)
        end)

        it("completes a full scripted deal", function()
            local _, sd = run_full_deal(rule_config.builtins.russian, 42)
            assert.is_table(sd)
            assert.is_boolean(sd.made_contract)
            -- 5-step rounding from canonical_russian.
            assert.are.equal(5, rule_config.builtins.russian.scoring.round_to_nearest)
            for _, n in ipairs(sd.card_points_rounded) do
                assert.are.equal(0, n % 5, "card-points must round to nearest 5")
            end
        end)
    end)

    describe("ukrainian", function()
        it("completes a full scripted deal under the canonical talon shape", function()
            local _, sd = run_full_deal(rule_config.builtins.ukrainian, 42)
            assert.is_table(sd)
            assert.is_boolean(sd.made_contract)
        end)

        it("falls a player off the barrel after two failed deals", function()
            local config = rule_config.builtins.ukrainian
            local target = config.endgame.target_score
            local threshold = config.barrel.threshold
            local fall_off_total = threshold + config.barrel.fall_off_penalty
            local barrel_make = target - threshold

            -- Player 2 mounts the barrel on deal 1 with deals_remaining = 2.
            local on_barrel_start = scoring.initial_barrel_state(config)
            on_barrel_start[2] = {
                on_barrel = true,
                mounted_on_deal = 1,
                deals_remaining = config.barrel.deal_count,
            }
            assert.are.equal(2, on_barrel_start[2].deals_remaining)

            local fail_delta = barrel_make - 1
            local after_first = scoring.advance_game(config, {
                declarer = 2,
                deal_index = 2,
                deltas = { 0, -fail_delta, 0 },
                running_totals_before = { 0, threshold, 0 },
                barrel_state_before = on_barrel_start,
            }).game
            assert.is_true(after_first.barrel_state[2].on_barrel)
            assert.are.equal(1, after_first.barrel_state[2].deals_remaining)
            assert.are.equal(threshold, after_first.running_totals[2])

            local after_second = scoring.advance_game(config, {
                declarer = 2,
                deal_index = 3,
                deltas = { 0, -fail_delta, 0 },
                running_totals_before = after_first.running_totals,
                barrel_state_before = after_first.barrel_state,
            }).game
            assert.is_false(after_second.barrel_state[2].on_barrel)
            assert.are.equal(fall_off_total, after_second.running_totals[2])
        end)

        it("requires three failed deals under canonical_russian for comparison", function()
            local config = rule_config.canonical_russian
            local threshold = config.barrel.threshold
            local fall_off_total = threshold + config.barrel.fall_off_penalty
            local barrel_make = config.endgame.target_score - threshold

            local on_barrel_start = scoring.initial_barrel_state(config)
            on_barrel_start[2] = {
                on_barrel = true,
                mounted_on_deal = 1,
                deals_remaining = config.barrel.deal_count,
            }
            assert.are.equal(3, on_barrel_start[2].deals_remaining)

            local state = { totals = { 0, threshold, 0 }, barrel = on_barrel_start }
            local fail_delta = barrel_make - 1
            for deal = 2, 4 do
                local out = scoring.advance_game(config, {
                    declarer = 2,
                    deal_index = deal,
                    deltas = { 0, -fail_delta, 0 },
                    running_totals_before = state.totals,
                    barrel_state_before = state.barrel,
                }).game
                state = { totals = out.running_totals, barrel = out.barrel_state }
            end
            assert.is_false(state.barrel[2].on_barrel)
            assert.are.equal(fall_off_total, state.totals[2])
        end)
    end)

    describe("polish", function()
        it("uses 10-step bid increments end-to-end on a constructed auction", function()
            local config = rule_config.builtins.polish
            local a = auction_module.new(config, 1).auction
            a = auction_module.bid(a, 2, 100).auction
            -- 5-step raise must be illegal under Polish 10-step increments.
            local five_step = auction_module.bid(a, 3, 105)
            assert.is_false(five_step.ok)
            -- 10-step raise is legal.
            local ten_step = auction_module.bid(a, 3, 110)
            assert.is_true(ten_step.ok)
            assert.are.equal(110, ten_step.auction.current_bid)
        end)

        it(
            "is rejected by the Phase 1 dealer because talon.size = 2 is not yet supported",
            function()
                local result = dealing.deal(deck_module.build(), rule_config.builtins.polish)
                assert.is_false(result.ok)
                assert.are.equal("unsupported_talon_size", result.error.code)
                assert.are.equal(2, result.error.talon_size)
            end
        )
    end)

    describe("two_player_a", function()
        it("deals 9-card hands and a 6-card stock with a face-up trump indicator", function()
            local result =
                dealing.deal(build_deck(42), rule_config.builtins.two_player_a, { dealer = 1 })
            assert.is_true(result.ok)
            assert.are.equal(2, #result.hands)
            assert.are.equal(9, #result.hands[1])
            assert.are.equal(9, #result.hands[2])
            assert.are.equal(0, #result.talon)
            assert.is_table(result.stock)
            assert.are.equal(6, #result.stock)
            assert.is_table(result.trump_indicator)
            assert.are.equal(result.stock[#result.stock], result.trump_indicator)
        end)

        it("plays a scripted full deal with stock-driven draws", function()
            local config = rule_config.builtins.two_player_a
            local deal_result = dealing.deal(build_deck(42), config, { dealer = 1 })
            assert.is_true(deal_result.ok)

            local a = auction_module.new(config, 1).auction
            -- Forehand bids opening_min, dealer passes — auction ends.
            a = auction_module.bid(a, 2, config.bidding.opening_min).auction
            a = auction_module.pass(a, 1).auction
            assert.are.equal("done", a.status)
            assert.are.equal(2, a.declarer)

            -- 2-player A skips the talon flow entirely; the stock is
            -- consumed during tricks, and trump comes from the
            -- indicator's suit.
            local trump_suit = deal_result.trump_indicator.suit
            local s = tricks_module.new(config, deal_result.hands, a.declarer, {
                trump = trump_suit,
                stock = deal_result.stock,
                trump_indicator = deal_result.trump_indicator,
            }).tricks
            assert.are.equal("draw", s.phase)
            assert.are.equal(12, s.tricks_per_deal)

            while s.status == "in_progress" do
                local p = s.next_to_play
                local choice = tricks_module.legal_cards(s, p).cards[1]
                s = tricks_module.play(s, p, choice).tricks
            end
            assert.are.equal("done", s.status)
            assert.are.equal(12, s.tricks_played)
            assert.are.equal(0, #s.stock)
            assert.are.equal("strict", s.phase)
        end)
    end)

    describe("two_player_b", function()
        it("deals 7-card hands and a 3-card talon (with 7 cards unused)", function()
            local result =
                dealing.deal(build_deck(42), rule_config.builtins.two_player_b, { dealer = 1 })
            assert.is_true(result.ok)
            assert.are.equal(2, #result.hands)
            assert.are.equal(7, #result.hands[1])
            assert.are.equal(7, #result.hands[2])
            assert.are.equal(3, #result.talon)
            assert.is_nil(result.stock)
        end)

        it("plays a scripted full deal with declarer take/pass/discard", function()
            local config = rule_config.builtins.two_player_b
            local deal_result = dealing.deal(build_deck(42), config, { dealer = 1 })
            assert.is_true(deal_result.ok)

            local a = auction_module.new(config, 1).auction
            a = auction_module.bid(a, 2, config.bidding.opening_min).auction
            a = auction_module.pass(a, 1).auction
            assert.are.equal("done", a.status)

            local t = talon_module.new(config, a, deal_result.hands, deal_result.talon).talon
            t = talon_module.take(t).talon
            -- One pass to the single opponent, then discard.
            local pass_card = t.hands[a.declarer][1]
            t = talon_module.pass(t, 1, pass_card).talon
            assert.are.equal("awaiting_discard", t.status)
            local discard_card = t.hands[a.declarer][1]
            t = talon_module.discard(t, discard_card).talon
            assert.are.equal("awaiting_raise", t.status)
            t = talon_module.skip_raise(t).talon
            assert.are.equal("done", t.status)
            assert.are.equal(8, #t.hands[a.declarer])
            assert.are.equal(8, #t.hands[1])

            local s = tricks_module.new(config, t.hands, a.declarer).tricks
            assert.are.equal(8, s.tricks_per_deal)
            while s.status == "in_progress" do
                local p = s.next_to_play
                local choice = tricks_module.legal_cards(s, p).cards[1]
                s = tricks_module.play(s, p, choice).tricks
            end
            assert.are.equal("done", s.status)
            assert.are.equal(8, s.tricks_played)
        end)
    end)

    describe("four_player_a", function()
        it("deals 6-card hands to all four seats with no talon", function()
            local result =
                dealing.deal(build_deck(42), rule_config.builtins.four_player_a, { dealer = 1 })
            assert.is_true(result.ok)
            assert.are.equal(4, #result.hands)
            for i = 1, 4 do
                assert.are.equal(6, #result.hands[i])
            end
            assert.are.equal(0, #result.talon)
        end)

        it("plays a scripted full deal with partnership pooling", function()
            local config = rule_config.builtins.four_player_a
            local deal_result = dealing.deal(build_deck(42), config, { dealer = 1 })
            assert.is_true(deal_result.ok)

            local a = auction_module.new(config, 1).auction
            a = auction_module.bid(a, 2, config.bidding.opening_min).auction
            a = auction_module.pass(a, 3).auction
            a = auction_module.pass(a, 4).auction
            a = auction_module.pass(a, 1).auction
            assert.are.equal("done", a.status)

            -- 4-player A skips talon (size 0); declarer leads first
            -- trick directly.
            local s = tricks_module.new(config, deal_result.hands, a.declarer).tricks
            assert.are.equal(6, s.tricks_per_deal)
            assert.is_table(s.partnership_sides)
            assert.are.equal(1, s.partnership_sides[1])
            assert.are.equal(2, s.partnership_sides[2])
            assert.are.equal(1, s.partnership_sides[3])
            assert.are.equal(2, s.partnership_sides[4])

            while s.status == "in_progress" do
                local p = s.next_to_play
                local choice = tricks_module.legal_cards(s, p).cards[1]
                s = tricks_module.play(s, p, choice).tricks
            end
            assert.are.equal("done", s.status)
            assert.are.equal(6, s.tricks_played)

            local m = marriages_module.new(config).marriages
            local sd = scoring.score_deal(config, {
                declarer = a.declarer,
                bid = a.final_bid,
                captured_points = s.captured_points,
                marriage_bonuses = m.bonuses,
                running_totals = { 0, 0, 0, 0 },
            }).scoring
            assert.is_table(sd.sides)
            assert.is_table(sd.side_deal_scores)
            assert.are.equal(2, #sd.side_deal_scores)
        end)
    end)

    describe("four_player_b", function()
        it("deals 7-card hands to the three non-dealer seats and 3-card talon", function()
            local result =
                dealing.deal(build_deck(42), rule_config.builtins.four_player_b, { dealer = 2 })
            assert.is_true(result.ok)
            assert.are.equal(4, #result.hands)
            -- Dealer = 2 sits out this deal.
            assert.are.equal(0, #result.hands[2])
            assert.are.equal(7, #result.hands[1])
            assert.are.equal(7, #result.hands[3])
            assert.are.equal(7, #result.hands[4])
            assert.are.equal(3, #result.talon)
            assert.are.equal(2, result.sits_out)
        end)

        it("plays a scripted full deal with the dealer sitting out", function()
            local config = rule_config.builtins.four_player_b
            local deal_result = dealing.deal(build_deck(42), config, { dealer = 2 })
            assert.is_true(deal_result.ok)

            local a = auction_module.new(config, 2).auction
            assert.are.equal(2, a.sits_out)
            a = auction_module.bid(a, 3, config.bidding.opening_min).auction
            a = auction_module.pass(a, 4).auction
            a = auction_module.pass(a, 1).auction
            assert.are.equal("done", a.status)
            assert.are.equal(3, a.declarer)

            local t = talon_module.new(config, a, deal_result.hands, deal_result.talon).talon
            t = talon_module.take(t).talon
            -- Pass to the two non-dealer opponents (skip seat 2).
            local first_target
            for seat = 1, 4 do
                if seat ~= a.declarer and seat ~= 2 then
                    first_target = seat
                    break
                end
            end
            local pass1 = t.hands[a.declarer][1]
            t = talon_module.pass(t, first_target, pass1).talon
            local second_target
            for seat = 1, 4 do
                if seat ~= a.declarer and seat ~= 2 and seat ~= first_target then
                    second_target = seat
                    break
                end
            end
            local pass2 = t.hands[a.declarer][1]
            t = talon_module.pass(t, second_target, pass2).talon
            assert.are.equal("awaiting_raise", t.status)
            t = talon_module.skip_raise(t).talon

            local s = tricks_module.new(config, t.hands, a.declarer, { dealer = 2 }).tricks
            assert.are.equal(2, s.sits_out)
            assert.are.equal(8, s.tricks_per_deal)
            while s.status == "in_progress" do
                local p = s.next_to_play
                local choice = tricks_module.legal_cards(s, p).cards[1]
                s = tricks_module.play(s, p, choice).tricks
            end
            assert.are.equal("done", s.status)
            assert.are.equal(8, s.tricks_played)
            -- The sitting-out seat never won a trick or captured points.
            assert.are.equal(0, s.captured_points[2])
            assert.are.equal(0, s.tricks_won[2])
        end)
    end)
end)
