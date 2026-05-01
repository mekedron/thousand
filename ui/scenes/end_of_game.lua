-- Placeholder end-of-game scene. Registered today but not yet routed into
-- from gameplay; the deal-scoring task later in Phase 2 wires the in-game
-- transition. The scene exists so that route can land without re-touching
-- the manager wiring.

local i18n = require("app.i18n")
local Button = require("ui.button")
local t = i18n.t

local M = {}
M.__index = M

local BUTTON_W = 240
local BUTTON_H = 56

function M.new(manager)
    local self = setmetatable({ _manager = manager }, M)
    self._back_button = Button.new({
        id = "back_to_menu", -- i18n-ok
        label_key = "scene.end_of_game.back_to_menu",
        enabled = true,
        on_press = function()
            self._manager:set_game_active(false)
            self._manager:switch_to("menu")
        end,
    })
    self._back_button.focused = true
    return self
end

function M:enter(_prev_id, _params)
    self._back_button.focused = true
    self._back_button.hovered = false
    self._back_button.pressed = false
end

function M:draw(w, h)
    w = w or 800
    h = h or 600

    love.graphics.clear(0.05, 0.10, 0.15)

    local title_x = math.floor(w * 0.5 - 60)
    local title_y = math.floor(h * 0.25)
    local placeholder_x = math.floor(w * 0.5 - 120)
    local placeholder_y = title_y + 60

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(t("scene.end_of_game.title"), title_x, title_y)
    love.graphics.print(t("scene.end_of_game.placeholder"), placeholder_x, placeholder_y)

    self._back_button:set_rect(
        math.floor(w * 0.5 - BUTTON_W * 0.5),
        math.floor(h * 0.65),
        BUTTON_W,
        BUTTON_H
    )
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
    if key == "return" or key == "space" or key == "kpenter" or key == "escape" then -- i18n-ok
        self._back_button:activate()
    end
end

return M
