-- Pure-Lua mock of the LÖVE 11.x global API surface used by Thousand
-- scenes. Lets journey tests run under busted with no Love2D runtime.
--
-- Usage:
--   local love_mock = require("tests.e2e.support.love_mock")
--   local mock = love_mock.new({ width = 1280, height = 720 })
--   mock:install()                     -- replaces _G.love
--   require("main")                    -- binds love.load / love.draw
--   mock:dispatch("load")
--   mock:dispatch("draw")
--   for _, op in ipairs(mock.graphics.recording()) do ... end
--   mock:restore()                     -- restores the prior global
--
-- Design notes
-- ============
-- Top-level fields on the mock (load, draw, update, mousepressed, ...) are
-- left nil so dispatch() can detect bound vs. unbound callbacks. Namespace
-- tables (graphics, keyboard, ...) install a permissive __index fallback
-- so a Phase 2 scene that calls an unstubbed API records a diagnostic op
-- and keeps running, instead of crashing the journey.
--
-- The graphics namespace tracks a translate-only transform stack so that
-- print / printf / rectangle ops record positions in screen-space. scale,
-- rotate and setMatrix are intentionally raised as errors today: the
-- harness will surface them the moment a scene needs them, and we add the
-- math at that point rather than guess what mode (LÖVE 2D matrix? our own
-- composition order?) is correct. Phase 2 menu scenes do not need them.

local M = {}

-- Shallow copy used to snapshot color tables at draw time so a scene that
-- mutates its own color table after calling setColor does not retroactively
-- rewrite history.
local function shallow_copy(t)
    if type(t) ~= "table" then
        return t
    end
    local out = {}
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end

-- Normalise (r, g, b[, a]) and ({r, g, b[, a]}) into {r, g, b, a}.
local function color_args(...)
    local first = select(1, ...)
    if type(first) == "table" then
        return { first[1] or 0, first[2] or 0, first[3] or 0, first[4] or 1 }
    end
    local r, g, b, a = ...
    return { r or 0, g or 0, b or 0, a or 1 }
end

local function near(a, b)
    return math.abs(a - b) < 1e-6
end

local function expected_rgb(expected)
    return expected[1] or expected.r or 0,
        expected[2] or expected.g or 0,
        expected[3] or expected.b or 0
end

-- Graphics namespace ---------------------------------------------------

