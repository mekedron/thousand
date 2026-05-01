-- E2E: opening the template editor for a built-in template. Verifies
-- the picker → editor wiring, that every section header is rendered,
-- that the deferred badge appears for at least one field, and that
-- the read-only banner is shown for a built-in.

local journey = require("tests.e2e.support.journey")

describe("e2e: template editor (built-in view)", function()
    local j

    before_each(function()
        j = journey.start({ locale = "en", width = 1280, height = 800 })
    end)

    after_each(function()
        if j then
            j:stop()
        end
    end)

    local function open_editor_for_russian()
        j:step()
        assert.is_true(j:click_text(j:find_localised("scene.menu.templates")))
        j:step()
        -- The picker draws an Edit button per row. Clicking the Edit text
        -- on the Russian row routes the editor to the built-in view.
        assert.is_true(j:click_text(j:find_localised("scene.template_picker.edit")))
        j:step()
    end

    it("renders the read-only banner for a built-in template", function()
        open_editor_for_russian()
        assert.is_not_nil(j:find_text(j:find_localised("scene.template_editor.builtin_readonly")))
    end)

    it("renders every catalogued section header", function()
        open_editor_for_russian()
        local rule_config = require("core.rule_config")
        for _, section in ipairs(rule_config.sections()) do
            local key = "templates.section." .. section
            local label = j:find_localised(key)
            assert.is_not_nil(j:find_text(label), "section " .. section)
        end
    end)

    it("renders the deferred badge somewhere", function()
        open_editor_for_russian()
        assert.is_not_nil(j:find_text(j:find_localised("scene.template_editor.deferred_badge")))
    end)

    it("Cancel returns to the picker", function()
        open_editor_for_russian()
        assert.is_true(j:click_text(j:find_localised("scene.template_editor.cancel")))
        j:step()
        assert.is_not_nil(j:find_text(j:find_localised("scene.template_picker.title")))
    end)
end)
