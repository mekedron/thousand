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

    describe("table_regions()", function()
        it("returns five named regions plus the menu button rect", function()
            local r = layout.table_regions(1280, 720)
            assert.is_table(r.opponents)
            assert.is_table(r.centre)
            assert.is_table(r.hand)
            assert.is_table(r.scoreboard)
            assert.is_table(r.menu_button)
        end)

        it("anchors the menu button at the top-right", function()
            local r = layout.table_regions(1280, 720)
            local expected = layout.top_right(1280, 720, 120, 48)
            assert.are.equal(expected.x, r.menu_button.x)
            assert.are.equal(expected.y, r.menu_button.y)
        end)

        it("places the scoreboard column on the right below the menu button", function()
            local r = layout.table_regions(1280, 720)
            assert.is_true(r.scoreboard.x > r.opponents.x + r.opponents.w)
            assert.is_true(r.scoreboard.y > r.menu_button.y + r.menu_button.h - 1)
        end)

        it("stacks opponents → centre → hand vertically with margins between", function()
            local r = layout.table_regions(1280, 720)
            assert.is_true(r.centre.y > r.opponents.y + r.opponents.h)
            assert.is_true(r.hand.y > r.centre.y + r.centre.h)
        end)

        it("returns floored integer coordinates", function()
            local r = layout.table_regions(801, 601)
            for _, key in ipairs({ "opponents", "centre", "hand", "scoreboard" }) do
                local rect = r[key]
                assert.are.equal(math.floor(rect.x), rect.x, key .. ".x")
                assert.are.equal(math.floor(rect.y), rect.y, key .. ".y")
                assert.are.equal(math.floor(rect.w), rect.w, key .. ".w")
                assert.are.equal(math.floor(rect.h), rect.h, key .. ".h")
            end
        end)

        it("reflows across window sizes", function()
            for _, size in ipairs({ { 800, 600 }, { 1024, 768 }, { 1600, 900 } }) do
                local w, h = size[1], size[2]
                local r = layout.table_regions(w, h)
                assert.is_true(r.hand.y < h, "hand fits in " .. w .. "x" .. h)
                assert.is_true(r.scoreboard.x + r.scoreboard.w <= w, "scoreboard fits horizontally")
            end
        end)

        it("respects the menu_btn_h override when reserving the right column", function()
            local r = layout.table_regions(1280, 720, { menu_btn_h = 64 })
            assert.is_true(r.scoreboard.y >= layout.SAFE_MARGIN + 64)
        end)
    end)
end)
