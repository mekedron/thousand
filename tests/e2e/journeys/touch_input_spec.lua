-- End-to-end coverage for the touch input path: a touch reaches the same
-- on_press logic a mouse click does, mouse callbacks are suppressed while
-- a touch is in flight, and no button is left visually hovered after a
-- touch release. These tests prove the layer-4 funnel in main.lua,
-- exercising the same code path real iOS / Android devices would.

local journey = require("tests.e2e.support.journey")

local function smallest_rect_under_text(j, text)
    local best
    for _, op in ipairs(j:draws()) do
        if op.op == "rectangle" and op.mode == "fill" then
            for _, t in ipairs(j:draws()) do
                if t.op == "text" and t.text == text then
                    if
                        t.x >= op.x
                        and t.x <= op.x + op.w
                        and t.y >= op.y
                        and t.y <= op.y + op.h
                    then
                        if not best or (op.w * op.h) < (best.w * best.h) then
                            best = op
                        end
                    end
                end
            end
        end
    end
    return best
end

local function rect_center(rect)
    return rect.x + rect.w * 0.5, rect.y + rect.h * 0.5
end

-- Colour bands lifted from ui/button.lua; if the widget's palette changes,
-- update both files together.
local HOVERED_BG = { 0.26, 0.50, 0.32 }

local function near(a, b)
    return math.abs(a - b) < 1e-3
end

local function color_matches(a, b)
    return near(a[1], b[1]) and near(a[2], b[2]) and near(a[3], b[3])
end

local function rect_bg_color(j, rect)
    local last_color
    for _, op in ipairs(j:draws()) do
        if op.op == "setColor" then
            last_color = op.color
        end
        if op == rect then
            return last_color
        end
    end
    return nil
end

describe("e2e: touch input", function()
    local j

    before_each(function()
        j = journey.start({ locale = "en" })
        j:step()
    end)

    after_each(function()
        if j then
            j:stop()
        end
    end)

    describe("touch reaches the same action path as click", function()
        it("touching New Game transitions to the table", function()
            local rect = smallest_rect_under_text(j, j:find_localised("scene.menu.new_game"))
            local cx, cy = rect_center(rect)
            j:touch(cx, cy)
            j:step()
            assert.is_not_nil(j:find_text(j:find_localised("scene.table.title")))
        end)

        it("touching the Menu button on the table returns to the menu", function()
            local rect = smallest_rect_under_text(j, j:find_localised("scene.menu.new_game"))
            j:click(rect_center(rect))
            j:step()
            local back_label = j:find_localised("scene.table.back_to_menu")
            local back_rect = smallest_rect_under_text(j, back_label)
            j:touch(rect_center(back_rect))
            j:step()
            assert.is_not_nil(j:find_text(j:find_localised("scene.menu.title")))
        end)
    end)

    describe("synthesised mouse events during a touch are suppressed", function()
        it("a click while holding a touch does not transition", function()
            j:press_touch(10, 10)
            local rect = smallest_rect_under_text(j, j:find_localised("scene.menu.new_game"))
            local cx, cy = rect_center(rect)
            j:click(cx, cy)
            j:step()
            assert.is_not_nil(j:find_text(j:find_localised("scene.menu.title")))
        end)

        it("after the touch ends and one frame elapses, mouse works again", function()
            j:press_touch(10, 10)
            j:release_touch(10, 10)
            -- Advance one frame so love.update clears the touch_active flag.
            j:step()
            local rect = smallest_rect_under_text(j, j:find_localised("scene.menu.new_game"))
            local cx, cy = rect_center(rect)
            j:click(cx, cy)
            j:step()
            assert.is_not_nil(j:find_text(j:find_localised("scene.table.title")))
        end)
    end)

    describe("touch release clears any lingering hover state", function()
        it("a touch drag onto a button does not leave it hovered after release", function()
            -- Quit is a safe target: in the e2e harness love.event.quit is a
            -- no-op so the menu stays put after the gesture, and we can
            -- inspect Quit's bg colour on the next frame.
            local rect = smallest_rect_under_text(j, j:find_localised("scene.menu.quit"))
            local cx, cy = rect_center(rect)
            j:press_touch(cx, cy)
            j:move_touch(cx, cy, 0, 0)
            j:release_touch(cx, cy)
            j:step()
            local rect_after = smallest_rect_under_text(j, j:find_localised("scene.menu.quit"))
            assert.is_not_nil(rect_after)
            assert.is_false(
                color_matches(rect_bg_color(j, rect_after), HOVERED_BG),
                "Quit must not be visually hovered after touch release"
            )
        end)
    end)
end)
