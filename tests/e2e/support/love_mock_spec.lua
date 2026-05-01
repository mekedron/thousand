-- Unit tests for the e2e love-mock module. The mock fakes the LÖVE 11.x
-- API surface that scenes and main.lua actually call so journey tests
-- can drive `main.lua` under busted with no Love2D runtime.

local love_mock = require("tests.e2e.support.love_mock")

local function near(actual, expected, eps)
    return math.abs(actual - expected) < (eps or 1e-6)
end

describe("love_mock", function()
    describe("construction", function()
        it("returns a mock with the love namespaces scenes will call", function()
            local mock = love_mock.new()
            assert.is_table(mock.graphics)
            assert.is_table(mock.keyboard)
            assert.is_table(mock.mouse)
            assert.is_table(mock.timer)
            assert.is_table(mock.window)
            assert.is_table(mock.event)
            assert.is_table(mock.filesystem)
        end)

        it("uses default window dimensions when no opts are given", function()
            local mock = love_mock.new()
            local w, h = mock.window.getDimensions()
            assert.are.equal(800, w)
            assert.are.equal(600, h)
        end)

        it("respects width and height opts", function()
            local mock = love_mock.new({ width = 1280, height = 720 })
            local w, h = mock.window.getDimensions()
            assert.are.equal(1280, w)
            assert.are.equal(720, h)
        end)
    end)

    describe("install / restore", function()
        it("replaces _G.love and restores the prior global", function()
            local prior = _G.love
            local mock = love_mock.new()
            mock:install()
            assert.are.equal(mock, _G.love)
            mock:restore()
            assert.are.equal(prior, _G.love)
        end)

        it("restore is idempotent", function()
            local mock = love_mock.new()
            mock:install()
            mock:restore()
            assert.has_no.errors(function()
                mock:restore()
            end)
        end)

        it("calling restore without install is a no-op", function()
            local mock = love_mock.new()
            assert.has_no.errors(function()
                mock:restore()
            end)
        end)
    end)

    describe("dispatch", function()
        local mock
        before_each(function()
            mock = love_mock.new()
            mock:install()
        end)
        after_each(function()
            mock:restore()
        end)

        it("calls a defined love.<event> callback", function()
            local seen = false
            _G.love.draw = function()
                seen = true
            end
            mock:dispatch("draw")
            assert.is_true(seen)
        end)

        it("is a no-op when the event is not bound", function()
            assert.has_no.errors(function()
                mock:dispatch("update", 0.016)
            end)
        end)

        it("forwards extra args to the callback", function()
            local captured
            _G.love.mousepressed = function(x, y, btn)
                captured = { x, y, btn }
            end
            mock:dispatch("mousepressed", 100, 200, 1)
            assert.are.same({ 100, 200, 1 }, captured)
        end)
    end)

    describe("graphics recording", function()
        local mock
        before_each(function()
            mock = love_mock.new()
        end)

        it("records clear with a 4-tuple color and default alpha 1", function()
            mock.graphics.clear(0.07, 0.18, 0.10)
            local rec = mock.graphics.recording()
            assert.are.equal(1, #rec)
            assert.are.equal("clear", rec[1].op)
            assert.is_true(near(rec[1].color[1], 0.07))
            assert.is_true(near(rec[1].color[2], 0.18))
            assert.is_true(near(rec[1].color[3], 0.10))
            assert.is_true(near(rec[1].color[4], 1))
        end)

        it("records clear with explicit alpha", function()
            mock.graphics.clear(0.5, 0.5, 0.5, 0.25)
            local rec = mock.graphics.recording()
            assert.is_true(near(rec[1].color[4], 0.25))
        end)

        it("records setColor and reads it back via getColor", function()
            mock.graphics.setColor(0.5, 0.6, 0.7, 0.8)
            local r, g, b, a = mock.graphics.getColor()
            assert.is_true(near(r, 0.5))
            assert.is_true(near(g, 0.6))
            assert.is_true(near(b, 0.7))
            assert.is_true(near(a, 0.8))
            assert.are.equal("setColor", mock.graphics.recording()[1].op)
        end)

        it("records print as a normalised text op with x and y", function()
            mock.graphics.print("hello", 10, 20)
            local op = mock.graphics.recording()[1]
            assert.are.equal("text", op.op)
            assert.are.equal("hello", op.text)
            assert.are.equal(10, op.x)
            assert.are.equal(20, op.y)
        end)

        it("records printf under the same text op shape with limit and align", function()
            mock.graphics.printf("hi", 5, 5, 200, "left")
            local op = mock.graphics.recording()[1]
            assert.are.equal("text", op.op)
            assert.are.equal("hi", op.text)
            assert.are.equal(5, op.x)
            assert.are.equal(5, op.y)
            assert.are.equal(200, op.limit)
            assert.are.equal("left", op.align)
        end)

        it("records rectangle with mode and bounds", function()
            mock.graphics.rectangle("fill", 1, 2, 30, 40)
            local op = mock.graphics.recording()[1]
            assert.are.equal("rectangle", op.op)
            assert.are.equal("fill", op.mode)
            assert.are.equal(1, op.x)
            assert.are.equal(2, op.y)
            assert.are.equal(30, op.w)
            assert.are.equal(40, op.h)
        end)

        it("clear_recording empties the buffer in place", function()
            mock.graphics.clear(0, 0, 0)
            mock.graphics.print("x", 0, 0)
            local rec = mock.graphics.recording()
            assert.are.equal(2, #rec)
            mock.graphics.clear_recording()
            assert.are.equal(0, #mock.graphics.recording())
            -- Subsequent recording lands on the same buffer.
            mock.graphics.clear(1, 1, 1)
            assert.are.equal(1, #mock.graphics.recording())
        end)
    end)

    describe("transform stack", function()
        local mock
        before_each(function()
            mock = love_mock.new()
        end)

        it("translate offsets subsequent print x and y", function()
            mock.graphics.translate(100, 200)
            mock.graphics.print("x", 5, 5)
            local op = mock.graphics.recording()[1]
            assert.are.equal(105, op.x)
            assert.are.equal(205, op.y)
        end)

        it("push isolates further translates and pop reverts", function()
            mock.graphics.translate(10, 0)
            mock.graphics.push()
            mock.graphics.translate(100, 0)
            mock.graphics.print("inner", 0, 0)
            mock.graphics.pop()
            mock.graphics.print("outer", 0, 0)
            local rec = mock.graphics.recording()
            assert.are.equal(110, rec[1].x)
            assert.are.equal(10, rec[2].x)
        end)

        it("translate offsets rectangle x and y as well", function()
            mock.graphics.translate(50, 60)
            mock.graphics.rectangle("fill", 1, 1, 10, 10)
            local op = mock.graphics.recording()[1]
            assert.are.equal(51, op.x)
            assert.are.equal(61, op.y)
        end)

        it("pop on the empty (root) stack errors with a clear message", function()
            assert.has_error(function()
                mock.graphics.pop()
            end)
        end)

        it("scale, rotate and setMatrix raise an unimplemented diagnostic", function()
            assert.has_error(function()
                mock.graphics.scale(2)
            end)
            assert.has_error(function()
                mock.graphics.rotate(1)
            end)
            assert.has_error(function()
                mock.graphics.setMatrix()
            end)
        end)
    end)

    describe("predicates", function()
        local mock
        before_each(function()
            mock = love_mock.new()
        end)

        it("was_clear_called returns true when the recorded color matches", function()
            mock.graphics.clear(0.07, 0.18, 0.10)
            assert.is_true(mock.graphics.was_clear_called({ 0.07, 0.18, 0.10 }))
        end)

        it("was_clear_called returns false when no clear was recorded", function()
            assert.is_false(mock.graphics.was_clear_called({ 0.07, 0.18, 0.10 }))
        end)

        it("was_clear_called returns true on any clear when no expected color", function()
            mock.graphics.clear(1, 1, 1)
            assert.is_true(mock.graphics.was_clear_called())
        end)

        it("was_text_drawn matches via substring", function()
            mock.graphics.print("Welcome to Thousand", 0, 0)
            assert.is_true(mock.graphics.was_text_drawn("Welcome"))
            assert.is_true(mock.graphics.was_text_drawn("Thousand"))
            assert.is_false(mock.graphics.was_text_drawn("Banana"))
        end)

        it("find_text returns the recorded op or nil", function()
            mock.graphics.print("New Game", 100, 200)
            local op = mock.graphics.find_text("New Game")
            assert.is_table(op)
            assert.are.equal(100, op.x)
            assert.are.equal(200, op.y)
            assert.is_nil(mock.graphics.find_text("missing"))
        end)
    end)

    describe("permissive __index fallback for unstubbed APIs", function()
        local mock
        before_each(function()
            mock = love_mock.new()
        end)

        it("records unstubbed graphics calls without crashing", function()
            mock.graphics.setBlendMode("alpha")
            local op = mock.graphics.recording()[1]
            assert.are.equal("unstubbed", op.op)
            assert.are.equal("graphics.setBlendMode", op.api)
        end)

        it("counts unstubbed calls per API", function()
            mock.graphics.setBlendMode("alpha")
            mock.graphics.setBlendMode("multiply")
            assert.are.equal(2, mock.graphics.unstubbed_count("setBlendMode"))
            assert.are.equal(0, mock.graphics.unstubbed_count("nope"))
        end)

        it("captures positional args verbatim", function()
            mock.graphics.someCall(1, "two", true)
            local op = mock.graphics.recording()[1]
            assert.are.same({ 1, "two", true }, op.args)
        end)
    end)
end)
