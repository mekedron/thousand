-- Segmented-toggle widget: a horizontal row of value-buttons of which
-- exactly one is "selected". Used by the template editor to render a
-- leaf-field's allowed values when the field has a finite enum or is a
-- boolean (rendered as off/on).
--
-- Click semantics mirror ui.button: a primary mousepressed inside a
-- segment arms it; the corresponding mousereleased fires on_change with
-- the new value only when it lands inside the same segment AND the
-- value is different from the current selection.
--
-- Keyboard activate (from ui.focus_group) cycles to the next allowed
-- value, wrapping at the end. Disabled toggles ignore both pointer and
-- keyboard activation.

local i18n = require("app.i18n")
local t = i18n.t

local Toggle = {}
Toggle.__index = Toggle

local M = {}

local function noop() end

local function index_of(values, target)
    for i, v in ipairs(values) do
        if v == target then
            return i
        end
    end
    return nil
end

local function copy_list(list)
    local out = {}
    for i, v in ipairs(list) do
        out[i] = v
    end
    return out
end

function M.new(opts)
    return setmetatable({
        id = opts.id,
        values = copy_list(opts.values),
        value_labels = copy_list(opts.value_labels),
        current = opts.current,
        enabled = opts.enabled ~= false,
        on_change = opts.on_change or noop,
        x = 0,
        y = 0,
        w = 0,
        h = 0,
        hovered_segment = nil,
        pressed_segment = nil,
        focused = false,
    }, Toggle)
end

function Toggle:set_rect(x, y, w, h)
    self.x, self.y, self.w, self.h = x, y, w, h
end

function Toggle:set_value(value)
    if index_of(self.values, value) then
        self.current = value
    end
end

function Toggle:set_enabled(value)
    self.enabled = value and true or false
    if not self.enabled then
        self.hovered_segment = nil
        self.pressed_segment = nil
    end
end

function Toggle:contains(px, py)
    return px >= self.x and px <= self.x + self.w and py >= self.y and py <= self.y + self.h
end

function Toggle:segment_rects()
    local n = #self.values
    if n == 0 or self.w <= 0 then
        return {}
    end
    local seg_w = math.floor(self.w / n)
    local out = {}
    for i = 1, n do
        out[i] = { x = self.x + (i - 1) * seg_w, y = self.y, w = seg_w, h = self.h }
    end
    return out
end

local function segment_at(self, px, py)
    if not self:contains(px, py) then
        return nil
    end
    for i, r in ipairs(self:segment_rects()) do
        if px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h then
            return i
        end
    end
    return nil
end

function Toggle:on_mousemoved(x, y)
    if not self.enabled then
        self.hovered_segment = nil
        return
    end
    self.hovered_segment = segment_at(self, x, y)
end

function Toggle:on_mousepressed(x, y, button)
    if button ~= 1 or not self.enabled then
        return false
    end
    local idx = segment_at(self, x, y)
    if not idx then
        return false
    end
    self.pressed_segment = idx
    return true
end

function Toggle:on_mousereleased(x, y, button)
    if button ~= 1 or not self.pressed_segment then
        return false
    end
    local pressed = self.pressed_segment
    self.pressed_segment = nil
    if not self.enabled then
        return false
    end
    local released = segment_at(self, x, y)
    if released ~= pressed then
        return false
    end
    local new_value = self.values[pressed]
    if new_value == self.current then
        return false
    end
    self.current = new_value
    self.on_change(new_value)
    return true
end

function Toggle:activate()
    if not self.enabled then
        return
    end
    local idx = index_of(self.values, self.current) or 0
    local next_idx = (idx % #self.values) + 1
    local new_value = self.values[next_idx]
    self.current = new_value
    self.on_change(new_value)
end

local function bg_color(self, segment_idx, is_selected)
    if not self.enabled then
        return 0.18, 0.20, 0.18, 1
    end
    if is_selected then
        if self.pressed_segment == segment_idx then
            return 0.18, 0.40, 0.22, 1
        end
        return 0.26, 0.55, 0.34, 1
    end
    if self.pressed_segment == segment_idx then
        return 0.14, 0.22, 0.16, 1
    end
    if self.hovered_segment == segment_idx then
        return 0.22, 0.32, 0.24, 1
    end
    return 0.16, 0.22, 0.18, 1
end

function Toggle:draw()
    local rects = self:segment_rects()
    for i, r in ipairs(rects) do
        local is_selected = self.values[i] == self.current
        local cr, cg, cb, ca = bg_color(self, i, is_selected)
        love.graphics.setColor(cr, cg, cb, ca)
        love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
        love.graphics.setColor(0.10, 0.14, 0.10, 1)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", r.x, r.y, r.w, r.h)
        if self.enabled then
            love.graphics.setColor(1, 1, 1, 1)
        else
            love.graphics.setColor(0.55, 0.55, 0.55, 1)
        end
        local label = t(self.value_labels[i])
        love.graphics.printf(label, r.x, r.y + math.floor(r.h * 0.5) - 8, r.w, "center")
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
