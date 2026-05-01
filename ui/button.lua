-- Shared button helper. Owns the visual state (enabled / hovered / focused /
-- pressed), hit-testing, and action dispatch for one rectangular button.
-- Scenes hold an ordered list of these and pump events into them.
--
-- The four states map to four backgrounds in draw():
--   disabled — flat dim
--   pressed  — darkened
--   hovered  — brightened
--   default  — neutral
-- focused buttons get a contrasting outline so keyboard nav is visible.
--
-- Click semantics: a primary mousepressed inside an enabled button arms it
-- (pressed=true). The corresponding mousereleased fires the on_press
-- callback only if it lands inside the same button — release-outside
-- cancels, matching standard desktop button UX.

local i18n = require("app.i18n")
local t = i18n.t

local Button = {}
Button.__index = Button

local M = {}

local function noop() end

function M.new(opts)
    return setmetatable({
        id = opts.id,
        label_key = opts.label_key,
        enabled = opts.enabled ~= false,
        on_press = opts.on_press or noop,
        x = 0,
        y = 0,
        w = 0,
        h = 0,
        hovered = false,
        focused = false,
        pressed = false,
    }, Button)
end

function Button:set_rect(x, y, w, h)
    self.x, self.y, self.w, self.h = x, y, w, h
end

function Button:set_enabled(value)
    self.enabled = value and true or false
    if not self.enabled then
        self.hovered = false
        self.pressed = false
    end
end

function Button:contains(px, py)
    return px >= self.x and px <= self.x + self.w and py >= self.y and py <= self.y + self.h
end

function Button:on_mousemoved(x, y)
    self.hovered = self.enabled and self:contains(x, y) or false
end

function Button:on_mousepressed(x, y, button)
    if button ~= 1 or not self.enabled or not self:contains(x, y) then
        return false
    end
    self.pressed = true
    return true
end

function Button:on_mousereleased(x, y, button)
    if button ~= 1 or not self.pressed then
        return false
    end
    local was_pressed = self.pressed
    self.pressed = false
    if was_pressed and self.enabled and self:contains(x, y) then
        self.on_press()
        return true
    end
    return false
end

function Button:activate()
    if self.enabled then
        self.on_press()
    end
end

local function bg_color(self)
    if not self.enabled then
        return 0.18, 0.20, 0.18, 1
    elseif self.pressed then
        return 0.14, 0.30, 0.18, 1
    elseif self.hovered then
        return 0.26, 0.50, 0.32, 1
    else
        return 0.20, 0.40, 0.25, 1
    end
end

function Button:draw()
    local r, g, b, a = bg_color(self)
    love.graphics.setColor(r, g, b, a)
    love.graphics.rectangle("fill", self.x, self.y, self.w, self.h)

    if self.focused and self.enabled then
        love.graphics.setColor(0.95, 0.95, 0.55, 1)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", self.x - 2, self.y - 2, self.w + 4, self.h + 4)
        love.graphics.setLineWidth(1)
    end

    if self.enabled then
        love.graphics.setColor(1, 1, 1, 1)
    else
        love.graphics.setColor(0.55, 0.55, 0.55, 1)
    end
    love.graphics.print(t(self.label_key), self.x + 16, self.y + 18)
end

return M
