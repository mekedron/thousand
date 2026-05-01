-- Placeholder table scene. The next Phase 2 tasks fill in actual card
-- rendering, the scoreboard, the auction UI and hot-seat input. For now
-- this scene renders the green felt, the localised "Table" header and
-- a touch-friendly Menu button that returns to the main menu.
--
-- The Menu button is the touch-parity affordance: iOS and Android have
-- no reliable physical Escape key, so a visible button must always be
-- available. Keyboard users get Escape as a shortcut to the same path.
--
-- Note: if a third in-scene modal joins this scene (the privacy hand-off
-- overlay is the next obvious one), extract a Modal helper into
-- ui/modal.lua before the second copy of inline modal state lands.

local i18n = require("app.i18n")
local Button = require("ui.button")
local layout = require("ui.layout")
local t = i18n.t

local M = {}
M.__index = M

local BACK_BTN_W = 120
local BACK_BTN_H = 48

function M.new(manager)
    local self = setmetatable({
        _manager = manager,
    }, M)
    self._back_button = Button.new({
        id = "back_to_menu", -- i18n-ok
        label_key = "scene.table.back_to_menu",
        enabled = true,
        on_press = function()
            self:_return_to_menu()
        end,
    })
    self._back_button.focused = true
    return self
end

function M:_return_to_menu()
    self._manager:switch_to("menu")
end

function M:enter(_prev_id, _params)
    self._back_button.focused = true
    self._back_button.hovered = false
    self._back_button.pressed = false
end

function M:draw(w, h)
    w = w or 800
    h = h or 600

    love.graphics.clear(0.07, 0.22, 0.12)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(t("scene.table.title"), math.floor(w * 0.5 - 30), math.floor(h * 0.12))

    love.graphics.setColor(0.85, 0.85, 0.85, 1)
    love.graphics.print(t("scene.table.escape_hint"), math.floor(w * 0.5 - 180), h - 40)

    local back_rect = layout.top_right(w, h, BACK_BTN_W, BACK_BTN_H)
    self._back_button:set_rect(back_rect.x, back_rect.y, back_rect.w, back_rect.h)
    self._back_button:draw()

    love.graphics.setColor(1, 1, 1, 1)
end

function M:mousemoved(x, y, _dx, _dy)
    self._back_button:on_mousemoved(x, y)
end

function M:mousepressed(x, y, button)
    self._back_button:on_mousepressed(x, y, button)
end

function M:mousereleased(x, y, button)
    self._back_button:on_mousereleased(x, y, button)
end

function M:keypressed(key)
    if key == "escape" then -- i18n-ok
        self:_return_to_menu()
    elseif key == "return" or key == "space" or key == "kpenter" then -- i18n-ok
        self._back_button:activate()
    end
end

return M
