-- Unit coverage for the Settings scene. Drives the in-memory storage
-- hook on app.settings so the scene's toggle reads/writes don't depend
-- on Love2D's filesystem.

local love_mock = require("tests.e2e.support.love_mock")

local function reset_modules()
    local to_reset = {
        "ui.scenes.settings",
        "ui.button",
        "ui.focus_group",
        "app.i18n",
        "app.settings",
        "app.json",
    }
    for _, mod in ipairs(to_reset) do
        package.loaded[mod] = nil
    end
end

local function recording_manager()
    local switched_to
    local mgr = {
        switch_to = function(_self, id)
            switched_to = id
        end,
        session = function()
            return nil
        end,
        is_game_active = function()
            return false
        end,
    }
    return mgr, function()
        return switched_to
    end
end

local function in_memory_storage()
    local store = {}
    return function(path)
        return store[path]
    end,
        function(path, content)
            store[path] = content
            return true
        end,
        store
end

local function find_text(mock, needle)
    for _, op in ipairs(mock.graphics.recording()) do
        if op.op == "text" and op.text:find(needle, 1, true) then
            return op
        end
    end
    return nil
end

describe("ui.scenes.settings", function()
    local mock, scene, settings, manager, last_switch, t

    before_each(function()
        reset_modules()
        mock = love_mock.new({ width = 1024, height = 720 })
        mock:install()
        local i18n = require("app.i18n")
        i18n._reset()
        i18n._set_logger(function() end)
        i18n.set_locale("en")
        t = i18n.t

        settings = require("app.settings")
        local read_fn, write_fn = in_memory_storage()
        settings._set_storage(read_fn, write_fn)

        manager, last_switch = recording_manager()
        local settings_scene = require("ui.scenes.settings")
        scene = settings_scene.new(manager)
        scene:enter(nil, nil)
    end)

    after_each(function()
        if mock then
            mock:restore()
        end
        reset_modules()
    end)

    it("renders the title, toggle label, description and Back", function()
        scene:draw(1024, 720)
        assert.is_not_nil(find_text(mock, t("scene.settings.title")), "title")
        assert.is_not_nil(find_text(mock, t("scene.settings.hot_seat_privacy.label")), "row label")
        assert.is_not_nil(
            find_text(mock, t("scene.settings.hot_seat_privacy.description")),
            "row description"
        )
        assert.is_not_nil(find_text(mock, t("scene.settings.back_to_menu")), "Back button")
    end)

    it("toggle starts at On for the default settings", function()
        scene:draw(1024, 720)
        assert.is_not_nil(find_text(mock, t("scene.settings.toggle.on")))
        assert.is_nil(find_text(mock, t("scene.settings.toggle.off")))
    end)

    it("clicking the toggle flips settings.hot_seat_privacy and the label", function()
        scene:draw(1024, 720)
        local btn = scene._toggle_button
        local cx = btn.x + btn.w * 0.5
        local cy = btn.y + btn.h * 0.5
        scene:mousepressed(cx, cy, 1)
        scene:mousereleased(cx, cy, 1)
        assert.are.equal(false, settings.get("hot_seat_privacy"))

        mock.graphics.clear_recording()
        scene:draw(1024, 720)
        assert.is_not_nil(find_text(mock, t("scene.settings.toggle.off")))
        assert.is_nil(find_text(mock, t("scene.settings.toggle.on")))
    end)

    it("clicking Back returns to the menu", function()
        scene:draw(1024, 720)
        local btn = scene._back_button
        local cx = btn.x + btn.w * 0.5
        local cy = btn.y + btn.h * 0.5
        scene:mousepressed(cx, cy, 1)
        scene:mousereleased(cx, cy, 1)
        assert.are.equal("menu", last_switch())
    end)

    it("Esc returns to the menu", function()
        scene:keypressed("escape")
        assert.are.equal("menu", last_switch())
    end)

    it("Tab + Enter activates the toggle", function()
        scene:draw(1024, 720)
        scene:keypressed("tab")
        scene:keypressed("return")
        assert.are.equal(false, settings.get("hot_seat_privacy"))
    end)

    it("Tab twice + Enter activates Back", function()
        scene:draw(1024, 720)
        scene:keypressed("tab")
        scene:keypressed("tab")
        scene:keypressed("return")
        assert.are.equal("menu", last_switch())
    end)

    it("re-entering reflects the current setting value", function()
        settings.set("hot_seat_privacy", false)
        scene:enter(nil, nil)
        scene:draw(1024, 720)
        assert.is_not_nil(find_text(mock, t("scene.settings.toggle.off")))
    end)
end)
