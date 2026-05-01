-- End-of-game scene. Renders the winner banner and the final scoreline of
-- a finished session. The deal-scoring task later in Phase 2 will be the
-- one to actually transition the table here automatically; today the
-- scene is reachable through the journey harness with a finished session
-- injected into the manager (used by the e2e end-of-game render journey).
--
-- The scene reads its data either from `params.view_model` (when the
-- table scene routes here with one in hand) or from
-- `view_model.from_session(manager:session())` if the manager still
-- holds the finished session. Either way "Back to Menu" clears the
-- session so the menu's Continue button greys out again.

local i18n = require("app.i18n")
local Button = require("ui.button")
local FocusGroup = require("ui.focus_group")
local view_model = require("app.table_view_model")
local t = i18n.t

local M = {}
M.__index = M

local BUTTON_W = 240
local BUTTON_H = 56
local SCORE_GAP = 80

function M.new(manager)
    local self = setmetatable({ _manager = manager, _view_model = nil }, M)
    self._back_button = Button.new({
        id = "back_to_menu", -- i18n-ok
        label_key = "scene.end_of_game.back_to_menu",
        enabled = true,
        on_press = function()
            self._manager:clear_session()
            self._manager:switch_to("menu")
        end,
    })
    self._focus = FocusGroup.new({ self._back_button })
    return self
end

function M:enter(_prev_id, params)
    self._back_button.hovered = false
    self._back_button.pressed = false
    -- Focus-on-Tab convention: no focus ring on entry. The user surfaces
    -- it with a Tab press.
    self._focus:clear()
    if params and params.view_model then
        self._view_model = params.view_model
    else
        local session = self._manager.session and self._manager:session() or nil
        if session then
            self._view_model = view_model.from_session(session)
        else
            self._view_model = nil
        end
    end
end

local function draw_winner(view, w, h)
    local label
    if view and view.winner then
        label = t("scene.end_of_game.winner", { n = view.winner })
    else
        label = t("scene.end_of_game.placeholder")
    end
    local x = math.floor(w * 0.5 - 80)
    local y = math.floor(h * 0.30)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(label, x, y)
    return y
end

local function draw_scores(view, w, y)
    if not view or not view.scoreboard or #view.scoreboard == 0 then
        return
    end
    love.graphics.setColor(0.85, 0.85, 0.85, 1)
    local title = t("scene.end_of_game.scores_title")
    love.graphics.print(title, math.floor(w * 0.5 - 60), y + 28)

    local total_w = (#view.scoreboard - 1) * SCORE_GAP
    local start_x = math.floor(w * 0.5 - total_w * 0.5)
    local row_y = y + 56
    for i, entry in ipairs(view.scoreboard) do
        local seat_label
        if i == 1 then
            seat_label = t("scene.table.player_label.you")
        else
            seat_label = t("scene.table.player_label.other", { n = i })
        end
        local cx = start_x + (i - 1) * SCORE_GAP
        if entry.is_winner then
            love.graphics.setColor(1, 0.95, 0.55, 1)
        else
            love.graphics.setColor(0.85, 0.85, 0.85, 1)
        end
        love.graphics.print(seat_label, cx - 24, row_y)
        love.graphics.print(tostring(entry.total), cx - 12, row_y + 22)
    end
end

function M:draw(w, h)
    w = w or 800
    h = h or 600

    love.graphics.clear(0.05, 0.10, 0.15)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(
        t("scene.end_of_game.title"),
        math.floor(w * 0.5 - 60),
        math.floor(h * 0.18)
    )

    local winner_y = draw_winner(self._view_model, w, h)
    draw_scores(self._view_model, w, winner_y)

    self._back_button:set_rect(
        math.floor(w * 0.5 - BUTTON_W * 0.5),
        math.floor(h * 0.78),
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

local function shift_held()
    if not (love.keyboard and love.keyboard.isDown) then
        return false
    end
    return love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") -- i18n-ok
end

function M:keypressed(key)
    if key == "tab" then -- i18n-ok
        self._focus:advance(shift_held() and -1 or 1)
    elseif key == "down" or key == "right" then -- i18n-ok
        self._focus:advance(1)
    elseif key == "up" or key == "left" then -- i18n-ok
        self._focus:advance(-1)
    elseif key == "return" or key == "space" or key == "kpenter" or key == "escape" then -- i18n-ok
        -- The Back-to-Menu button is the only action on this scene, so
        -- Enter / Space / Esc all activate it regardless of focus state.
        self._back_button:activate()
    end
end

return M
