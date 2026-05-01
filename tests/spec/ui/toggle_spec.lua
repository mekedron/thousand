-- Unit coverage for the segmented-toggle widget. Values + parallel
-- label-key list + currently-selected value. Click on a segment fires
-- on_change with the new value. Pure-Lua state; draw is tested only
-- to confirm it doesn't blow up under love-free unit tests (it isn't,
-- in fact, called here — toggle_spec exercises state and dispatch).

local Toggle = require("ui.toggle")

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
end)
