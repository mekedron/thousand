-- Unit coverage for the number-stepper widget. Like the segmented
-- toggle but for free-range numeric fields with min/max bounds and a
-- step. Click the - button to decrement; click the + button to
-- increment. Values clamp to [min, max]. The draw block runs under
-- tests.e2e.support.love_mock so we can also assert the rendered
-- "current value" marker in the disabled state.

local NumberStepper = require("ui.number_stepper")
local love_mock = require("tests.e2e.support.love_mock")

local function make(opts)
    opts = opts or {}
    opts.id = opts.id or "num"
    opts.current = opts.current or 100
    opts.step = opts.step or 5
    opts.min = opts.min or 0
    opts.max = opts.max or 1000
    return NumberStepper.new(opts)
end

describe("ui.number_stepper", function()
    describe("new()", function()
        it("stores current/step/min/max and defaults enabled to true", function()
            local s = make({ current = 100, step = 5, min = 50, max = 200 })
            assert.is_true(s.enabled)
            assert.are.equal(100, s.current)
            assert.are.equal(5, s.step)
            assert.are.equal(50, s.min)
            assert.are.equal(200, s.max)
        end)

        it("respects explicit enabled=false", function()
            assert.is_false(make({ enabled = false }).enabled)
        end)
    end)

    describe("set_value", function()
        it("clamps to min", function()
            local s = make({ current = 50, min = 50, max = 200 })
            s:set_value(10)
            assert.are.equal(50, s.current)
        end)

        it("clamps to max", function()
            local s = make({ current = 50, min = 50, max = 200 })
            s:set_value(500)
            assert.are.equal(200, s.current)
        end)

        it("ignores non-number values", function()
            local s = make()
            s:set_value("nope")
            assert.are.equal(100, s.current)
        end)
    end)

    describe("set_enabled", function()
        it("toggles the enabled flag", function()
            local s = make()
            s:set_enabled(false)
            assert.is_false(s.enabled)
            s:set_enabled(true)
            assert.is_true(s.enabled)
        end)
    end)

    describe("button rects", function()
        it("computes minus and plus rects within set_rect", function()
            local s = make()
            s:set_rect(0, 0, 200, 50)
            local m, p = s:minus_rect(), s:plus_rect()
            assert.are.equal(0, m.x)
            assert.are.equal(50, m.h)
            assert.is_true(p.x > m.x + m.w)
        end)
    end)

    describe("clicks", function()
        it("clicking the minus button decrements by step and fires on_change", function()
            local fired = {}
            local s = make({
                current = 100,
                step = 5,
                on_change = function(v)
                    fired[#fired + 1] = v
                end,
            })
            s:set_rect(0, 0, 200, 50)
            local m = s:minus_rect()
            s:on_mousepressed(m.x + 5, m.y + 5, 1)
            s:on_mousereleased(m.x + 5, m.y + 5, 1)
            assert.are.equal(95, s.current)
            assert.are.same({ 95 }, fired)
        end)

        it("clicking the plus button increments by step and fires on_change", function()
            local fired = {}
            local s = make({
                current = 100,
                step = 5,
                on_change = function(v)
                    fired[#fired + 1] = v
                end,
            })
            s:set_rect(0, 0, 200, 50)
            local p = s:plus_rect()
            s:on_mousepressed(p.x + 5, p.y + 5, 1)
            s:on_mousereleased(p.x + 5, p.y + 5, 1)
            assert.are.equal(105, s.current)
            assert.are.same({ 105 }, fired)
        end)

        it("respects min on decrement", function()
            local fired = 0
            local s = make({
                current = 50,
                min = 50,
                step = 5,
                on_change = function()
                    fired = fired + 1
                end,
            })
            s:set_rect(0, 0, 200, 50)
            local m = s:minus_rect()
            s:on_mousepressed(m.x + 5, m.y + 5, 1)
            s:on_mousereleased(m.x + 5, m.y + 5, 1)
            assert.are.equal(50, s.current)
            assert.are.equal(0, fired)
        end)

        it("respects max on increment", function()
            local fired = 0
            local s = make({
                current = 200,
                max = 200,
                step = 5,
                on_change = function()
                    fired = fired + 1
                end,
            })
            s:set_rect(0, 0, 200, 50)
            local p = s:plus_rect()
            s:on_mousepressed(p.x + 5, p.y + 5, 1)
            s:on_mousereleased(p.x + 5, p.y + 5, 1)
            assert.are.equal(200, s.current)
            assert.are.equal(0, fired)
        end)

        it("ignores clicks when disabled", function()
            local fired = 0
            local s = make({
                enabled = false,
                on_change = function()
                    fired = fired + 1
                end,
            })
            s:set_rect(0, 0, 200, 50)
            local p = s:plus_rect()
            s:on_mousepressed(p.x + 5, p.y + 5, 1)
            s:on_mousereleased(p.x + 5, p.y + 5, 1)
            assert.are.equal(100, s.current)
            assert.are.equal(0, fired)
        end)
    end)

    describe("draw — current-value marker", function()
        local AMBER = { 0.95, 0.85, 0.30, 1 }
        local mock

        before_each(function()
            mock = love_mock.new({ width = 800, height = 600 })
            mock:install()
        end)

        after_each(function()
            mock:restore()
        end)

        local function find_inset_outline(rects, value_rect)
            for _, r in ipairs(rects) do
                if
                    r.op == "rectangle"
                    and r.mode == "line"
                    and r.x == value_rect.x + 2
                    and r.y == value_rect.y + 2
                    and r.w == value_rect.w - 4
                    and r.h == value_rect.h - 4
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

        it("draws an inset amber outline around the value when disabled", function()
            local s = make({ enabled = false, current = 100 })
            s:set_rect(0, 0, 300, 50)
            s:draw()
            local rects = mock.graphics.recording()
            local outline = find_inset_outline(rects, s:value_rect())
            assert.is_not_nil(outline, "current marker drawn around value rect")
            assert.is_true(
                colors_match(color_before(rects, outline), AMBER),
                "outline drawn in amber"
            )
        end)

        it("does not draw the marker when enabled", function()
            local s = make({ enabled = true, current = 100 })
            s:set_rect(0, 0, 300, 50)
            s:draw()
            local rects = mock.graphics.recording()
            assert.is_nil(
                find_inset_outline(rects, s:value_rect()),
                "no current marker when enabled"
            )
        end)
    end)
end)
