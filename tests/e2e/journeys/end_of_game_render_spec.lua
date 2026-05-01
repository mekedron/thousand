-- End-to-end journey for the end-of-game render. The deal-scoring task
-- later in Phase 2 wires the table → end-of-game transition through
-- gameplay; today the journey constructs the scene under the live
-- love-mock harness with a finished session and asserts the winner banner
-- and final scores reach the screen.
--
-- We don't reach into main.lua's local manager — main.lua is a layer-4
-- entry point, and "give me the manager handle" would only exist for the
-- benefit of this test. Constructing a fresh scene_manager + scene under
-- the same love-mock exercises the same rendering surface that gameplay
-- will reach when the auto-transition lands.

local journey = require("tests.e2e.support.journey")

describe("e2e: end-of-game render", function()
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

    it("shows the winner banner and three final scores under the live love-mock", function()
        local scene_manager = require("ui.scene_manager")
        local end_of_game_scene = require("ui.scenes.end_of_game")
        local Session = require("app.session")
        local rule_config = require("core.rule_config")

        local session = Session.from_state({
            config = rule_config.canonical_russian,
            dealer = 1,
            running_totals = { 1010, 720, 540 },
            winner = 1,
        })

        local manager = scene_manager.new()
        manager:set_session(session)
        manager:register("end_of_game", end_of_game_scene.new(manager))
        manager:switch_to("end_of_game")

        _G.love.graphics.clear_recording()
        manager:draw(1024, 720)

        local t = j._i18n.t

        assert.is_not_nil(
            j._mock.graphics.find_text(t("scene.end_of_game.winner", { n = 1 })),
            "winner banner"
        )
        assert.is_not_nil(
            j._mock.graphics.find_text(t("scene.end_of_game.scores_title")),
            "scores title"
        )
        assert.is_not_nil(j._mock.graphics.find_text("1010"), "winner score")
        assert.is_not_nil(j._mock.graphics.find_text("720"), "second score")
        assert.is_not_nil(j._mock.graphics.find_text("540"), "third score")
        assert.is_not_nil(
            j._mock.graphics.find_text(t("scene.end_of_game.back_to_menu")),
            "back-to-menu button"
        )
    end)
end)
