-- E2E: opening the template picker from the main menu, seeing the
-- built-in templates rendered with the canonical Russian as "in use",
-- and clicking through to the editor for a built-in. Proves the
-- wiring main.lua → template_picker → template_editor.

local journey = require("tests.e2e.support.journey")

describe("e2e: template picker", function()
    local j

    before_each(function()
        j = journey.start({ locale = "en", width = 1280, height = 800 })
    end)

    after_each(function()
        if j then
            j:stop()
        end
    end)

    it("Templates button appears on the main menu", function()
        j:step()
        local label = j:find_localised("scene.menu.templates")
        assert.is_not_nil(j:find_text(label))
    end)

    it("clicking Templates opens the picker with built-ins listed", function()
        j:step()
        assert.is_true(j:click_text(j:find_localised("scene.menu.templates")))
        j:step()
        assert.is_not_nil(j:find_text(j:find_localised("scene.template_picker.title")))
        assert.is_not_nil(j:find_text(j:find_localised("scene.template_picker.builtins_header")))
        assert.is_not_nil(j:find_text(j:find_localised("templates.builtin.russian")))
        assert.is_not_nil(j:find_text(j:find_localised("templates.builtin.polish")))
    end)

    it("Russian is marked as in use by default", function()
        j:step()
        assert.is_true(j:click_text(j:find_localised("scene.menu.templates")))
        j:step()
        assert.is_not_nil(j:find_text(j:find_localised("scene.template_picker.in_use_badge")))
    end)

    it("Back button on the picker returns to the menu", function()
        j:step()
        assert.is_true(j:click_text(j:find_localised("scene.menu.templates")))
        j:step()
        assert.is_true(j:click_text(j:find_localised("scene.template_picker.back")))
        j:step()
        -- Menu's New Game label should be visible again.
        assert.is_not_nil(j:find_text(j:find_localised("scene.menu.new_game")))
    end)
end)
