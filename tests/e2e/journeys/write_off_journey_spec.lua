-- Phase 3.7 write-off / сдача e2e journey. Drives the table scene
-- through a session whose tricks phase opens under
-- `bidding.write_off = "on"` and asserts:
--
--   * the "Write off" panel button is visible to the declarer while
--     the deal still has more than one trick remaining;
--   * the per-seat "Write-offs: 1 / 3" scoreboard line renders when
--     `penalties.write_off_streak = "any_three"` is on;
--   * pressing the button advances the session into deal_done with
--     `reason = "write_off"` and the localised banner appears.
--
-- Engine math is pinned in tests/spec/app/session_write_off_spec; this
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

local function find_panel_button(scene, id)
    for _, b in ipairs(scene._panel_buttons) do
        if b.id == id then
            return b
        end
    end
    return nil
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

-- 24-card deal. Seat 2 holds the winners; the actual sequence does
-- not matter for write-off journeys because the deal closes the
-- moment the button is pressed.
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
        write_off_counts = opts.write_off_counts,
    })
end

describe("write-off journey", function()
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

    it("renders the Write off panel button when the toggle is on", function()
        local cfg = build_config({ bidding = { write_off = "on" } })
        local s = session_at_tricks(cfg, generic_layout(), {
            dealer = 1,
            declarer = 2,
            bid = 100,
        })
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        j._mock.graphics.clear_recording()
        scene:draw(1024, 720)

        local btn = find_panel_button(scene, "tricks_write_off")
        assert.is_not_nil(btn, "Write-off button should be present in the tricks panel")
        assert.is_true(btn.enabled)
        assert.is_truthy(find_text(j, "Write off"))
    end)

    it("hides the Write off button when the toggle is off", function()
        -- Default canonical_russian has bidding.write_off = "off".
        local cfg = rule_config.canonical_russian
        local s = session_at_tricks(cfg, generic_layout(), {
            dealer = 1,
            declarer = 2,
            bid = 100,
        })
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        local btn = find_panel_button(scene, "tricks_write_off")
        assert.is_nil(btn, "Write-off button should be hidden under the default toggle")
    end)

    it("renders the per-seat write-off counter when streak is any_three", function()
        local cfg = build_config({
            bidding = { write_off = "on" },
            penalties = {
                write_off_streak = "any_three",
                write_off_streak_threshold = 3,
            },
        })
        local s = session_at_tricks(cfg, generic_layout(), {
            dealer = 1,
            declarer = 2,
            bid = 100,
            write_off_counts = { 0, 1, 0 },
        })
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        j._mock.graphics.clear_recording()
        scene:draw(1024, 720)

        -- The view-model surfaces the per-seat counter only when the
        -- streak rule is on; the renderer prints it under each seat
        -- row using the "Write-offs: %{count} / %{threshold}" format.
        assert.is_truthy(find_text(j, "Write-offs: 1 / 3"))
    end)

    it("closes the deal with write_off reason when the button is pressed", function()
        local cfg = build_config({ bidding = { write_off = "on" } })
        local s = session_at_tricks(cfg, generic_layout(), {
            dealer = 1,
            declarer = 2,
            bid = 100,
        })
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)

        local btn = find_panel_button(scene, "tricks_write_off")
        assert.is_not_nil(btn)
        btn:activate()

        assert.are.equal("deal_done", s:current_phase())
        local dd = s:deal_done()
        assert.are.equal("write_off", dd.reason)
        assert.are.equal(2, dd.declarer)

        -- After the action the scene re-renders with the deal-done
        -- banner; the Write-off button is no longer in the panel.
        scene:draw(1024, 720)
        j._mock.graphics.clear_recording()
        scene:draw(1024, 720)
        assert.is_nil(find_panel_button(scene, "tricks_write_off"))
        assert.is_truthy(find_text(j, "Write-off — declarer conceded mid-deal"))
    end)
end)
