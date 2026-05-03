-- Unit coverage for the segmented-toggle widget. Values + parallel
-- label-key list + currently-selected value. Click on a segment fires
-- on_change with the new value. Pure-Lua state for the dispatch tests;
-- the draw block runs under tests.e2e.support.love_mock so we can also
-- assert the rendered "current value" marker in the disabled state.

local Toggle = require("ui.toggle")
local love_mock = require("tests.e2e.support.love_mock")

local function make(opts)
    opts = opts or {}
    opts.id = opts.id or "tog"
    opts.values = opts.values or { "off", "on" }
    opts.value_labels = opts.value_labels
        or {
            "scene.settings.toggle.off",
            "scene.settings.toggle.on",
        }
    opts.current = opts.current or opts.values[1]
    return Toggle.new(opts)
end

describe("ui.toggle", function()
    describe("new()", function()
        it("defaults enabled to true and stores values plus current", function()
            local t = make()
            assert.is_true(t.enabled)
            assert.are.same({ "off", "on" }, t.values)
            assert.are.equal("off", t.current)
        end)

        it("respects explicit enabled=false", function()
            assert.is_false(make({ enabled = false }).enabled)
        end)
    end)

    describe("set_rect / segments", function()
        it("partitions horizontal width across the values", function()
            local t = make({ values = { "a", "b", "c" } })
            t:set_rect(0, 0, 300, 50)
            local rects = t:segment_rects()
            assert.are.equal(3, #rects)
            assert.are.equal(0, rects[1].x)
            assert.are.equal(100, rects[2].x)
            assert.are.equal(200, rects[3].x)
            for _, r in ipairs(rects) do
                assert.are.equal(50, r.h)
            end
        end)
    end)

    describe("set_value", function()
        it("updates the current value", function()
            local t = make()
            t:set_value("on")
            assert.are.equal("on", t.current)
        end)

        it("ignores values not in the list", function()
            local t = make()
            t:set_value("nope")
            assert.are.equal("off", t.current)
        end)
    end)

    describe("set_enabled", function()
        it("toggles the enabled flag", function()
            local t = make()
            t:set_enabled(false)
            assert.is_false(t.enabled)
            t:set_enabled(true)
            assert.is_true(t.enabled)
        end)
    end)

    describe("contains", function()
        it("returns true inside the widget rect", function()
            local t = make()
            t:set_rect(10, 20, 200, 50)
            assert.is_true(t:contains(15, 25))
            assert.is_false(t:contains(0, 0))
        end)
    end)

    describe("on_mousepressed", function()
        it("clicks on a segment select that segment's value and fire on_change", function()
            local fired = {}
            local t = make({
                values = { "a", "b", "c" },
                value_labels = { "x", "y", "z" },
                on_change = function(value)
                    fired[#fired + 1] = value
                end,
            })
            t:set_rect(0, 0, 300, 50)
            t:on_mousepressed(150, 25, 1) -- middle segment
            t:on_mousereleased(150, 25, 1)
            assert.are.equal("b", t.current)
            assert.are.same({ "b" }, fired)
        end)

        it("does not fire on a no-op click on the already-selected segment", function()
            local fired = 0
            local t = make({
                on_change = function()
                    fired = fired + 1
                end,
            })
            t:set_rect(0, 0, 200, 50)
            t:on_mousepressed(50, 25, 1) -- left segment, current "off"
            t:on_mousereleased(50, 25, 1)
            assert.are.equal(0, fired)
        end)

        it("ignores clicks when disabled", function()
            local fired = 0
            local t = make({
                enabled = false,
                on_change = function()
                    fired = fired + 1
                end,
            })
            t:set_rect(0, 0, 200, 50)
            t:on_mousepressed(150, 25, 1)
            t:on_mousereleased(150, 25, 1)
            assert.are.equal("off", t.current)
            assert.are.equal(0, fired)
        end)

        it("ignores release outside the same segment", function()
            local fired = 0
            local t = make({
                on_change = function()
                    fired = fired + 1
                end,
            })
            t:set_rect(0, 0, 200, 50)
            t:on_mousepressed(150, 25, 1) -- press in segment 2
            t:on_mousereleased(50, 25, 1) -- release in segment 1
            assert.are.equal("off", t.current)
            assert.are.equal(0, fired)
        end)
    end)

    describe("activate", function()
        it("cycles to the next allowed value when enabled", function()
            local fired = {}
            local t = make({
                values = { "a", "b", "c" },
                value_labels = { "x", "y", "z" },
                current = "a",
                on_change = function(value)
                    fired[#fired + 1] = value
                end,
            })
            t:activate()
            assert.are.equal("b", t.current)
            t:activate()
            assert.are.equal("c", t.current)
            t:activate()
            assert.are.equal("a", t.current)
            assert.are.same({ "b", "c", "a" }, fired)
        end)

        it("does nothing when disabled", function()
            local t = make({ enabled = false })
            t:activate()
            assert.are.equal("off", t.current)
        end)
    end)

    describe("draw — current-value marker", function()
        local AMBER = { 0.95, 0.85, 0.30, 1 }
        local mock

        before_each(function()
            mock = love_mock.new({ width = 800, height = 600 })
            mock:install()
            -- Silence the i18n missing-key logger — the test labels
            -- are placeholder strings, not real i18n keys, so the
            -- logger would otherwise spam the test output.
            require("app.i18n")._set_logger(function() end)
        end)

        after_each(function()
            mock:restore()
        end)

        local function find_inset_outline(rects, segment)
            -- Current marker is line-mode, inset by +2 / -4 from segment.
            for _, r in ipairs(rects) do
                if
                    r.op == "rectangle"
                    and r.mode == "line"
                    and r.x == segment.x + 2
                    and r.y == segment.y + 2
                    and r.w == segment.w - 4
                    and r.h == segment.h - 4
                then
                    return r
                end
            end
            return nil
        end

        local function color_before(rects, target)
            local last
            for _, r in ipairs(rects) do
                if r == target then
                    return last
                end
                if r.op == "setColor" then
                    last = r.color
                end
            end
            return last
        end

        local function colors_match(actual, expected)
            if not actual then
                return false
            end
            for i = 1, 4 do
                if math.abs((actual[i] or 0) - (expected[i] or 0)) > 1e-3 then
                    return false
                end
            end
            return true
        end

        it("draws an inset amber outline on the current segment when disabled", function()
            local t = make({
                values = { "a", "b", "c" },
                value_labels = { "x", "y", "z" },
                current = "b",
                enabled = false,
            })
            t:set_rect(0, 0, 300, 50)
            t:draw()
            local rects = mock.graphics.recording()
            local segments = t:segment_rects()
            -- Expect exactly one inset outline, on segment 2 (current "b").
            assert.is_not_nil(
                find_inset_outline(rects, segments[2]),
                "current-segment outline drawn"
            )
            assert.is_nil(find_inset_outline(rects, segments[1]), "no marker on non-current")
            assert.is_nil(find_inset_outline(rects, segments[3]), "no marker on non-current")
            local outline = find_inset_outline(rects, segments[2])
            assert.is_true(
                colors_match(color_before(rects, outline), AMBER),
                "outline drawn in amber"
            )
        end)

        it("does not draw the marker when enabled", function()
            local t = make({
                values = { "a", "b", "c" },
                value_labels = { "x", "y", "z" },
                current = "b",
                enabled = true,
            })
            t:set_rect(0, 0, 300, 50)
            t:draw()
            local rects = mock.graphics.recording()
            local segments = t:segment_rects()
            for i = 1, 3 do
                assert.is_nil(
                    find_inset_outline(rects, segments[i]),
                    "no current marker when enabled"
                )
            end
        end)
    end)
end)
