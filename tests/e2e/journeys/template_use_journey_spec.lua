-- E2E: "Use this template" persists the active id so the menu's New
-- Game uses the chosen template's RuleConfig. We don't drive a full
-- game, just prove the wiring: pick Polish in the picker, press Use,
-- start a new game, assert the session's config has talon.size = 2.

local journey = require("tests.e2e.support.journey")

describe("e2e: use this template", function()
    local j

    before_each(function()
        j = journey.start({ locale = "en", width = 1280, height = 800 })
    end)

    after_each(function()
        if j then
            j:stop()
        end
    end)

    it("Use button on the picker persists the active id", function()
        local app_templates = require("app.templates")
        j:step()
        assert.is_true(j:click_text(j:find_localised("scene.menu.templates")))
        j:step()
        -- The first "Use" text op corresponds to the Russian row (built-ins
        -- list canonical-Russian first). Clicking it persists "russian" as
        -- the active id and routes back to the menu.
        assert.is_true(j:click_text(j:find_localised("scene.template_picker.use")))
        j:step()
        assert.are.equal("russian", app_templates.get_active_id())
        -- Menu's New Game button is back on screen.
        assert.is_not_nil(j:find_text(j:find_localised("scene.menu.new_game")))
    end)

    it("resolve_active_config feeds the menu's New Game", function()
        -- Sanity check on the wiring: the menu now reads the active id
        -- via app.templates.resolve_active_config when starting a session.
        -- We verify the resolution itself rather than driving a full game,
        -- because non-Russian templates are not yet playable end-to-end
        -- (Phase 3.6 lifts the dealer's unsupported_talon_size guard).
        local app_templates = require("app.templates")
        local rule_config = require("core.rule_config")
        app_templates.set_active_id("polish")
        local cfg = app_templates.resolve_active_config()
        assert.is_true(rule_config.is_rule_config(cfg))
        assert.are.equal(2, cfg.talon.size)
    end)
end)