local function new_graphics(get_dims)
    local recording = {}
    local color = { 1, 1, 1, 1 }
    local stack = { { x = 0, y = 0 } }
    local unstubbed = {}

    local g = {}

    function g.getWidth()
        local w, _ = get_dims()
        return w
    end

    function g.getHeight()
        local _, h = get_dims()
        return h
    end

    function g.getDimensions()
        return get_dims()
    end

    local function top()
        return stack[#stack]
    end

    local function record(op)
        recording[#recording + 1] = op
    end

    function g.clear(...)
        record({ op = "clear", color = color_args(...) })
    end

    function g.setColor(...)
        color = color_args(...)
        record({ op = "setColor", color = shallow_copy(color) })
    end

    function g.getColor()
        return color[1], color[2], color[3], color[4]
    end

    function g.print(text, x, y)
        local t = top()
        record({
            op = "text",
            text = tostring(text),
            x = (x or 0) + t.x,
            y = (y or 0) + t.y,
        })
    end

    function g.printf(text, x, y, limit, align)
        local t = top()
        record({
            op = "text",
            text = tostring(text),
            x = (x or 0) + t.x,
            y = (y or 0) + t.y,
            limit = limit,
            align = align,
        })
    end

    function g.rectangle(mode, x, y, w, h)
        local t = top()
        record({
            op = "rectangle",
            mode = mode,
            x = (x or 0) + t.x,
            y = (y or 0) + t.y,
            w = w or 0,
            h = h or 0,
        })
    end

    function g.push()
        local t = top()
        stack[#stack + 1] = { x = t.x, y = t.y }
    end

    function g.pop()
        if #stack == 1 then
            error("love.graphics.pop with empty (root) transform stack", 2)
        end
        stack[#stack] = nil
    end

    function g.translate(dx, dy)
        local t = top()
        t.x = t.x + (dx or 0)
        t.y = t.y + (dy or 0)
    end

    function g.scale()
        error("love.graphics.scale is unimplemented in the e2e harness", 2)
    end

    function g.rotate()
        error("love.graphics.rotate is unimplemented in the e2e harness", 2)
    end

    function g.setMatrix()
        error("love.graphics.setMatrix is unimplemented in the e2e harness", 2)
    end

    function g.recording()
        return recording
    end

    function g.clear_recording()
        for i = #recording, 1, -1 do
            recording[i] = nil
        end
    end

    function g.was_clear_called(expected)
        for _, op in ipairs(recording) do
            if op.op == "clear" then
                if expected == nil then
                    return true
                end
                local er, eg, eb = expected_rgb(expected)
                if near(op.color[1], er) and near(op.color[2], eg) and near(op.color[3], eb) then
                    return true
                end
            end
        end
        return false
    end

    function g.was_text_drawn(needle)
        for _, op in ipairs(recording) do
            if op.op == "text" and op.text:find(needle, 1, true) then
                return true
            end
        end
        return false
    end

    function g.find_text(needle)
        for _, op in ipairs(recording) do
            if op.op == "text" and op.text:find(needle, 1, true) then
                return op
            end
        end
        return nil
    end

    function g.unstubbed_count(name)
        return unstubbed[name] or 0
    end

    setmetatable(g, {
        __index = function(_, key)
            return function(...)
                unstubbed[key] = (unstubbed[key] or 0) + 1
                record({
                    op = "unstubbed",
                    api = "graphics." .. key,
                    args = { ... },
                })
            end
        end,
    })

    return g
end

-- Keyboard / mouse / timer / window / event / filesystem ---------------
--
-- Minimal stubs. Each namespace gets a permissive __index fallback so an
-- unstubbed call records into a shared diagnostics table on the namespace
-- without crashing the journey. None of these are interesting to inspect
-- in Phase 2's first journey, but they are present so scenes that call
-- love.timer.getDelta() or love.window.getDimensions() do not blow up.

local function permissive(t)
    setmetatable(t, {
        __index = function()
            return function() end
        end,
    })
    return t
end

local function new_keyboard()
    return permissive({
        isDown = function()
            return false
        end,
    })
end

local function new_mouse()
    return permissive({
        getPosition = function()
            return 0, 0
        end,
        isDown = function()
            return false
        end,
    })
end

local function new_timer()
    local clock = 0
    return permissive({
        getDelta = function()
            return 0.016
        end,
        getTime = function()
            return clock
        end,
        step = function()
            clock = clock + 0.016
        end,
    })
end

local function new_window(get_dims, set_dims)
    return permissive({
        getDimensions = function()
            return get_dims()
        end,
        getWidth = function()
            local w, _ = get_dims()
            return w
        end,
        getHeight = function()
            local _, h = get_dims()
            return h
        end,
        setMode = function(new_w, new_h)
            set_dims(new_w, new_h)
            return true
        end,
    })
end

local function new_event()
    return permissive({
        quit = function() end,
        push = function() end,
    })
end

local function new_filesystem()
    return permissive({
        getSaveDirectory = function()
            return "/tmp/thousand-test"
        end,
        read = function()
            return nil, "filesystem unstubbed in e2e harness"
        end,
        write = function()
            return false, "filesystem unstubbed in e2e harness"
        end,
        getInfo = function()
            return nil
        end,
    })
end

-- Mock object ----------------------------------------------------------

local Mock = {}
Mock.__index = Mock

function M.new(opts)
    opts = opts or {}
    local w, h = opts.width or 800, opts.height or 600
    local function get_dims()
        return w, h
    end
    local function set_dims(new_w, new_h)
        w, h = new_w, new_h
    end

    local self = setmetatable({}, Mock)
    self.graphics = new_graphics(get_dims)
    self.keyboard = new_keyboard()
    self.mouse = new_mouse()
    self.timer = new_timer()
    self.window = new_window(get_dims, set_dims)
    self.event = new_event()
    self.filesystem = new_filesystem()
    self._installed = false
    self._prior_love = nil
    self._set_dims = set_dims
    return self
end

function Mock:install()
    if self._installed then
        return
    end
    self._prior_love = _G.love
    _G.love = self
    self._installed = true
end

function Mock:restore()
    if not self._installed then
        return
    end
    _G.love = self._prior_love
    self._prior_love = nil
    self._installed = false
end

function Mock:dispatch(event, ...)
    if event == "resize" then
        local nw, nh = ...
        if nw and nh then
            self._set_dims(nw, nh)
        end
    end
    local fn = rawget(self, event)
    if type(fn) == "function" then
        return fn(...)
    end
    -- Callback not bound — silent no-op, which mirrors how LÖVE itself
    -- treats missing handlers.
end

return M
