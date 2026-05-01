-- Unit coverage for the Template Picker scene. Drives in-memory storage
-- hooks on app.settings and app.templates so persistence and active-id
-- writes don't depend on Love2D's filesystem.

local love_mock = require("tests.e2e.support.love_mock")

local function reset_modules()
    local mods = {
        "ui.scenes.template_picker",
        "ui.scenes.template_editor",
        "ui.button",
        "ui.focus_group",
        "app.i18n",
        "app.settings",
        "app.templates",
        "app.json",
        "app.auto_save",
        "core.templates",
        "core.template_diff",
        "core.rule_config",
    }
    for _, m in ipairs(mods) do
        package.loaded[m] = nil
    end
end

local function recording_manager(opts)
    opts = opts or {}
    local switches = {}
    local active = opts.active or false
    local mgr = {
        switch_to = function(_self, id, params)
            switches[#switches + 1] = { id = id, params = params }
        end,
        session = function()
            return active and {} or nil
        end,
        is_game_active = function()
            return active
        end,
        clear_session = function()
            active = false
        end,
    }
    return mgr, function()
        return switches
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
    return r, w, store
end

local function find_text(mock, needle)
    for _, op in ipairs(mock.graphics.recording()) do
        if op.op == "text" and op.text:find(needle, 1, true) then
            return op
        end
    end
    return nil
end

describe("ui.scenes.template_picker", function()
    local mock, scene, settings, templates, manager, last_switches, t

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
        local now = 1000
        templates._set_clock(function()
            return now
        end)
        local n = 0
        templates._set_rng(function()
            n = n + 1
            return n
        end)

        manager, last_switches = recording_manager()
        local picker_scene = require("ui.scenes.template_picker")
        scene = picker_scene.new(manager)
    end)

    after_each(function()
        if mock then
            mock:restore()
        end
        reset_modules()
    end)

    it("renders title and built-ins above customs", function()
        scene:enter(nil, nil)
        scene:draw(1280, 800)
        assert.is_not_nil(find_text(mock, t("scene.template_picker.title")))
        assert.is_not_nil(find_text(mock, t("scene.template_picker.builtins_header")))
        assert.is_not_nil(find_text(mock, t("scene.template_picker.customs_header")))
        assert.is_not_nil(find_text(mock, t("templates.builtin.russian")))
        assert.is_not_nil(find_text(mock, t("templates.builtin.polish")))
    end)

    it("shows the empty-state copy when no custom templates exist", function()
        scene:enter(nil, nil)
        scene:draw(1280, 800)
        assert.is_not_nil(find_text(mock, t("scene.template_picker.empty_customs")))
    end)

    it("Use on a built-in persists the active id and routes to the menu", function()
        scene:enter(nil, nil)
        scene:draw(1280, 800)
        -- Find the Use button for Polish.
        local target
        for _, btn in ipairs(scene._row_buttons) do
            if btn.id == "use_polish" then
                target = btn
                break
            end
        end
        assert.is_not_nil(target, "use_polish button present")
        scene:mousepressed(target.x + 5, target.y + 5, 1)
        scene:mousereleased(target.x + 5, target.y + 5, 1)
        assert.are.equal("polish", templates.get_active_id())
        local switches = last_switches()
        assert.are.equal("menu", switches[#switches].id)
    end)

    it("Edit on a built-in routes to the editor with the builtin_id", function()
        scene:enter(nil, nil)
        scene:draw(1280, 800)
        local target
        for _, btn in ipairs(scene._row_buttons) do
            if btn.id == "edit_russian" then
                target = btn
                break
            end
        end
        assert.is_not_nil(target)
        scene:mousepressed(target.x + 5, target.y + 5, 1)
        scene:mousereleased(target.x + 5, target.y + 5, 1)
        local switches = last_switches()
        local last = switches[#switches]
        assert.are.equal("template_editor", last.id)
        assert.are.equal("russian", last.params.builtin_id)
    end)

    it("Clone on a built-in creates a custom template and opens the editor", function()
        scene:enter(nil, nil)
        scene:draw(1280, 800)
        local target
        for _, btn in ipairs(scene._row_buttons) do
            if btn.id == "clone_russian" then
                target = btn
                break
            end
        end
        assert.is_not_nil(target)
        scene:mousepressed(target.x + 5, target.y + 5, 1)
        scene:mousereleased(target.x + 5, target.y + 5, 1)
        local listing = templates.list()
        assert.are.equal(1, #listing.templates)
        local switches = last_switches()
        local last = switches[#switches]
        assert.are.equal("template_editor", last.id)
        assert.are.equal(listing.templates[1].id, last.params.template_id)
    end)

    it("renders modified count for a custom template that diverges from its parent", function()
        local created = templates.create({ fromBuiltin = "russian", name = "Tweaked" }).template
        templates.update(
            created.id,
            (function()
                local app_json = require("app.json")
                local rule_config = require("core.rule_config")
                local blob = app_json.decode(rule_config.to_json(rule_config.builtins.russian))
                blob.bidding.opening_min = 110
                return blob
            end)()
        )
        scene:enter(nil, nil)
        scene:draw(1280, 800)
        assert.is_not_nil(find_text(mock, t("scene.template_picker.modified_count", { n = 1 })))
    end)

    describe("mid-game switch", function()
        before_each(function()
            manager, last_switches = recording_manager({ active = true })
            local picker_scene = require("ui.scenes.template_picker")
            scene = picker_scene.new(manager)
            scene:enter(nil, nil)
            scene:draw(1280, 800)
        end)

        it("opens the confirmation modal instead of switching immediately", function()
            local target
            for _, btn in ipairs(scene._row_buttons) do
                if btn.id == "use_polish" then
                    target = btn
                    break
                end
            end
            scene:mousepressed(target.x + 5, target.y + 5, 1)
            scene:mousereleased(target.x + 5, target.y + 5, 1)
            assert.are.equal("confirm_switch", scene._modal)
            scene:draw(1280, 800)
            local prompt = t("scene.template_picker.confirm_switch_mid_game.prompt")
            assert.is_not_nil(find_text(mock, prompt))
            -- Active id should not yet be set.
            assert.are.equal("russian", templates.get_active_id())
        end)

        it("Yes on the modal clears the session and persists the active id", function()
            local target
            for _, btn in ipairs(scene._row_buttons) do
                if btn.id == "use_polish" then
                    target = btn
                    break
                end
            end
            scene:mousepressed(target.x + 5, target.y + 5, 1)
            scene:mousereleased(target.x + 5, target.y + 5, 1)
            scene:draw(1280, 800)
            scene:mousepressed(scene._modal_yes.x + 5, scene._modal_yes.y + 5, 1)
            scene:mousereleased(scene._modal_yes.x + 5, scene._modal_yes.y + 5, 1)
            assert.are.equal("polish", templates.get_active_id())
            local switches = last_switches()
            assert.are.equal("menu", switches[#switches].id)
        end)

        it("No on the modal closes it without changing state", function()
            local target
            for _, btn in ipairs(scene._row_buttons) do
                if btn.id == "use_polish" then
                    target = btn
                    break
                end
            end
            scene:mousepressed(target.x + 5, target.y + 5, 1)
            scene:mousereleased(target.x + 5, target.y + 5, 1)
            scene:draw(1280, 800)
            scene:mousepressed(scene._modal_no.x + 5, scene._modal_no.y + 5, 1)
            scene:mousereleased(scene._modal_no.x + 5, scene._modal_no.y + 5, 1)
            assert.are.equal("russian", templates.get_active_id())
            assert.is_nil(scene._modal)
        end)
    end)

    it("Delete on a custom template prompts and removes after confirmation", function()
        local created = templates.create({ fromBuiltin = "russian", name = "Doomed" }).template
        scene:enter(nil, nil)
        scene:draw(1280, 800)
        local target
        for _, btn in ipairs(scene._row_buttons) do
            if btn.id == "delete_" .. created.id then
                target = btn
                break
            end
        end
        assert.is_not_nil(target)
        scene:mousepressed(target.x + 5, target.y + 5, 1)
        scene:mousereleased(target.x + 5, target.y + 5, 1)
        assert.are.equal("confirm_delete", scene._modal)
        scene:draw(1280, 800)
        scene:mousepressed(scene._modal_yes.x + 5, scene._modal_yes.y + 5, 1)
        scene:mousereleased(scene._modal_yes.x + 5, scene._modal_yes.y + 5, 1)
        assert.is_nil(templates.get(created.id))
    end)
end)
