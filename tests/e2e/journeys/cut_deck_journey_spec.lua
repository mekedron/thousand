-- End-to-end journey for the Phase 3.8 cut-deck ritual. Drives the
-- table scene under the journey's mocked Love so the localised "Cut
-- the deck" button and the "Bad cut N/3" indicator render. Three
-- scenarios:
--
--   * Good cut (good bottom): button present → press → phase clears
--     to auction.
--   * Bad cut (bad bottom): button press rotates the cutter ccw and
--     the indicator advances to "Bad cuts: 1 / 3".
--   * Threshold penalty (third bad cut): the dealer's running total
--     drops by 120 and the deal proceeds to auction.

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

local function find_panel_button(scene, id)
    for _, b in ipairs(scene._panel_buttons or {}) do
        if b.id == id then
            return b
        end
    end
    return nil
end

-- Build a config with the procedural cut ritual on and the
-- shuffle-time guard off — the only legal combination under the
-- cross-field invariant.
local function cut_config()
    local rule_config = require("core.rule_config")
    local json = require("app.json")
    local blob = json.decode(rule_config.to_json(rule_config.canonical_russian))
    blob.dealing.cut_deck_safety = "off"
    blob.dealing.cut_deck_nine_jack_penalty = "on"
    blob.dealing.four_nine_redeal = "off"
    blob.dealing.three_nine_redeal = "off"
    blob.dealing.four_jack_redeal = "off"
    return rule_config.new(blob)
end

local function session_in_cut(opts)
    local Session = require("app.session")
    local card = require("core.card")
    local cfg = cut_config()
    opts = opts or {}
    local pc = cfg.players.count
    local dealer = opts.dealer or 1
    local zeros = {}
    for i = 1, pc do
        zeros[i] = 0
    end
    return Session.from_state({
        config = cfg,
        seed = opts.seed or 1,
        dealer = dealer,
        deal_index = 1,
        running_totals = opts.running_totals or zeros,
        cut_phase = {
            active_cutter = opts.active_cutter or ((dealer - 2) % pc + 1),
            bad_cut_count = opts.bad_cut_count or 0,
            bottom_card = opts.bottom_card or card.new("hearts", "Q"),
        },
        cut_deck_log = opts.cut_deck_log or {},
    })
end

describe("e2e: cut-deck ritual", function()
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

    it("renders the localised Cut the deck button while the phase is open", function()
        local s = session_in_cut()
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        _G.love.graphics.clear_recording()
        scene:draw(1024, 720)

        local label = j:find_localised("scene.table.cut.cut_deck_button")
        assert.is_not_nil(find_text(j, label), "Cut the deck button label must render")
        local btn = find_panel_button(scene, "cut_deck")
        assert.is_not_nil(btn, "cut_deck panel button must be present")
    end)

    it("clears the cut phase and proceeds to auction on a good cut", function()
        local card = require("core.card")
        local s = session_in_cut({ bottom_card = card.new("clubs", "Q") })
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)
        scene:_do_cut_deck()
        scene:draw(1024, 720)

        assert.are.equal("auction", s:current_phase())
        assert.is_nil(s:cut_phase())
    end)

    it("rotates the cutter ccw and advances the indicator on a bad cut", function()
        local card = require("core.card")
        local s = session_in_cut({
            dealer = 1,
            active_cutter = 3,
            bad_cut_count = 0,
            bottom_card = card.new("hearts", "J"),
        })
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        scene:_do_cut_deck()
        scene:draw(1024, 720)

        assert.are.equal("cut", s:current_phase())
        assert.are.equal(2, s:active_cutter())
        assert.are.equal(1, s:bad_cut_count())

        _G.love.graphics.clear_recording()
        scene:draw(1024, 720)
        local label =
            j:find_localised("scene.table.cut.bad_cut_indicator", { count = 1, threshold = 3 })
        assert.is_not_nil(find_text(j, label), "Bad cut indicator must render after a bad cut")
    end)

    it("debits the dealer 120 on the third bad cut and clears the phase", function()
        local card = require("core.card")
        local s = session_in_cut({
            dealer = 1,
            active_cutter = 2,
            bad_cut_count = 2,
            running_totals = { 50, 100, 200 },
            bottom_card = card.new("diamonds", "J"),
        })
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        scene:_do_cut_deck()
        scene:draw(1024, 720)

        assert.are.equal("auction", s:current_phase())
        assert.is_nil(s:cut_phase())
        assert.are.equal(-70, s:running_totals()[1]) -- 50 - 120 = -70
        assert.are.equal(100, s:running_totals()[2])
        assert.are.equal(200, s:running_totals()[3])
        local log = s:cut_deck_log()
        assert.are.equal(1, #log)
        assert.are.equal("threshold_penalty", log[1].kind)
        assert.are.equal(120, log[1].amount)
    end)
end)
