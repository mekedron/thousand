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
        it("is rejected by the Phase 1 dealer because count = 2 is not yet supported", function()
            local result = dealing.deal(deck_module.build(), rule_config.builtins.two_player_a)
            assert.is_false(result.ok)
            assert.are.equal("unsupported_player_count", result.error.code)
            assert.are.equal(2, result.error.player_count)
        end)
    end)

    describe("two_player_b", function()
        it("is rejected by the Phase 1 dealer because count = 2 is not yet supported", function()
            local result = dealing.deal(deck_module.build(), rule_config.builtins.two_player_b)
            assert.is_false(result.ok)
            assert.are.equal("unsupported_player_count", result.error.code)
            assert.are.equal(2, result.error.player_count)
        end)
    end)

    describe("four_player_a", function()
        it("is rejected by the Phase 1 dealer because count = 4 is not yet supported", function()
            local result = dealing.deal(deck_module.build(), rule_config.builtins.four_player_a)
            assert.is_false(result.ok)
            assert.are.equal("unsupported_player_count", result.error.code)
            assert.are.equal(4, result.error.player_count)
        end)
    end)

    describe("four_player_b", function()
        it("is rejected by the Phase 1 dealer because count = 4 is not yet supported", function()
            local result = dealing.deal(deck_module.build(), rule_config.builtins.four_player_b)
            assert.is_false(result.ok)
            assert.are.equal("unsupported_player_count", result.error.code)
            assert.are.equal(4, result.error.player_count)
        end)
    end)
end)
