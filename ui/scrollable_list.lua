-- Scrollable-list helper. Owns viewport rect + content height + scroll
-- offset; provides scroll_by / page_up / page_down / on_wheel / set_offset
-- and a draw-time translate. The rendering scene is responsible for
-- drawing rows in content-space; this helper supplies the y-offset and
-- a scissor that hides anything outside the viewport.
--
-- Pure-Lua state. The only love.graphics calls live inside push_scissor
-- and translate, run by the scene around its own row draw.

local ScrollableList = {}
ScrollableList.__index = ScrollableList

local M = {}

local SCROLL_STEP = 60

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
        x = 0,
        y = 0,
        viewport_w = opts.viewport_w,
        viewport_h = opts.viewport_h,
        content_h = opts.content_h or 0,
        offset_y = 0,
    }, ScrollableList)
end

function ScrollableList:set_rect(x, y, w, h)
    self.x = x
    self.y = y
    self.viewport_w = w
    self.viewport_h = h
    self:set_offset(self.offset_y)
end

function ScrollableList:set_content_height(h)
    self.content_h = h or 0
    self:set_offset(self.offset_y)
end

function ScrollableList:max_offset()
    local m = self.content_h - self.viewport_h
    if m < 0 then
        return 0
    end
    return m
end

function ScrollableList:set_offset(value)
    self.offset_y = clamp(value or 0, 0, self:max_offset())
end

function ScrollableList:scroll_by(delta)
    self:set_offset(self.offset_y + (delta or 0))
end

function ScrollableList:on_wheel(_dx, dy)
    if not dy or dy == 0 then
        return
    end
    self:set_offset(self.offset_y - dy * SCROLL_STEP)
end

function ScrollableList:page_up()
    self:set_offset(self.offset_y - self.viewport_h)
end

function ScrollableList:page_down()
    self:set_offset(self.offset_y + self.viewport_h)
end

function ScrollableList:contains_viewport_point(px, py)
    return px >= self.x
        and px <= self.x + self.viewport_w
        and py >= self.y
        and py <= self.y + self.viewport_h
end

-- The scene wraps its row drawing in begin_draw / end_draw. begin_draw
-- pushes a translate by -offset_y and a scissor over the viewport rect;
-- end_draw pops both.
function ScrollableList:begin_draw()
    love.graphics.push()
    love.graphics.setScissor(self.x, self.y, self.viewport_w, self.viewport_h)
    love.graphics.translate(self.x, self.y - self.offset_y)
end

function ScrollableList.end_draw(_self)
    love.graphics.setScissor()
    love.graphics.pop()
end

-- Translate a viewport-coordinate (e.g. mouse position) into content
-- coordinates so the scene can hit-test row rects directly.
function ScrollableList:viewport_to_content(px, py)
    return px - self.x, py - self.y + self.offset_y
end

return M
