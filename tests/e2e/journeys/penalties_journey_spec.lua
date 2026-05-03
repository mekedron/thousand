-- Phase 3.6 penalty house-rules e2e journey. Drives the table scene
-- through a session whose deal completes under
-- `penalties.zero_tricks = "any_three"` and asserts:
--
--   * the per-seat "Bolts: 1 / 3" counter renders on the running
--     scoreboard for the seat that took zero tricks;
--   * once seeded counters reach the threshold, the deal-done banner
--     surfaces the bolt-penalty row.
--
-- Engine math is pinned in tests/spec/core/scoring_spec; session
-- state transitions in tests/spec/app/session_penalties_spec. This
-- journey verifies the rendered output round-trips to the user.

local journey = require("tests.e2e.support.journey")
local Session = require("app.session")
local rule_config = require("core.rule_config")
local card = require("core.card")
local json = require("app.json")
local marriages_module = require("core.marriages")
local auction_module = require("core.auction")
local tricks_module = require("core.tricks")

local function find_text(j, needle)
    return j._mock.graphics.find_text(needle)
end

local function build_table_scene_in_mock(session)
    local scene_manager = require("ui.scene_manager")
    local table_scene = require("ui.scenes.table")
    local manager = scene_manager.new()
    manager:set_session(session)
    manager:register("table", table_scene.new(manager))
    manager:switch_to("table")
    return manager, manager._scenes["table"]
end

local function build_config(overrides)
    local blob = json.decode(rule_config.to_json(rule_config.canonical_russian))
    for section, fields in pairs(overrides or {}) do
        blob[section] = blob[section] or {}
        for k, v in pairs(fields) do
            blob[section][k] = v
        end
    end
    return rule_config.new(blob)
end

local function c(suit, rank)
    return card.new(suit, rank)
end

-- 24-card deal where seat 2 holds every winner (As + 10s) and sweeps
-- every trick; seats 1 and 3 finish on zero tricks.
local function bolt_layout()
    return {
        {
            c("hearts", "9"),
            c("hearts", "J"),
            c("diamonds", "9"),
            c("diamonds", "J"),
            c("clubs", "9"),
            c("clubs", "J"),
            c("spades", "9"),
            c("spades", "J"),
        },
        {
            c("hearts", "A"),
            c("hearts", "10"),
            c("diamonds", "A"),
            c("diamonds", "10"),
            c("clubs", "A"),
            c("clubs", "10"),
            c("spades", "A"),
            c("spades", "10"),
        },
        {
            c("hearts", "Q"),
            c("hearts", "K"),
            c("diamonds", "Q"),
            c("diamonds", "K"),
            c("clubs", "Q"),
            c("clubs", "K"),
            c("spades", "Q"),
            c("spades", "K"),
        },
    }
end

local function seat2_sweeps_sequence()
    return {
        { { 2, c("hearts", "A") }, { 3, c("hearts", "Q") }, { 1, c("hearts", "9") } },
        { { 2, c("hearts", "10") }, { 3, c("hearts", "K") }, { 1, c("hearts", "J") } },
        { { 2, c("diamonds", "A") }, { 3, c("diamonds", "K") }, { 1, c("diamonds", "9") } },
        { { 2, c("diamonds", "10") }, { 3, c("diamonds", "Q") }, { 1, c("diamonds", "J") } },
        { { 2, c("clubs", "A") }, { 3, c("clubs", "K") }, { 1, c("clubs", "9") } },
        { { 2, c("clubs", "10") }, { 3, c("clubs", "Q") }, { 1, c("clubs", "J") } },
        { { 2, c("spades", "A") }, { 3, c("spades", "K") }, { 1, c("spades", "9") } },
        { { 2, c("spades", "10") }, { 3, c("spades", "Q") }, { 1, c("spades", "J") } },
    }
end

local function session_at_tricks(cfg, hands, opts)
    opts = opts or {}
    local pc = cfg.players.count
    local dealer = opts.dealer or 1
    local declarer = opts.declarer or ((dealer % pc) + 1)
    local running_totals = { 0, 0, 0 }
    local holdings = {}
    for seat = 1, pc do
        local suits = marriages_module.detect(hands[seat])
        local total = 0
        for _, suit in ipairs(suits) do
            total = total + (cfg.marriages.values[suit] or 0)
        end
        holdings[seat] = { marriage_total = total }
    end
    local auction = auction_module.new(
        cfg,
        dealer,
        { holdings = holdings, running_totals = running_totals }
    ).auction
    local forehand = (dealer % pc) + 1
    auction = auction_module.bid(auction, forehand, opts.bid or 100).auction
    for seat = 1, pc do
        if seat ~= forehand and auction.status == "in_progress" then
            local r = auction_module.pass(auction, seat)
            if r.ok then
                auction = r.auction
            end
        end
    end
    local marriages = marriages_module.new(cfg).marriages
    local tricks = tricks_module.new(cfg, hands, declarer, {
        dealer = dealer,
        declarer = declarer,
    }).tricks
    return Session.from_state({
        config = cfg,
        seed = 1,
        dealer = dealer,
        hands = hands,
        auction = auction,
        marriages = marriages,
        tricks = tricks,
        talon = {
            declarer = declarer,
            final_bid = opts.bid or 100,
            status = "done",
            hands = hands,
        },
        running_totals = running_totals,
        deal_index = 1,
        zero_tricks_bolts = opts.zero_tricks_bolts,
    })
end

local function play_sequence(s, sequence)
    for _, trick in ipairs(sequence) do
        for _, p in ipairs(trick) do
            assert(s:play(p[1], p[2]).ok)
        end
    end
end

describe("penalty house rules journey", function()
    it("renders the bolts counter under the zero-trick seat", function()
        local j = journey.start({ locale = "en", width = 1024, height = 720 })
        j:step()
        local cfg = build_config({
            penalties = { zero_tricks = "any_three" },
        })
        local s = session_at_tricks(cfg, bolt_layout(), { dealer = 1, declarer = 2, bid = 100 })
        play_sequence(s, seat2_sweeps_sequence())

        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        j._mock.graphics.clear_recording()
        scene:draw(1024, 720)

        -- Seats 1 and 3 each earned a bolt this deal. The view-model
        -- exposes the per-seat counter; the renderer prints it under
        -- the seat row. The text format is `Bolts: 1 / 3`.
        assert.is_truthy(find_text(j, "Bolts: 1 / 3"))
    end)

    it("shows the bolt penalty row in the deal-done banner at threshold", function()
        local j = journey.start({ locale = "en", width = 1024, height = 720 })
        j:step()
        local cfg = build_config({
            penalties = { zero_tricks = "any_three" },
        })
        -- Seed seats 1 and 3 with two bolts; the third zero-trick deal
        -- pushes both to threshold.
        local s = session_at_tricks(cfg, bolt_layout(), {
            dealer = 1,
            declarer = 2,
            bid = 100,
            zero_tricks_bolts = { 2, 0, 2 },
        })
        play_sequence(s, seat2_sweeps_sequence())

        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        j._mock.graphics.clear_recording()
        scene:draw(1024, 720)

        assert.is_truthy(find_text(j, "Bolt penalty (zero tricks)"))
    end)
end)
