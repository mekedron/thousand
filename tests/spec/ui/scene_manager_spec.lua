-- Unit coverage for the scene manager. The manager itself is pure Lua
-- (no love.* dependency), so it can be exercised straight from busted.

local scene_manager = require("ui.scene_manager")

local function fake_scene()
    local s = {
        events = {},
    }
    function s:enter(prev_id, params)
        self.events[#self.events + 1] = { name = "enter", prev = prev_id, params = params }
    end
    function s:leave(next_id)
        self.events[#self.events + 1] = { name = "leave", next = next_id }
    end
    function s:update(dt)
        self.events[#self.events + 1] = { name = "update", dt = dt }
    end
    function s:draw(w, h)
        self.events[#self.events + 1] = { name = "draw", w = w, h = h }
    end
    function s:mousemoved(x, y, dx, dy)
        self.events[#self.events + 1] = {
            name = "mousemoved",
            x = x,
            y = y,
            dx = dx,
            dy = dy,
        }
    end
    function s:mousepressed(x, y, button)
        self.events[#self.events + 1] = { name = "mousepressed", x = x, y = y, button = button }
    end
    function s:mousereleased(x, y, button)
        self.events[#self.events + 1] = {
            name = "mousereleased",
            x = x,
            y = y,
            button = button,
        }
    end
    function s:keypressed(key)
        self.events[#self.events + 1] = { name = "keypressed", key = key }
    end
    function s:keyreleased(key)
        self.events[#self.events + 1] = { name = "keyreleased", key = key }
    end
    function s:resize(w, h)
        self.events[#self.events + 1] = { name = "resize", w = w, h = h }
    end
    return s
end

describe("ui.scene_manager", function()
    local m, a, b

    before_each(function()
        m = scene_manager.new()
        a = fake_scene()
        b = fake_scene()
        m:register("a", a)
        m:register("b", b)
    end)

    it("starts with no active scene", function()
        local id, scene = m:active()
        assert.is_nil(id)
        assert.is_nil(scene)
    end)

    it("activates the registered scene on switch_to and forwards params", function()
        m:switch_to("a", { hello = "world" })
        local id, scene = m:active()
        assert.are.equal("a", id)
        assert.are.equal(a, scene)
        assert.are.equal(1, #a.events)
        assert.are.equal("enter", a.events[1].name)
        assert.is_nil(a.events[1].prev)
        assert.are.equal("world", a.events[1].params.hello)
    end)

    it("fires leave on the previous scene then enter on the next", function()
        m:switch_to("a")
        m:switch_to("b", { reason = "next" })
        assert.are.equal("leave", a.events[2].name)
        assert.are.equal("b", a.events[2].next)
        assert.are.equal("enter", b.events[1].name)
        assert.are.equal("a", b.events[1].prev)
        assert.are.equal("next", b.events[1].params.reason)
    end)

    it("re-fires enter when the same scene is targeted again", function()
        m:switch_to("a")
        m:switch_to("a", { again = true })
        assert.are.equal("enter", a.events[1].name)
        assert.are.equal("leave", a.events[2].name)
        assert.are.equal("a", a.events[2].next)
        assert.are.equal("enter", a.events[3].name)
        assert.is_true(a.events[3].params.again)
    end)

    it("dispatches lifecycle events to the active scene only", function()
        m:switch_to("a")
        m:update(0.016)
        m:draw(800, 600)
        m:mousemoved(5, 6, 1, 2)
        m:mousepressed(10, 20, 1)
        m:mousereleased(11, 21, 1)
        m:keypressed("escape") -- i18n-ok
        m:keyreleased("escape") -- i18n-ok
        m:resize(1024, 768)
        local names = {}
        for _, e in ipairs(a.events) do
            names[#names + 1] = e.name
        end
        assert.are.same({
            "enter",
            "update",
            "draw",
            "mousemoved",
            "mousepressed",
            "mousereleased",
            "keypressed",
            "keyreleased",
            "resize",
        }, names)
        assert.are.equal(0, #b.events)
    end)

    it("no-ops when an active scene lacks a callback", function()
        local minimal = {}
        m:register("min", minimal)
        m:switch_to("min")
        assert.has_no.errors(function()
            m:update(0.016)
            m:draw(640, 480)
            m:mousemoved(1, 2, 0, 0)
            m:mousepressed(0, 0, 1)
            m:mousereleased(0, 0, 1)
            m:keypressed("space") -- i18n-ok
            m:keyreleased("space") -- i18n-ok
            m:resize(640, 480)
        end)
    end)

    it("no-ops dispatch when no scene is active", function()
        assert.has_no.errors(function()
            m:update(0.016)
            m:draw(800, 600)
            m:mousemoved(0, 0, 0, 0)
            m:mousepressed(0, 0, 1)
            m:mousereleased(0, 0, 1)
            m:keypressed("escape") -- i18n-ok
            m:keyreleased("escape") -- i18n-ok
            m:resize(800, 600)
        end)
    end)

    it("rejects switch_to for an unregistered id", function()
        assert.has_error(function()
            m:switch_to("ghost")
        end)
    end)

    it("round-trips the game-active flag", function()
        assert.is_false(m:is_game_active())
        m:set_game_active(true)
        assert.is_true(m:is_game_active())
        m:set_game_active(false)
        assert.is_false(m:is_game_active())
    end)

    it("preserves the game-active flag across scene transitions", function()
        m:switch_to("a")
        m:set_game_active(true)
        m:switch_to("b")
        assert.is_true(m:is_game_active())
    end)
end)
