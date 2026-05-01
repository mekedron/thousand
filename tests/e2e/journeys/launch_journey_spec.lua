-- First sanity-check journey for the e2e harness. Passes against the
-- placeholder main.lua that only clears to green felt; designed to grow
-- into a real menu-then-table journey when the scene skeleton lands.

local journey = require("tests.e2e.support.journey")

local function near(actual, expected, eps)
    return math.abs(actual - expected) < (eps or 1e-3)
end

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

    it("renders the green-felt placeholder on the first frame", function()
        j:step()
        local clear = j:screen().clear
        assert.is_not_nil(clear, "expected love.graphics.clear() to have been called on frame 1")
        assert.is_true(near(clear[1], 0.07), "expected r=0.07 got " .. tostring(clear[1]))
        assert.is_true(near(clear[2], 0.18), "expected g=0.18 got " .. tostring(clear[2]))
        assert.is_true(near(clear[3], 0.10), "expected b=0.10 got " .. tostring(clear[3]))
    end)

    it("survives input dispatch through the placeholder draw loop", function()
        j:step()
        j:click(640, 360)
        j:press_key("escape")
        j:resize(1024, 768)
        j:step()
        -- No scene-state assertions yet — main.lua has no scenes.
        -- Once the menu lands, this block becomes:
        --   j:click_text(j:find_localised("menu.new_game"))
        --   j:step()
        --   assert.is_truthy(j:find_text(j:find_localised("scene.table.title")))
        --   j:press_key("escape")
        --   j:step()
        --   assert.is_truthy(j:find_text(j:find_localised("menu.new_game")))
    end)

    it("can resolve a localised string through the harness", function()
        local s = j:find_localised("menu.new_game")
        assert.is_string(s)
        assert.are.not_equal("menu.new_game", s)
    end)
end)
