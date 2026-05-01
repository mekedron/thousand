-- Unit coverage for the end-of-game scene. Builds a stub manager + finished
-- session and asserts the winner banner and the three final-score numbers
-- are rendered.

local love_mock = require("tests.e2e.support.love_mock")

local function reset_modules()
    local to_reset = {
        "ui.scenes.end_of_game",
        "ui.button",
        "app.i18n",
        "app.session",
        "app.table_view_model",
    }
    for _, mod in ipairs(to_reset) do
        package.loaded[mod] = nil
    end
end

local function fake_manager(session)
    return {
        switch_to = function() end,
        session = function()
            return session
        end,
        clear_session = function() end,
    }
end

local function find_text(mock, needle)
    for _, op in ipairs(mock.graphics.recording()) do
        if op.op == "text" and op.text:find(needle, 1, true) then
            return op
        end
    end
    return nil
end

describe("ui.scenes.end_of_game", function()
    local mock

    before_each(function()
        reset_modules()
        mock = love_mock.new({ width = 1024, height = 720 })
        mock:install()
        local i18n = require("app.i18n")
        i18n._reset()
        i18n._set_logger(function() end)
        i18n.set_locale("en")
    end)

    after_each(function()
        if mock then
            mock:restore()
        end
        reset_modules()
    end)

    it("renders the winner banner and final scores from a finished session", function()
        local Session = require("app.session")
        local rule_config = require("core.rule_config")
        local session = Session.from_state({
            config = rule_config.canonical_russian,
            dealer = 2,
            running_totals = { 1010, 720, 540 },
            winner = 1,
        })
        local end_of_game_scene = require("ui.scenes.end_of_game")
        local scene = end_of_game_scene.new(fake_manager(session))
        scene:enter(nil, nil)
        scene:draw(1024, 720)

        local i18n = require("app.i18n")
        local t = i18n.t

        assert.is_not_nil(find_text(mock, t("scene.end_of_game.winner", { n = 1 })))
        assert.is_not_nil(find_text(mock, t("scene.end_of_game.scores_title")))
        assert.is_not_nil(find_text(mock, "1010"), "winner score")
        assert.is_not_nil(find_text(mock, "720"), "second score")
        assert.is_not_nil(find_text(mock, "540"), "third score")
        assert.is_not_nil(find_text(mock, t("scene.end_of_game.back_to_menu")))
    end)

    it("accepts a view-model passed via params", function()
        local end_of_game_scene = require("ui.scenes.end_of_game")
        local scene = end_of_game_scene.new(fake_manager(nil))
        scene:enter(nil, {
            view_model = {
                phase = "done",
                turn_player = nil,
                dealer = 1,
                player_count = 3,
                winner = 2,
                final_scores = { 540, 1020, 720 },
                scoreboard = {
                    {
                        player = 1,
                        total = 540,
                        barrel = { on_barrel = false },
                        is_winner = false,
                    },
                    {
                        player = 2,
                        total = 1020,
                        barrel = { on_barrel = false },
                        is_winner = true,
                    },
                    {
                        player = 3,
                        total = 720,
                        barrel = { on_barrel = false },
                        is_winner = false,
                    },
                },
                hands = {},
                talon = { face_down = true, count = 0, cards = {} },
            },
        })
        scene:draw(1024, 720)

        local i18n = require("app.i18n")
        local t = i18n.t

        assert.is_not_nil(find_text(mock, t("scene.end_of_game.winner", { n = 2 })))
        assert.is_not_nil(find_text(mock, "1020"))
    end)

    it("falls back to the placeholder when no session is available", function()
        local end_of_game_scene = require("ui.scenes.end_of_game")
        local scene = end_of_game_scene.new(fake_manager(nil))
        scene:enter(nil, nil)
        scene:draw(1024, 720)

        local i18n = require("app.i18n")
        local t = i18n.t

        assert.is_not_nil(find_text(mock, t("scene.end_of_game.title")))
        assert.is_not_nil(find_text(mock, t("scene.end_of_game.placeholder")))
    end)
end)
