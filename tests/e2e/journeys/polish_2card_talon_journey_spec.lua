-- End-to-end journey for the Polish 2-card pass_without_taking talon.
-- Builds a session at talon-revealed under the `polish` builtin,
-- drives the table scene under the journey's mocked Love, and asserts
-- the localised "Pass talon" affordance renders (in place of the
-- canonical "Take talon") and the Russian raise affordance does not
-- appear at all (Polish skips awaiting_raise).

local journey = require("tests.e2e.support.journey")

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

local function dismiss_curtain_state(scene)
    scene._curtain = nil
    if scene._view_model and scene._view_model.turn_player then
        scene._last_revealed_seat = scene._view_model.turn_player
    end
end

-- Polish 7/7/7 hands + 2-card talon + 1 leftover. The hands are
-- chosen so the standard "forehand opens at 100, others pass" auction
-- finalises with seat 2 as declarer, mirroring the canonical-Russian
-- journey's defaults.
local function polish_layout()
    local card = require("core.card")
    local seat1 = {
        card.new("spades", "9"),
        card.new("spades", "J"),
        card.new("spades", "Q"),
        card.new("spades", "K"),
        card.new("spades", "10"),
        card.new("spades", "A"),
        card.new("clubs", "9"),
    }
    local seat2 = {
        card.new("clubs", "J"),
        card.new("clubs", "Q"),
        card.new("clubs", "K"),
        card.new("clubs", "10"),
        card.new("clubs", "A"),
        card.new("diamonds", "9"),
        card.new("diamonds", "J"),
    }
    local seat3 = {
        card.new("diamonds", "Q"),
        card.new("diamonds", "K"),
        card.new("diamonds", "10"),
        card.new("diamonds", "A"),
        card.new("hearts", "9"),
        card.new("hearts", "J"),
        card.new("hearts", "Q"),
    }
    local talon = { card.new("hearts", "K"), card.new("hearts", "10") }
    local leftover_for_declarer = { card.new("hearts", "A") }
    return { seat1, seat2, seat3 }, talon, leftover_for_declarer
end

local function build_polish_session_at_talon()
    local Session = require("app.session")
    local rule_config = require("core.rule_config")
    local auction_module = require("core.auction")
    local marriages_module = require("core.marriages")
    local cfg = rule_config.builtins.polish
    local hands, talon, leftover_for_declarer = polish_layout()
    local s = Session.from_state({
        config = cfg,
        seed = 1,
        dealer = 1,
        hands = hands,
        talon_cards = talon,
        auction = auction_module.new(cfg, 1).auction,
        marriages = marriages_module.new(cfg).marriages,
        running_totals = { 0, 0, 0 },
        deal_index = 1,
    })
    s._leftover_for_declarer = leftover_for_declarer
    -- Drive the auction: forehand (seat 2) bids 100; the other two pass.
    assert(s:bid(2, 100).ok)
    assert(s:pass(3).ok)
    assert(s:pass(1).ok)
    return s
end

describe("e2e: polish 2-card talon (pass_without_taking)", function()
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

    it("renders the 'Pass talon' button at revealed status", function()
        local s = build_polish_session_at_talon()
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        _G.love.graphics.clear_recording()
        scene:draw(1024, 720)

        local pass_label = j:find_localised("scene.table.talon.pass_polish_button")
        assert.is_not_nil(find_text(j, pass_label), "Pass talon button should be visible")
        local take_label = j:find_localised("scene.table.talon.take_button")
        assert.is_nil(find_text(j, take_label), "Take button must not render under Polish")
    end)

    it("clicking Pass talon distributes both cards and lands on tricks at 8/8/8", function()
        local s = build_polish_session_at_talon()
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        scene:_do_pass_polish_talon()

        assert.are.equal("tricks", s:current_phase(), "tricks should start after both passes")
        local hands = s:hands()
        assert.are.equal(8, #hands[1])
        assert.are.equal(8, #hands[2])
        assert.are.equal(8, #hands[3])
    end)
end)
