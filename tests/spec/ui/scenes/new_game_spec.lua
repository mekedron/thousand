-- Unit coverage for the New Game picker scene. Drives in-memory storage
-- hooks on app.settings and app.templates so the scene can swap which
-- template is active and check that the row count follows
-- `players.count`.

local love_mock = require("tests.e2e.support.love_mock")

local function reset_modules()
    local mods = {
        "ui.scenes.new_game",
        "ui.button",
        "ui.toggle",
        "ui.focus_group",
        "app.i18n",
        "app.settings",
        "app.templates",
        "app.json",
        "app.auto_save",
        "app.session",
        "core.rule_config",
        "core.templates",
        "core.auto_save",
    }
    for _, m in ipairs(mods) do
        package.loaded[m] = nil
    end
end

local function recording_manager()
    local switches = {}
    local last_session = nil
    local mgr = {
        switch_to = function(_self, id, params)
            switches[#switches + 1] = { id = id, params = params }
        end,
        set_session = function(_self, session)
            last_session = session
        end,
        session = function()
            return last_session
        end,
        is_game_active = function()
            return last_session ~= nil
        end,
        clear_session = function()
            last_session = nil
        end,
    }
    return mgr,
        function()
            return switches
        end,
        function()
            return last_session
        end
end

local function in_memory_storage()
    local store = {}
    local r = function(p)
        return store[p]
    end
    local w = function(p, c)
        store[p] = c
        return true
    end
    local rm = function(p)
        store[p] = nil
        return true
    end
    return r, w, rm, store
end

local function find_text(mock, needle)
    for _, op in ipairs(mock.graphics.recording()) do
        if op.op == "text" and op.text:find(needle, 1, true) then
            return op
        end
    end
    return nil
end

local function press(scene, btn)
    scene:mousepressed(btn.x + 5, btn.y + 5, 1)
    scene:mousereleased(btn.x + 5, btn.y + 5, 1)
end

local function press_segment(scene, toggle, segment_index)
    local rects = toggle:segment_rects()
    local r = rects[segment_index]
    scene:mousepressed(r.x + 5, r.y + 5, 1)
    scene:mousereleased(r.x + 5, r.y + 5, 1)
end

describe("ui.scenes.new_game", function()
    local mock, scene, settings, templates, manager, last_switches, last_session, t

    before_each(function()
        reset_modules()
        mock = love_mock.new({ width = 1280, height = 800 })
        mock:install()
        local i18n = require("app.i18n")
        i18n._reset()
        i18n._set_logger(function() end)
        i18n.set_locale("en")
        t = i18n.t

        settings = require("app.settings")
        local sread, swrite = in_memory_storage()
        settings._set_storage(sread, swrite)

        templates = require("app.templates")
        local tread, twrite = in_memory_storage()
        templates._set_storage(tread, twrite)
        templates._set_clock(function()
            return 1000
        end)
        local n = 0
        templates._set_rng(function()
            n = n + 1
            return n
        end)

        local auto_save = require("app.auto_save")
        local _, _, _ = in_memory_storage()
        auto_save._set_storage(function()
            return nil
        end, function()
            return true
        end, function()
            return true
        end)

        manager, last_switches, last_session = recording_manager()
        local new_game_scene = require("ui.scenes.new_game")
        scene = new_game_scene.new(manager)
    end)

    after_each(function()
        if mock then
            mock:restore()
        end
        reset_modules()
    end)

    describe("default 3-player canonical Russian", function()
        before_each(function()
            scene:enter(nil, nil)
            scene:draw(1280, 800)
        end)

        it("renders the title", function()
            assert.is_not_nil(find_text(mock, t("scene.new_game.title")))
        end)

        it("shows the active template label", function()
            assert.is_not_nil(find_text(mock, t("templates.builtin.russian")))
        end)

        it("populates one row per seat", function()
            assert.are.equal(3, #scene._seat_toggles)
        end)

        it("defaults seat 1 to human and the rest to bot", function()
            assert.are.equal("human", scene._seat_toggles[1].current)
            assert.are.equal("bot", scene._seat_toggles[2].current)
            assert.are.equal("bot", scene._seat_toggles[3].current)
        end)

        it("toggling seat 2 to human flips the binding", function()
            press_segment(scene, scene._seat_toggles[2], 1) -- 1 = human segment
            assert.are.equal("human", scene._seat_toggles[2].current)
        end)

        it(
            "Start dispatches set_session with the chosen seat_kinds and switches to table",
            function()
                press_segment(scene, scene._seat_toggles[2], 1)
                press(scene, scene._start_button)
                local session = last_session()
                assert.is_not_nil(session)
                assert.are.same({ "human", "human", "bot" }, session:seat_kinds())
                local switches = last_switches()
                local last = switches[#switches]
                assert.are.equal("table", last.id)
                assert.are.same({ "human", "human", "bot" }, last.params.seat_kinds)
            end
        )

        it("Back routes to menu without starting a game", function()
            press(scene, scene._back_button)
            assert.is_nil(last_session())
            local switches = last_switches()
            assert.are.equal("menu", switches[#switches].id)
        end)

        it("Esc routes to menu", function()
            scene:keypressed("escape")
            local switches = last_switches()
            assert.are.equal("menu", switches[#switches].id)
        end)

        it("permits Start with an all-bot composition", function()
            press_segment(scene, scene._seat_toggles[1], 2) -- 2 = bot segment
            assert.are.equal("bot", scene._seat_toggles[1].current)
            press(scene, scene._start_button)
            local session = last_session()
            assert.is_not_nil(session)
            assert.are.same({ "bot", "bot", "bot" }, session:seat_kinds())
        end)
    end)

    describe("alternate player counts", function()
        it("renders 2 rows under a 2-player template", function()
            templates.set_active_id("two_player_a")
            scene:enter(nil, nil)
            scene:draw(1280, 800)
            assert.are.equal(2, #scene._seat_toggles)
            assert.are.equal("human", scene._seat_toggles[1].current)
            assert.are.equal("bot", scene._seat_toggles[2].current)
        end)

        it("renders 4 rows under a 4-player template", function()
            templates.set_active_id("four_player_a")
            scene:enter(nil, nil)
            scene:draw(1280, 800)
            assert.are.equal(4, #scene._seat_toggles)
            assert.are.equal("human", scene._seat_toggles[1].current)
            for i = 2, 4 do
                assert.are.equal("bot", scene._seat_toggles[i].current)
            end
        end)
    end)

    describe("focus and keyboard nav", function()
        before_each(function()
            scene:enter(nil, nil)
            scene:draw(1280, 800)
        end)

        it("Tab seeds focus on the first widget then advances", function()
            scene:keypressed("tab")
            assert.is_true(scene._seat_toggles[1].focused)
            scene:keypressed("tab")
            assert.is_true(scene._seat_toggles[2].focused)
        end)

        it("Enter activates the focused start button to launch the game", function()
            for _ = 1, 4 do
                scene:keypressed("tab") -- 3 toggles + 1 to land on Start
            end
            assert.is_true(scene._start_button.focused)
            scene:keypressed("return")
            local session = last_session()
            assert.is_not_nil(session)
        end)
    end)
end)
