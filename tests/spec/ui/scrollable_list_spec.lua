-- Unit coverage for the scrollable-list helper. Pure-Lua scroll math —
-- no love.graphics calls. Tracks viewport offset, content height, and
-- mouse-wheel/keyboard scrolling. Drawing applies a translate before
-- the consumer renders rows; that is exercised in scene specs, not
-- here.

local ScrollableList = require("ui.scrollable_list")

local function make(opts)
    opts = opts or {}
    opts.viewport_w = opts.viewport_w or 600
    opts.viewport_h = opts.viewport_h or 400
    opts.content_h = opts.content_h or 1000
    return ScrollableList.new(opts)
end

describe("ui.scrollable_list", function()
    describe("new()", function()
        it("starts at offset 0", function()
            local s = make()
            assert.are.equal(0, s.offset_y)
        end)
    end)

    describe("set_content_height", function()
        it("clamps current offset to the new max", function()
            local s = make({ content_h = 1000, viewport_h = 400 })
            s:set_offset(500) -- max would be 600; valid
            assert.are.equal(500, s.offset_y)
            s:set_content_height(600) -- max becomes 200; offset clamps
            assert.are.equal(200, s.offset_y)
        end)
    end)

    describe("max_offset", function()
        it("returns content_h - viewport_h, never negative", function()
            local s = make({ content_h = 1000, viewport_h = 400 })
            assert.are.equal(600, s:max_offset())
            s:set_content_height(200)
            assert.are.equal(0, s:max_offset())
        end)
    end)

    describe("set_offset / scroll_by", function()
        it("clamps to [0, max_offset]", function()
            local s = make({ content_h = 1000, viewport_h = 400 })
            s:set_offset(-50)
            assert.are.equal(0, s.offset_y)
            s:set_offset(5000)
            assert.are.equal(600, s.offset_y)
        end)

        it("scroll_by adds delta and clamps", function()
            local s = make({ content_h = 1000, viewport_h = 400 })
            s:scroll_by(120)
            assert.are.equal(120, s.offset_y)
            s:scroll_by(-200)
            assert.are.equal(0, s.offset_y)
        end)
    end)

    describe("on_wheel", function()
        it("dy>0 scrolls up (decreases offset)", function()
            local s = make()
            s:set_offset(200)
            s:on_wheel(0, 1)
            assert.is_true(s.offset_y < 200)
        end)

        it("dy<0 scrolls down (increases offset)", function()
            local s = make()
            s:set_offset(0)
            s:on_wheel(0, -1)
            assert.is_true(s.offset_y > 0)
        end)
    end)

    describe("page", function()
        it("page_down scrolls by ~viewport_h", function()
            local s = make({ viewport_h = 400, content_h = 2000 })
            s:page_down()
            assert.are.equal(400, s.offset_y)
        end)

        it("page_up scrolls back by ~viewport_h, clamped at 0", function()
            local s = make({ viewport_h = 400, content_h = 2000 })
            s:set_offset(800)
            s:page_up()
            assert.are.equal(400, s.offset_y)
            s:page_up()
            assert.are.equal(0, s.offset_y)
            s:page_up()
            assert.are.equal(0, s.offset_y)
        end)
    end)

    describe("contains_viewport_point", function()
        it("returns true within the viewport rect", function()
            local s = make()
            s:set_rect(10, 20, 600, 400)
            assert.is_true(s:contains_viewport_point(20, 30))
            assert.is_false(s:contains_viewport_point(0, 0))
            assert.is_false(s:contains_viewport_point(700, 30))
        end)
    end)
end)
