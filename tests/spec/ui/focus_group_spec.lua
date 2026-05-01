-- Unit coverage for the keyboard FocusGroup. Pure Lua — runs under busted
-- without love.* and exercises every API the scenes lean on.

local FocusGroup = require("ui.focus_group")
local Button = require("ui.button")

local function fake_button(opts)
    opts = opts or {}
    return Button.new({
        id = opts.id or "fake",
        label_key = "scene.menu.new_game",
        enabled = opts.enabled ~= false,
        on_press = opts.on_press or function() end,
    })
end

describe("ui.focus_group", function()
    describe("new()", function()
        it("starts with no focused button — focus surfaces only on advance/focus", function()
            local b = fake_button()
            local g = FocusGroup.new({ b })
            assert.is_nil(g:focused())
            assert.is_false(b.focused)
        end)
    end)

    describe("advance()", function()
        it("seeds focus on the first enabled button on the first forward call", function()
            local a, b, c =
                fake_button({ id = "a" }), fake_button({ id = "b" }), fake_button({ id = "c" })
            local g = FocusGroup.new({ a, b, c })
            g:advance(1)
            assert.are.equal(a, g:focused())
            assert.is_true(a.focused)
            assert.is_false(b.focused)
        end)

        it("seeds focus on the last enabled button on the first backward call", function()
            local a, b, c =
                fake_button({ id = "a" }), fake_button({ id = "b" }), fake_button({ id = "c" })
            local g = FocusGroup.new({ a, b, c })
            g:advance(-1)
            assert.are.equal(c, g:focused())
        end)

        it("skips disabled buttons", function()
            local a = fake_button({ id = "a", enabled = false })
            local b = fake_button({ id = "b" })
            local c = fake_button({ id = "c", enabled = false })
            local g = FocusGroup.new({ a, b, c })
            g:advance(1)
            assert.are.equal(b, g:focused())
            g:advance(1)
            assert.are.equal(b, g:focused()) -- only b is enabled, wraps back
        end)

        it("cycles forward and wraps", function()
            local a, b, c =
                fake_button({ id = "a" }), fake_button({ id = "b" }), fake_button({ id = "c" })
            local g = FocusGroup.new({ a, b, c })
            g:advance(1)
            g:advance(1)
            g:advance(1)
            g:advance(1)
            assert.are.equal(a, g:focused())
        end)
    end)

    describe("activate()", function()
        it("runs the focused button's on_press", function()
            local fired = 0
            local b = fake_button({
                on_press = function()
                    fired = fired + 1
                end,
            })
            local g = FocusGroup.new({ b })
            g:advance(1)
            g:activate()
            assert.are.equal(1, fired)
        end)

        it("does nothing when no button is focused", function()
            local fired = 0
            local b = fake_button({
                on_press = function()
                    fired = fired + 1
                end,
            })
            local g = FocusGroup.new({ b })
            g:activate()
            assert.are.equal(0, fired)
        end)

        it("does nothing when the focused button is disabled", function()
            local fired = 0
            local b = fake_button({
                on_press = function()
                    fired = fired + 1
                end,
            })
            local g = FocusGroup.new({ b })
            g:focus(b)
            b:set_enabled(false)
            g:activate()
            assert.are.equal(0, fired)
        end)
    end)

    describe("clear() and focus()", function()
        it("clear drops focus and the visual mark", function()
            local b = fake_button()
            local g = FocusGroup.new({ b })
            g:advance(1)
            g:clear()
            assert.is_nil(g:focused())
            assert.is_false(b.focused)
        end)

        it("focus(button) sets the focus directly", function()
            local a, b = fake_button({ id = "a" }), fake_button({ id = "b" })
            local g = FocusGroup.new({ a, b })
            g:focus(b)
            assert.are.equal(b, g:focused())
            assert.is_true(b.focused)
            assert.is_false(a.focused)
        end)

        it("focus(nil) is equivalent to clear", function()
            local a, b = fake_button({ id = "a" }), fake_button({ id = "b" })
            local g = FocusGroup.new({ a, b })
            g:focus(b)
            g:focus(nil)
            assert.is_nil(g:focused())
        end)
    end)

    describe("set_buttons()", function()
        it("replaces the list and drops focus", function()
            local a, b, c =
                fake_button({ id = "a" }), fake_button({ id = "b" }), fake_button({ id = "c" })
            local g = FocusGroup.new({ a, b })
            g:advance(1)
            assert.are.equal(a, g:focused())
            g:set_buttons({ b, c })
            assert.is_nil(g:focused())
            assert.is_false(a.focused)
            assert.is_false(b.focused)
            assert.is_false(c.focused)
        end)
    end)
end)
