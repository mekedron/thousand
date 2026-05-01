-- Unit tests for the e2e journey driver. The driver wraps the love-mock,
-- loads main.lua against it, and exposes step / click / press_key / resize
-- plus a localised-string finder.

local journey = require("tests.e2e.support.journey")
local i18n = require("app.i18n")

describe("journey", function()
    after_each(function()
        -- Belt-and-braces: a failed test mid-journey could leave _G.love
        -- and i18n state contaminated for the next describe block.
        _G.love = nil
        i18n._reset()
    end)

    describe("start", function()
        it("returns a journey object with the expected method surface", function()
            local j = journey.start({ locale = "en" })
            assert.is_function(j.step)
            assert.is_function(j.click)
            assert.is_function(j.click_text)
            assert.is_function(j.press_key)
            assert.is_function(j.resize)
            assert.is_function(j.find_text)
            assert.is_function(j.find_localised)
            assert.is_function(j.draws)
            assert.is_function(j.screen)
            assert.is_function(j.stop)
            j:stop()
        end)

        it("activates the requested locale", function()
            local j = journey.start({ locale = "ru" })
            assert.are.equal("ru", i18n.get_locale())
            j:stop()
        end)

        it("defaults to en when no locale is given", function()
            local j = journey.start({})
            assert.are.equal("en", i18n.get_locale())
            j:stop()
        end)

        it("resets i18n state on each start so locale leakage is impossible", function()
            local j1 = journey.start({ locale = "ru" })
            j1:stop()
            local j2 = journey.start({ locale = "en" })
            assert.are.equal("en", i18n.get_locale())
            j2:stop()
        end)

        it("installs the mock at _G.love during the journey", function()
            assert.is_nil(_G.love)
            local j = journey.start({})
            assert.is_table(_G.love)
            j:stop()
        end)
    end)

    describe("step", function()
        it("dispatches love.update then love.draw in that order", function()
            local order = {}
            local j = journey.start({})
            -- main.lua only sets love.draw; inject update to observe order.
            local original_draw = _G.love.draw
            _G.love.update = function(dt)
                order[#order + 1] = { "update", dt }
            end
            _G.love.draw = function()
                order[#order + 1] = { "draw" }
                original_draw()
            end
            j:step(0.5)
            assert.are.equal("update", order[1][1])
            assert.are.equal(0.5, order[1][2])
            assert.are.equal("draw", order[2][1])
            j:stop()
        end)

        it("supplies a default dt when none is given", function()
            local seen
            local j = journey.start({})
            _G.love.update = function(dt)
                seen = dt
            end
            j:step()
            assert.is_number(seen)
            j:stop()
        end)
    end)

    describe("click", function()
        it("dispatches mousepressed then mousereleased with x, y, button=1", function()
            local events = {}
            local j = journey.start({})
            _G.love.mousepressed = function(x, y, btn)
                events[#events + 1] = { "pressed", x, y, btn }
            end
            _G.love.mousereleased = function(x, y, btn)
                events[#events + 1] = { "released", x, y, btn }
            end
            j:click(640, 360)
            assert.are.same({ "pressed", 640, 360, 1 }, events[1])
            assert.are.same({ "released", 640, 360, 1 }, events[2])
            j:stop()
        end)

        it("respects an explicit button arg", function()
            local seen
            local j = journey.start({})
            _G.love.mousepressed = function(_, _, btn)
                seen = btn
            end
            j:click(0, 0, 2)
            assert.are.equal(2, seen)
            j:stop()
        end)
    end)

    describe("press_key", function()
        it("dispatches keypressed then keyreleased", function()
            local events = {}
            local j = journey.start({})
            _G.love.keypressed = function(k)
                events[#events + 1] = { "pressed", k }
            end
            _G.love.keyreleased = function(k)
                events[#events + 1] = { "released", k }
            end
            j:press_key("escape")
            assert.are.same({ "pressed", "escape" }, events[1])
            assert.are.same({ "released", "escape" }, events[2])
            j:stop()
        end)
    end)

    describe("resize", function()
        it("dispatches love.resize with the new dimensions", function()
            local seen
            local j = journey.start({})
            _G.love.resize = function(w, h)
                seen = { w, h }
            end
            j:resize(1024, 768)
            assert.are.same({ 1024, 768 }, seen)
            j:stop()
        end)
    end)

    describe("find_localised", function()
        it("resolves a key in the active locale", function()
            local j = journey.start({ locale = "en" })
            assert.are.equal("New Game", j:find_localised("menu.new_game"))
            j:stop()
        end)

        it("returns the bare key when missing in both active and en", function()
            local j = journey.start({ locale = "en" })
            assert.are.equal("does.not.exist", j:find_localised("does.not.exist"))
            j:stop()
        end)

        it("interpolates params", function()
            local j = journey.start({ locale = "en" })
            assert.are.equal(
                "Welcome, Bob!",
                j:find_localised("greeting.welcome", { name = "Bob" })
            )
            j:stop()
        end)
    end)

    describe("module caching defeat", function()
        it("two consecutive starts bind callbacks to the current mock", function()
            local j1 = journey.start({})
            j1:step()
            local first_count = #j1:draws()
            assert.is_true(first_count > 0, "first journey should record at least one draw op")
            j1:stop()

            local j2 = journey.start({})
            -- Fresh mock — recording must start empty.
            assert.are.equal(0, #j2:draws())
            j2:step()
            assert.is_true(#j2:draws() > 0, "second journey should record into its own mock")
            j2:stop()
        end)
    end)

    describe("screen()", function()
        it("returns a flat summary including the latest clear color", function()
            local j = journey.start({})
            j:step()
            local s = j:screen()
            assert.is_not_nil(s.clear)
            assert.is_table(s.texts)
            assert.is_table(s.rectangles)
            j:stop()
        end)
    end)

    describe("stop", function()
        it("restores _G.love to nil after start replaced it", function()
            assert.is_nil(_G.love)
            local j = journey.start({})
            assert.is_table(_G.love)
            j:stop()
            assert.is_nil(_G.love)
        end)

        it("is idempotent", function()
            local j = journey.start({})
            j:stop()
            assert.has_no.errors(function()
                j:stop()
            end)
        end)
    end)
end)
