-- End-to-end journey for the 2-player Variant A stock_draw distribution.
-- Builds a session under the `two_player_a` builtin (which now pins
-- `talon.distribution = "stock_draw"`), drives the head-to-head auction
-- through to tricks, and asserts the table scene renders the stock
-- block (label + count + trump indicator) and suppresses every
-- traditional-talon affordance — there is no Take, Pass-Polish, or
-- raise button in this layout.

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

-- Build a Variant A session and drive the head-to-head auction to its
-- end. With `dealer = 1`, seat 2 is forehand: forehand bids the minimum
-- and the dealer passes, so seat 2 declares at 100. The session
-- transitions straight to tricks because `talon.size = 0` skips the
-- talon phase; the stock and trump indicator are seeded into the
-- tricks layer at the same time.
local function build_two_player_a_session_at_tricks()
    local Session = require("app.session")
    local rule_config = require("core.rule_config")
    local s = Session.new({
        seed = 7,
        dealer = 1,
        config = rule_config.builtins.two_player_a,
    })
    assert(s:bid(2, 100).ok)
    assert(s:pass(1).ok)
    assert.are.equal("tricks", s:current_phase())
    return s
end

describe("e2e: 2-player Variant A stock_draw distribution", function()
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

    it("renders the stock block with trump indicator and 6-card count", function()
        local s = build_two_player_a_session_at_tricks()
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        _G.love.graphics.clear_recording()
        scene:draw(1024, 720)

        local stock_label = j:find_localised("scene.table.stock.label")
        assert.is_not_nil(find_text(j, stock_label), "Stock label should be visible")

        local indicator_label = j:find_localised("scene.table.stock.trump_indicator")
        assert.is_not_nil(
            find_text(j, indicator_label),
            "Trump-indicator caption should be visible"
        )

        local count_text = j:find_localised("scene.table.stock.count", { n = 6 })
        assert.is_not_nil(
            find_text(j, count_text),
            "Stock count should read '6 cards left' immediately after auction"
        )

        -- The talon-flow affordances must not render under Variant A.
        local take_label = j:find_localised("scene.table.talon.take_button")
        assert.is_nil(find_text(j, take_label), "Take talon must not render")
        local pass_polish_label = j:find_localised("scene.table.talon.pass_polish_button")
        assert.is_nil(find_text(j, pass_polish_label), "Polish 'Pass talon' must not render")
        local talon_label = j:find_localised("scene.table.talon.label")
        assert.is_nil(find_text(j, talon_label), "Generic 'Talon' label must not render")
    end)

    it("decrements the stock by 2 after one trick", function()
        local s = build_two_player_a_session_at_tricks()
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        -- Resolve one trick by playing the legal-cards head of each
        -- seat in turn. Variant A is in `phase = draw` here, so legality
        -- is the relaxed pre-stock-exhausted ruleset.
        local turn = s:current_turn()
        local choice = s:legal_cards(turn)[1]
        assert(s:play(turn, choice).ok)
        turn = s:current_turn()
        choice = s:legal_cards(turn)[1]
        assert(s:play(turn, choice).ok)

        _G.love.graphics.clear_recording()
        scene:draw(1024, 720)

        -- Winner draws first, loser draws second — stock drops from 6
        -- to 4. The trump indicator is still the bottom card and stays
        -- visible until the very last draw.
        local count_text = j:find_localised("scene.table.stock.count", { n = 4 })
        assert.is_not_nil(
            find_text(j, count_text),
            "Stock count should read '4 cards left' after one trick"
        )
    end)
end)
