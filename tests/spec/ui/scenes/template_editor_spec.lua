-- Unit coverage for the Template Editor scene. Drives in-memory storage
-- hooks on app.settings and app.templates so the scene's lifecycle and
-- persistence checks don't depend on Love2D's filesystem.

local love_mock = require("tests.e2e.support.love_mock")

local function reset_modules()
    local mods = {
        "ui.scenes.template_editor",
        "ui.scenes.template_picker",
        "ui.button",
        "ui.toggle",
        "ui.number_stepper",
        "ui.focus_group",
        "app.i18n",
        "app.settings",
        "app.templates",
        "app.json",
        "core.templates",
        "core.template_diff",
        "core.rule_config",
    }
    for _, m in ipairs(mods) do
        package.loaded[m] = nil
    end
end

local function recording_manager()
    local switches = {}
    local mgr = {
        switch_to = function(_self, id, params)
            switches[#switches + 1] = { id = id, params = params }
        end,
        session = function()
            return nil
        end,
        is_game_active = function()
            return false
        end,
        clear_session = function() end,
    }
    return mgr, function()
        return switches
    end
end

local function in_memory_storage()
    local store = {}
    local read_fn = function(p)
        return store[p]
    end
    local write_fn = function(p, c)
        store[p] = c
        return true
    end
    return read_fn, write_fn, store
end

local function find_text(mock, needle)
    for _, op in ipairs(mock.graphics.recording()) do
        if op.op == "text" and op.text:find(needle, 1, true) then
            return op
        end
    end
    return nil
end

describe("ui.scenes.template_editor", function()
    local mock, scene, settings, templates, manager, last_switches, t, custom

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

        local created = templates.create({ fromBuiltin = "russian", name = "My Custom" })
        custom = created.template

        manager, last_switches = recording_manager()
        local editor_scene = require("ui.scenes.template_editor")
        scene = editor_scene.new(manager)
    end)

    after_each(function()
        if mock then
            mock:restore()
        end
        reset_modules()
    end)

    describe("when entering with a custom template id", function()
        before_each(function()
            scene:enter(nil, { template_id = custom.id })
        end)

        it("renders the title with the template name", function()
            scene:draw(1024, 720)
            assert.is_not_nil(find_text(mock, t("scene.template_editor.title")), "title")
            assert.is_not_nil(find_text(mock, "My Custom"), "name")
        end)

        it("renders every section header in declared order", function()
            scene:draw(1024, 720)
            local sections = require("core.rule_config").sections()
            for _, s in ipairs(sections) do
                local key = "templates.section." .. s
                assert.is_not_nil(find_text(mock, t(key)), "section " .. s)
            end
        end)

        it("renders the parent built-in label", function()
            scene:draw(1024, 720)
            local parent_label = t("templates.builtin.russian")
            assert.is_not_nil(
                find_text(mock, t("scene.template_editor.parent_label", { name = parent_label }))
            )
        end)

        it("Save is enabled and Cancel returns to the picker", function()
            scene:draw(1024, 720)
            assert.is_true(scene._save_button.enabled)
            -- Click Cancel via direct button call.
            local b = scene._cancel_button
            scene:mousepressed(b.x + 5, b.y + 5, 1)
            scene:mousereleased(b.x + 5, b.y + 5, 1)
            local switches = last_switches()
            assert.are.equal("template_picker", switches[#switches].id)
        end)

        it("disables every deferred field's widget", function()
            scene:draw(1024, 720)
            -- Phase 3.6 closes every catalogued toggle, so the schema
            -- ships with no deferred fields right now. The contract is
            -- still that any deferred widget must be disabled — keep
            -- the loop so reintroducing a deferred toggle in a later
            -- phase exercises the assertion without a test rewrite.
            for _, entry in ipairs(scene._widgets) do
                if entry.descriptor.status == "deferred" and entry.widget then
                    assert.is_false(entry.widget.enabled, entry.section .. "." .. entry.field)
                end
            end
        end)

        it("renders 'Not yet available' badge only when a deferred field exists", function()
            scene:draw(1024, 720)
            local has_deferred = false
            for _, entry in ipairs(scene._widgets) do
                if entry.descriptor.status == "deferred" then
                    has_deferred = true
                    break
                end
            end
            local badge = find_text(mock, t("scene.template_editor.deferred_badge"))
            if has_deferred then
                assert.is_not_nil(badge)
            else
                assert.is_nil(badge)
            end
        end)

        it("changing a selectable numeric field marks the row modified", function()
            scene:draw(1024, 720)
            -- Find bidding.opening_min widget and bump it.
            local target
            for _, e in ipairs(scene._widgets) do
                if e.section == "bidding" and e.field == "opening_min" and e.widget then
                    target = e
                    break
                end
            end
            assert.is_not_nil(target, "opening_min widget present")
            target.widget:activate()
            scene:draw(1024, 720)
            assert.is_not_nil(find_text(mock, t("scene.template_editor.modified_badge")))
        end)

        it("invariant violation surfaces a banner and disables Save", function()
            scene:draw(1024, 720)
            -- Force opening_min above pre_talon_max.
            scene._working_blob.bidding.opening_min = 130
            scene._working_blob.bidding.pre_talon_max = 120
            scene:_recompute()
            scene:draw(1024, 720)
            assert.is_false(scene._save_button.enabled)
            assert.is_not_nil(find_text(mock, "Cannot save"))
        end)

        it("Save persists the working blob via app.templates.update", function()
            scene:draw(1024, 720)
            scene._working_blob.bidding.opening_min = 110
            scene:_recompute()
            scene:_save()
            local refreshed = templates.get(custom.id)
            assert.are.equal(110, refreshed.ruleConfig.bidding.opening_min)
        end)

        it("Reset to parent restores the parent's blob", function()
            scene:draw(1024, 720)
            scene._working_blob.bidding.opening_min = 110
            scene:_recompute()
            scene:_save()
            scene:_reset_to_parent()
            assert.are.equal(100, scene._working_blob.bidding.opening_min)
        end)

        it("Delete confirmation modal removes the template", function()
            scene:draw(1024, 720)
            scene:_open_delete_modal()
            scene:_confirm_delete()
            assert.is_nil(templates.get(custom.id))
            local switches = last_switches()
            assert.are.equal("template_picker", switches[#switches].id)
        end)
    end)

    describe("when entering with a built-in id", function()
        before_each(function()
            scene:enter(nil, { builtin_id = "polish" })
        end)

        it("disables Save and shows the read-only banner", function()
            scene:draw(1024, 720)
            assert.is_false(scene._save_button.enabled)
            assert.is_not_nil(find_text(mock, t("scene.template_editor.builtin_readonly")))
        end)

        it("renders every section header", function()
            scene:draw(1024, 720)
            local sections = require("core.rule_config").sections()
            for _, s in ipairs(sections) do
                local key = "templates.section." .. s
                assert.is_not_nil(find_text(mock, t(key)), "section " .. s)
            end
        end)
    end)
end)
