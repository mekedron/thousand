-- Unit coverage for the shared button helper. Buttons are pure Lua except
-- for their draw method (which calls love.graphics) — these tests avoid
-- draw and exercise only state, hit-testing and event handling.

local Button = require("ui.button")

local function make(opts)
    opts = opts or {}
    opts.id = opts.id or "btn"
    opts.label_key = opts.label_key or "scene.menu.new_game"
    return Button.new(opts)
end

describe("ui.button", function()
    describe("new()", function()
        it("defaults enabled to true and starts unhovered/unfocused/unpressed", function()
            local b = make()
            assert.is_true(b.enabled)
            assert.is_false(b.hovered)
            assert.is_false(b.focused)
            assert.is_false(b.pressed)
        end)

        it("respects explicit enabled=false", function()
            assert.is_false(make({ enabled = false }).enabled)
        end)

        it("stores the label key for later i18n resolution", function()
            local b = make({ label_key = "scene.table.back_to_menu" })
            assert.are.equal("scene.table.back_to_menu", b.label_key)
        end)
    end)

    describe("set_rect()", function()
        it("stores x/y/w/h for hit-testing", function()
            local b = make()
            b:set_rect(10, 20, 100, 50)
            assert.are.equal(10, b.x)
            assert.are.equal(20, b.y)
            assert.are.equal(100, b.w)
            assert.are.equal(50, b.h)
        end)
    end)

    describe("contains()", function()
        it("returns true for a point inside the rect", function()
            local b = make()
            b:set_rect(10, 20, 100, 50)
            assert.is_true(b:contains(50, 40))
            assert.is_true(b:contains(10, 20))
            assert.is_true(b:contains(110, 70))
        end)

        it("returns false for a point outside the rect", function()
            local b = make()
            b:set_rect(10, 20, 100, 50)
            assert.is_false(b:contains(0, 0))
            assert.is_false(b:contains(200, 40))
            assert.is_false(b:contains(50, 100))
        end)
    end)

    describe("on_mousemoved()", function()
        it("sets hovered when over an enabled button", function()
            local b = make()
            b:set_rect(0, 0, 100, 50)
            b:on_mousemoved(50, 25)
            assert.is_true(b.hovered)
        end)

        it("clears hovered when the cursor leaves the rect", function()
            local b = make()
            b:set_rect(0, 0, 100, 50)
            b:on_mousemoved(50, 25)
            b:on_mousemoved(500, 500)
            assert.is_false(b.hovered)
        end)

        it("never hovers a disabled button", function()
            local b = make({ enabled = false })
            b:set_rect(0, 0, 100, 50)
            b:on_mousemoved(50, 25)
            assert.is_false(b.hovered)
        end)
    end)

    describe("press / release", function()
        it("press marks pressed=true only when enabled and over the button", function()
            local b = make()
            b:set_rect(0, 0, 100, 50)
            assert.is_false(b:on_mousepressed(500, 500, 1))
            assert.is_false(b.pressed)
            assert.is_true(b:on_mousepressed(50, 25, 1))
            assert.is_true(b.pressed)
        end)

        it("press ignores non-primary buttons", function()
            local b = make()
            b:set_rect(0, 0, 100, 50)
            assert.is_false(b:on_mousepressed(50, 25, 2))
            assert.is_false(b.pressed)
        end)

        it("press ignores disabled buttons", function()
            local b = make({ enabled = false })
            b:set_rect(0, 0, 100, 50)
            assert.is_false(b:on_mousepressed(50, 25, 1))
            assert.is_false(b.pressed)
        end)

        it("release inside the rect after a press triggers on_press", function()
            local fired = 0
            local b = make({
                on_press = function()
                    fired = fired + 1
                end,
            })
            b:set_rect(0, 0, 100, 50)
            b:on_mousepressed(50, 25, 1)
            b:on_mousereleased(60, 30, 1)
            assert.are.equal(1, fired)
            assert.is_false(b.pressed)
        end)

        it("release outside the rect cancels the action", function()
            local fired = 0
            local b = make({
                on_press = function()
                    fired = fired + 1
                end,
            })
            b:set_rect(0, 0, 100, 50)
            b:on_mousepressed(50, 25, 1)
            b:on_mousereleased(500, 500, 1)
            assert.are.equal(0, fired)
            assert.is_false(b.pressed)
        end)
    end)

    describe("activate()", function()
        it("triggers on_press when enabled", function()
            local fired = 0
            local b = make({
                on_press = function()
                    fired = fired + 1
                end,
            })
            b:activate()
            assert.are.equal(1, fired)
        end)

        it("does nothing when disabled", function()
            local fired = 0
            local b = make({
                enabled = false,
                on_press = function()
                    fired = fired + 1
                end,
            })
            b:activate()
            assert.are.equal(0, fired)
        end)
    end)
end)
