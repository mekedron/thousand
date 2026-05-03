-- Phase 3.7 cross-deal counters e2e journey. Drives the table scene
-- under three new toggles and asserts the rendered output:
--
--   * `penalties.no_win_streak = "any_three"` exposes the "No-win
--     streak: N / 3" line per seat.
--   * `barrel.fall_count_resets_to_zero = "on"` exposes the
--     "Barrel falls: N / 3" line per seat.
--   * canonical_russian (both off) renders neither line.
--
-- Engine math is pinned in tests/spec/core/scoring_spec and
-- tests/spec/app/session_no_win_streak_spec /
-- session_barrel_falls_spec; this journey verifies the rendered
-- output round-trips to the user.

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

local function generic_layout()
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

local function session_at_tricks(cfg, hands, opts)
    opts = opts or {}
    local pc = cfg.players.count
    local dealer = opts.dealer or 1
    local declarer = opts.declarer or ((dealer % pc) + 1)
    local running_totals = opts.running_totals or { 0, 0, 0 }
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
        no_win_streak_counts = opts.no_win_streak_counts,
        barrel_fall_counts = opts.barrel_fall_counts,
    })
end

describe("cross-deal counters journey", function()
    local j

    before_each(function()
        j = journey.start({ locale = "en", width = 1024, height = 720 })
        j:step()
    end)

    after_each(function()
        if j then
            j:stop()
        end
    end)

    it("renders the no-win streak counter when the toggle is on", function()
        local cfg = build_config({
            penalties = { no_win_streak = "any_three", no_win_streak_threshold = 3 },
        })
        local s = session_at_tricks(cfg, generic_layout(), {
            dealer = 1,
            declarer = 2,
            bid = 100,
            no_win_streak_counts = { 0, 0, 2 },
        })
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        j._mock.graphics.clear_recording()
        scene:draw(1024, 720)

        assert.is_truthy(find_text(j, "No-win streak: 2 / 3"))
        assert.is_truthy(find_text(j, "No-win streak: 0 / 3"))
    end)

    it("renders the barrel-fall counter when the toggle is on", function()
        local cfg = build_config({
            barrel = { fall_count_resets_to_zero = "on" },
        })
        local s = session_at_tricks(cfg, generic_layout(), {
            dealer = 1,
            declarer = 2,
            bid = 100,
            barrel_fall_counts = { 1, 0, 2 },
        })
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        j._mock.graphics.clear_recording()
        scene:draw(1024, 720)

        assert.is_truthy(find_text(j, "Barrel falls: 1 / 3"))
        assert.is_truthy(find_text(j, "Barrel falls: 2 / 3"))
    end)

    it("hides both counters under canonical_russian defaults", function()
        local cfg = rule_config.canonical_russian
        local s = session_at_tricks(cfg, generic_layout(), {
            dealer = 1,
            declarer = 2,
            bid = 100,
        })
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        j._mock.graphics.clear_recording()
        scene:draw(1024, 720)

        assert.is_nil(find_text(j, "No-win streak"))
        assert.is_nil(find_text(j, "Barrel falls"))
    end)
end)
