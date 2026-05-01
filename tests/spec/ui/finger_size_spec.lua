-- Regression guard for the touch-target minimum. Drives the menu, table
-- and abandon-modal scenes through the e2e journey at multiple window
-- sizes (including the conf.lua minimum 800x600) and asserts every
-- button rectangle clears layout.MIN_HIT_TARGET on both axes.
--
-- Why test-layer enforcement instead of an assert in Button:set_rect?
-- Coupling Button to layout policy would fight a future Phase 3 template
-- editor that needs to render arbitrarily small in-progress edits. The
-- enforcement that matters in production lives here: a green CI run
-- guarantees no shipped scene has a sub-44px clickable surface.

local journey = require("tests.e2e.support.journey")
local layout = require("ui.layout")

-- Button bg palette from ui/button.lua. Any rectangle whose immediately
-- preceding setColor matches one of these is a button surface.
local BUTTON_BGS = {
    { 0.20, 0.40, 0.25 }, -- default
    { 0.26, 0.50, 0.32 }, -- hovered
    { 0.14, 0.30, 0.18 }, -- pressed
    { 0.18, 0.20, 0.18 }, -- disabled
}

local function near(a, b)
    return math.abs(a - b) < 1e-3
end

local function color_matches(a, b)
    return near(a[1], b[1]) and near(a[2], b[2]) and near(a[3], b[3])
end

local function is_button_bg(color)
    if not color then
        return false
    end
    for _, palette in ipairs(BUTTON_BGS) do
        if color_matches(color, palette) then
            return true
        end
    end
    return false
end

-- Walk the recording in order; return every fill rectangle whose most
-- recent preceding setColor matches a button bg.
local function button_rects(j)
    local rects = {}
    local last_color
    for _, op in ipairs(j:draws()) do
        if op.op == "setColor" then
            last_color = op.color
        elseif op.op == "rectangle" and op.mode == "fill" and is_button_bg(last_color) then
            rects[#rects + 1] = op
        end
    end
    return rects
end

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

local function click_button(j, label)
    local rect = smallest_rect_under_text(j, label)
    assert(rect, "no button rectangle for label: " .. label)
    j:click(rect_center(rect))
end

local SIZES = {
    { 800, 600 },
    { 1024, 768 },
    { 1280, 720 },
}

local function assert_all_buttons_finger_sized(j, where)
    local rects = button_rects(j)
    assert.is_true(#rects > 0, "no buttons found at " .. where)
    for _, r in ipairs(rects) do
        assert.is_true(
            layout.is_touch_target_ok(r.w, r.h),
            string.format(
                "%s: button rect %dx%d falls below MIN_HIT_TARGET=%d",
                where,
                r.w,
                r.h,
                layout.MIN_HIT_TARGET
            )
        )
    end
end

describe("ui finger-size guard", function()
    for _, size in ipairs(SIZES) do
        local w, h = size[1], size[2]
        local label = w .. "x" .. h

        describe("at " .. label, function()
            local j

            before_each(function()
                j = journey.start({ locale = "en", width = w, height = h })
                j:step()
            end)

            after_each(function()
                if j then
                    j:stop()
                end
            end)

            it("menu buttons clear MIN_HIT_TARGET", function()
                assert_all_buttons_finger_sized(j, "menu " .. label)
            end)

            it("table back-to-menu button clears MIN_HIT_TARGET", function()
                click_button(j, j:find_localised("scene.menu.new_game"))
                j:step()
                assert_all_buttons_finger_sized(j, "table " .. label)
            end)

            it("abandon-modal buttons clear MIN_HIT_TARGET", function()
                click_button(j, j:find_localised("scene.menu.new_game"))
                j:step()
                j:press_key("escape")
                j:step()
                click_button(j, j:find_localised("scene.menu.abandon"))
                j:step()
                assert_all_buttons_finger_sized(j, "abandon-modal " .. label)
            end)

            it("end-of-game button clears MIN_HIT_TARGET", function()
                -- The end-of-game scene isn't reachable from gameplay yet
                -- (Phase 2 wires the auto-transition later), so render it
                -- directly with a fake manager. The journey's love mock is
                -- still installed, so :draw(w, h) records into the shared
                -- recording.
                local end_of_game_scene = require("ui.scenes.end_of_game")
                local fake_manager = {
                    clear_session = function() end,
                    set_session = function() end,
                    session = function()
                        return nil
                    end,
                    is_game_active = function()
                        return false
                    end,
                    switch_to = function() end,
                }
                local scene = end_of_game_scene.new(fake_manager)
                scene:enter(nil, nil)
                _G.love.graphics.clear_recording()
                scene:draw(w, h)
                assert_all_buttons_finger_sized(j, "end-of-game " .. label)
            end)
        end)
    end
end)
