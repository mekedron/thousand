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

    describe("hand_card_rects()", function()
        local hand_region = { x = 100, y = 500, w = 800, h = 140 }

        it("returns one rect per card, in the order they were given", function()
            local rects = layout.hand_card_rects(hand_region, 7)
            assert.are.equal(7, #rects)
        end)

        it("places every rect entirely inside the hand region", function()
            local rects = layout.hand_card_rects(hand_region, 8)
            for i, r in ipairs(rects) do
                assert.is_true(r.x >= hand_region.x, "rect " .. i .. " x")
                assert.is_true(r.y >= hand_region.y, "rect " .. i .. " y")
                assert.is_true(
                    r.x + r.w <= hand_region.x + hand_region.w,
                    "rect " .. i .. " right edge"
                )
                assert.is_true(
                    r.y + r.h <= hand_region.y + hand_region.h,
                    "rect " .. i .. " bottom edge"
                )
            end
        end)

        it("keeps every rect at or above MIN_HIT_TARGET on both axes", function()
            local rects = layout.hand_card_rects(hand_region, 10)
            for i, r in ipairs(rects) do
                assert.is_true(r.w >= layout.MIN_HIT_TARGET, "rect " .. i .. " w")
                assert.is_true(r.h >= layout.MIN_HIT_TARGET, "rect " .. i .. " h")
            end
        end)

        it("returns an empty list for zero cards", function()
            assert.are.same({}, layout.hand_card_rects(hand_region, 0))
        end)

        it("returns rects whose .x increases monotonically", function()
            local rects = layout.hand_card_rects(hand_region, 7)
            for i = 2, #rects do
                assert.is_true(rects[i].x > rects[i - 1].x, "rect " .. i .. " left of previous")
            end
        end)

        it("uses floored integer coordinates", function()
            local rects = layout.hand_card_rects({ x = 11, y = 13, w = 333, h = 99 }, 6)
            for _, r in ipairs(rects) do
                assert.are.equal(math.floor(r.x), r.x)
                assert.are.equal(math.floor(r.y), r.y)
                assert.are.equal(math.floor(r.w), r.w)
                assert.are.equal(math.floor(r.h), r.h)
            end
        end)
    end)

    describe("talon_card_rects()", function()
        local centre_region = { x = 50, y = 200, w = 600, h = 200 }

        it("returns one rect per card up to count", function()
            local rects = layout.talon_card_rects(centre_region, 3)
            assert.are.equal(3, #rects)
        end)

        it("returns an empty list for zero cards", function()
            assert.are.same({}, layout.talon_card_rects(centre_region, 0))
        end)

        it("places every rect inside the centre region", function()
            local rects = layout.talon_card_rects(centre_region, 3)
            for i, r in ipairs(rects) do
                assert.is_true(r.x >= centre_region.x, "rect " .. i .. " x")
                assert.is_true(r.y >= centre_region.y, "rect " .. i .. " y")
                assert.is_true(
                    r.x + r.w <= centre_region.x + centre_region.w,
                    "rect " .. i .. " right edge"
                )
            end
        end)
    end)

    describe("opponent_seat_rects()", function()
        local opponents_region = { x = 16, y = 16, w = 800, h = 120 }

        it("returns one rect per opponent seat", function()
            local rects = layout.opponent_seat_rects(opponents_region, 2)
            assert.are.equal(2, #rects)
        end)

        it("returns an empty list for zero opponents", function()
            assert.are.same({}, layout.opponent_seat_rects(opponents_region, 0))
        end)

        it("packs rects horizontally across the region", function()
            local rects = layout.opponent_seat_rects(opponents_region, 2)
            assert.is_true(rects[2].x > rects[1].x)
            for _, r in ipairs(rects) do
                assert.is_true(r.x >= opponents_region.x)
                assert.is_true(r.x + r.w <= opponents_region.x + opponents_region.w + 1)
            end
        end)

        it("keeps every rect at or above MIN_HIT_TARGET on both axes", function()
            local rects = layout.opponent_seat_rects(opponents_region, 2)
            for _, r in ipairs(rects) do
                assert.is_true(r.w >= layout.MIN_HIT_TARGET)
                assert.is_true(r.h >= layout.MIN_HIT_TARGET)
            end
        end)
    end)
end)
