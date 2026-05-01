-- Unit coverage for the layout primitives. Pure Lua — no love.* — so the
-- spec runs under plain busted with the project's standard config.

local layout = require("ui.layout")

describe("ui.layout", function()
    describe("MIN_HIT_TARGET", function()
        it("equals 44 logical pixels (iOS HIG)", function()
            assert.are.equal(44, layout.MIN_HIT_TARGET)
        end)
    end)

    describe("SAFE_MARGIN", function()
        it("equals 16 logical pixels", function()
            assert.are.equal(16, layout.SAFE_MARGIN)
        end)
    end)

    describe("top_right()", function()
        it("anchors the button to the top-right of the outer area with default margin", function()
            local rect = layout.top_right(1280, 720, 120, 48)
            assert.are.equal(1280 - 120 - 16, rect.x)
            assert.are.equal(16, rect.y)
            assert.are.equal(120, rect.w)
            assert.are.equal(48, rect.h)
        end)

        it("respects an explicit margin override", function()
            local rect = layout.top_right(800, 600, 100, 50, 24)
            assert.are.equal(800 - 100 - 24, rect.x)
            assert.are.equal(24, rect.y)
        end)

        it("reflows correctly across different window sizes", function()
            for _, size in ipairs({ { 800, 600 }, { 1024, 768 }, { 1600, 900 } }) do
                local w, h = size[1], size[2]
                local rect = layout.top_right(w, h, 120, 48)
                assert.are.equal(w - 120 - 16, rect.x, "x@" .. w .. "x" .. h)
                assert.are.equal(16, rect.y, "y@" .. w .. "x" .. h)
            end
        end)
    end)

    describe("center_panel()", function()
        it("centres the panel inside the outer area", function()
            local rect = layout.center_panel(1280, 720, 480, 220)
            assert.are.equal(math.floor(1280 * 0.5 - 480 * 0.5), rect.x)
            assert.are.equal(math.floor(720 * 0.5 - 220 * 0.5), rect.y)
            assert.are.equal(480, rect.w)
            assert.are.equal(220, rect.h)
        end)

        it("returns integer coordinates even at fractional centres", function()
            local rect = layout.center_panel(801, 601, 100, 100)
            assert.are.equal(math.floor(rect.x), rect.x)
            assert.are.equal(math.floor(rect.y), rect.y)
        end)
    end)

    describe("is_touch_target_ok()", function()
        it("returns true at the boundary", function()
            assert.is_true(layout.is_touch_target_ok(44, 44))
        end)

        it("returns true comfortably above the boundary", function()
            assert.is_true(layout.is_touch_target_ok(280, 56))
            assert.is_true(layout.is_touch_target_ok(120, 48))
        end)

        it("returns false when either axis falls below 44", function()
            assert.is_false(layout.is_touch_target_ok(43, 50))
            assert.is_false(layout.is_touch_target_ok(50, 43))
            assert.is_false(layout.is_touch_target_ok(0, 0))
        end)
    end)
end)
