-- Number-stepper widget. A label-flanked [-][value][+] row used by the
-- template editor for free-range numeric fields with min/max bounds.
-- Discrete enums (talon.size, allowed sets) use ui.toggle instead.
--
-- Click the minus button to decrement by step; click plus to increment.
-- Disabled steppers ignore both pointer and keyboard activation.

local NumberStepper = {}
NumberStepper.__index = NumberStepper

local M = {}

local function noop() end

local BUTTON_W = 56

local function clamp(v, lo, hi)
    if v < lo then
        return lo
    elseif v > hi then
        return hi
    end
    return v
end

function M.new(opts)
    return setmetatable({
        id = opts.id,
        current = opts.current,
        step = opts.step or 1,
        min = opts.min,
        max = opts.max,
        enabled = opts.enabled ~= false,
        on_change = opts.on_change or noop,
        x = 0,
        y = 0,
        w = 0,
        h = 0,
        pressed_button = nil,
        focused = false,
    }, NumberStepper)
end

function NumberStepper:set_rect(x, y, w, h)
    self.x, self.y, self.w, self.h = x, y, w, h
end

function NumberStepper:set_value(value)
    if type(value) ~= "number" then
        return
    end
    self.current = clamp(value, self.min, self.max)
end

function NumberStepper:set_enabled(value)
    self.enabled = value and true or false
    if not self.enabled then
        self.pressed_button = nil
    end
end

function NumberStepper:contains(px, py)
    return px >= self.x and px <= self.x + self.w and py >= self.y and py <= self.y + self.h
end

function NumberStepper:minus_rect()
    return { x = self.x, y = self.y, w = BUTTON_W, h = self.h }
end

function NumberStepper:plus_rect()
    return { x = self.x + self.w - BUTTON_W, y = self.y, w = BUTTON_W, h = self.h }
end

function NumberStepper:value_rect()
    return {
        x = self.x + BUTTON_W,
        y = self.y,
        w = self.w - 2 * BUTTON_W,
        h = self.h,
    }
end

local function rect_contains(r, px, py)
    return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

local function button_at(self, px, py)
    if rect_contains(self:minus_rect(), px, py) then
        return "minus"
    elseif rect_contains(self:plus_rect(), px, py) then
        return "plus"
    end
    return nil
end

function NumberStepper.on_mousemoved(_self, _x, _y) end

function NumberStepper:on_mousepressed(x, y, button)
    if button ~= 1 or not self.enabled then
        return false
    end
    local which = button_at(self, x, y)
    if not which then
        return false
    end
    self.pressed_button = which
    return true
end

function NumberStepper:_apply_step(direction)
    local target = self.current + direction * self.step
    target = clamp(target, self.min, self.max)
    if target == self.current then
        return false
    end
    self.current = target
    self.on_change(target)
    return true
end

function NumberStepper:on_mousereleased(x, y, button)
    if button ~= 1 or not self.pressed_button then
        return false
    end
    local pressed = self.pressed_button
    self.pressed_button = nil
    if not self.enabled then
        return false
    end
    local released = button_at(self, x, y)
    if released ~= pressed then
        return false
    end
    if pressed == "minus" then
        return self:_apply_step(-1)
    else
        return self:_apply_step(1)
    end
end

function NumberStepper:activate()
    if not self.enabled then
        return
    end
    self:_apply_step(1)
end

local function bg_color(self, role)
    if not self.enabled then
        return 0.18, 0.20, 0.18, 1
    end
    if self.pressed_button == role then
        return 0.14, 0.30, 0.18, 1
    end
    return 0.20, 0.36, 0.24, 1
end

function NumberStepper:draw()
    local m = self:minus_rect()
    local p = self:plus_rect()
    local v = self:value_rect()

    love.graphics.setColor(bg_color(self, "minus"))
    love.graphics.rectangle("fill", m.x, m.y, m.w, m.h)
    love.graphics.setColor(0.10, 0.14, 0.10, 1)
    love.graphics.rectangle("line", m.x, m.y, m.w, m.h)

    love.graphics.setColor(bg_color(self, "plus"))
    love.graphics.rectangle("fill", p.x, p.y, p.w, p.h)
    love.graphics.setColor(0.10, 0.14, 0.10, 1)
    love.graphics.rectangle("line", p.x, p.y, p.w, p.h)

    love.graphics.setColor(0.12, 0.16, 0.13, 1)
    love.graphics.rectangle("fill", v.x, v.y, v.w, v.h)
    love.graphics.setColor(0.10, 0.14, 0.10, 1)
    love.graphics.rectangle("line", v.x, v.y, v.w, v.h)

    local glyph_color = self.enabled and { 1, 1, 1, 1 } or { 0.55, 0.55, 0.55, 1 }
    -- Current-value text stays bright in the disabled state so the user
    -- can still tell *what* the read-only built-in is set to. The minus
    -- and plus glyphs stay greyed to communicate "not interactive".
    local value_color = self.enabled and { 1, 1, 1, 1 } or { 0.98, 0.92, 0.72, 1 }
    local minus = tostring("-") -- i18n-ok: glyph
    local plus = tostring("+") -- i18n-ok: glyph
    love.graphics.setColor(glyph_color)
    love.graphics.printf(minus, m.x, m.y + math.floor(m.h * 0.5) - 8, m.w, "center")
    love.graphics.printf(plus, p.x, p.y + math.floor(p.h * 0.5) - 8, p.w, "center")
    love.graphics.setColor(value_color)
    local val = tostring(self.current)
    love.graphics.printf(val, v.x, v.y + math.floor(v.h * 0.5) - 8, v.w, "center")

    -- Inset amber ring around the value when disabled — the analogue of
    -- the toggle's "current segment" marker for free-range numerics.
    if not self.enabled then
        love.graphics.setColor(0.95, 0.85, 0.30, 1)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", v.x + 2, v.y + 2, v.w - 4, v.h - 4)
        love.graphics.setLineWidth(1)
    end

    if self.focused and self.enabled then
        love.graphics.setColor(0.95, 0.95, 0.55, 1)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", self.x - 2, self.y - 2, self.w + 4, self.h + 4)
        love.graphics.setLineWidth(1)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return M
