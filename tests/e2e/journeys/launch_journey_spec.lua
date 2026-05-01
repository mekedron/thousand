-- First sanity-check journey: main.lua loads against the mock, and the
-- main menu scene renders its localised labels on frame 1. Deeper menu
-- behaviour (button clicks, navigation, modal flow) lives in
-- menu_navigation_spec.lua so this journey stays minimal — its job is
-- "the entry-point wiring is sane", not full-coverage menu testing.

local journey = require("tests.e2e.support.journey")

describe("e2e: launch journey", function()
    local j

    before_each(function()
        j = journey.start({ locale = "en" })
    end)

    after_each(function()
        if j then
            j:stop()
        end
    end)

    it("loads main.lua against the mock without errors", function()
        assert.is_not_nil(j)
        assert.is_table(j:draws())
    end)

    it("renders the main menu's localised title on the first frame", function()
        j:step()
        local title = j:find_localised("scene.menu.title")
        assert.is_not_nil(j:find_text(title), "expected menu title to be drawn on frame 1")
    end)

    it("draws the New Game label on the menu's first frame", function()
        j:step()
        local label = j:find_localised("scene.menu.new_game")
        assert.is_not_nil(j:find_text(label), "expected New Game label on the menu")
    end)

    it("survives input dispatch through the menu draw loop", function()
        j:step()
        j:click(1, 1)
        j:press_key("escape")
        j:resize(1024, 768)
        j:step()
        assert.is_table(j:draws())
    end)

    it("can resolve a localised string through the harness", function()
        local s = j:find_localised("scene.menu.new_game")
        assert.is_string(s)
        assert.are.not_equal("scene.menu.new_game", s)
    end)
end)
