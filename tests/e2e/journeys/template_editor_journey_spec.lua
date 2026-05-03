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

    it("renders the deferred badge only when a deferred field exists", function()
        -- The badge must render iff a deferred field is present in the
        -- schema. Phase 3.7 reintroduced two deferred catalogue entries
        -- (deck_size, cut_deck_nine_jack_penalty) for book-mentioned
        -- rules that are out of scope for v1.
        open_editor_for_russian()
        local rule_config = require("core.rule_config")
        local has_deferred = false
        for _, section in ipairs(rule_config.sections()) do
            local section_schema = rule_config.schema_for(section)
            if section_schema and section_schema.fields then
                for _, field_name in ipairs(section_schema.fields) do
                    local descriptor = rule_config.schema_for(section .. "." .. field_name)
                    if descriptor and descriptor.status == "deferred" then
                        has_deferred = true
                        break
                    end
                end
            end
            if has_deferred then
                break
            end
        end
        local badge = j:find_text(j:find_localised("scene.template_editor.deferred_badge"))
        if has_deferred then
            assert.is_not_nil(badge)
        else
            assert.is_nil(badge)
        end
    end)

    it("Cancel returns to the picker", function()
        open_editor_for_russian()
        assert.is_true(j:click_text(j:find_localised("scene.template_editor.cancel")))
        j:step()
        assert.is_not_nil(j:find_text(j:find_localised("scene.template_picker.title")))
    end)

    -- Phase 3.10: built-in templates surface a "current value" marker on
    -- every disabled toggle / stepper so the active option stands out
    -- from the other greyed-out options. The marker is an inset 2px
    -- amber outline drawn inside the segment / value rect; we sniff it
    -- by matching the inset-by-2 geometry against a parent fill rect.
    it("draws the current-value marker on the canonical Russian template", function()
        open_editor_for_russian()
        local recording = j:draws()
        local fills = {}
        for _, op in ipairs(recording) do
            if op.op == "rectangle" and op.mode == "fill" then
                fills[op.x .. ":" .. op.y .. ":" .. op.w .. ":" .. op.h] = true
            end
        end
        local found = false
        for _, op in ipairs(recording) do
            if op.op == "rectangle" and op.mode == "line" then
                local key = (op.x - 2)
                    .. ":"
                    .. (op.y - 2)
                    .. ":"
                    .. (op.w + 4)
                    .. ":"
                    .. (op.h + 4)
                if fills[key] then
                    found = true
                    break
                end
            end
        end
        assert.is_true(found, "current-value marker rendered on read-only built-in")
    end)
end)
