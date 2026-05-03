-- Main menu scene. Renders title, subtitle and four buttons (New Game,
-- Continue, Abandon Game, Quit) plus a confirm-abandon modal that the
-- Abandon button toggles. Continue and Abandon are both greyed unless
-- the manager reports a game in progress; Continue routes back into the
-- table scene with the same session, and the auto-save task later in
-- Phase 2 will broaden the "in progress" predicate to include
-- on-disk auto-saves.
--
-- Each button has hover / focus / active visual states (see ui/button.lua)
-- and the scene is fully keyboard-navigable. Focus behaviour is shared
-- with every other scene through ui/focus_group.lua: NO focus ring on
-- entry, the first Tab / arrow press surfaces it, and clicks leave focus
-- alone (focus-visible idiom). The "next" direction is any of Tab / Down
-- / Right; the "previous" direction is any of Shift+Tab / Up / Left.
-- Enter and Space activate the focused button.
--
-- Layout is recomputed each frame from the (w, h) passed into draw and
-- cached on `self` so input handlers can hit-test against the same rects
-- without re-running the math.

local i18n = require("app.i18n")
local Button = require("ui.button")
local FocusGroup = require("ui.focus_group")
local Session = require("app.session")
local auto_save = require("app.auto_save")
local app_templates = require("app.templates")
local t = i18n.t

local M = {}
M.__index = M

local BUTTON_W = 280
local BUTTON_H = 56
local BUTTON_GAP = 12

function M.new(manager)
    local self = setmetatable({
        _manager = manager,
        _modal = nil,
    }, M)
    self:_build_buttons()
    return self
end

function M:_build_buttons()
    -- The literal pairs below trip the i18n CI heuristic only because two
    -- adjacent string literals on one line look like a whitespace-bearing
    -- string to its regex; the strings themselves are ids and i18n keys.
    self._buttons = {
        Button.new({
            id = "single_player", -- i18n-ok
            label_key = "scene.menu.single_player",
            enabled = true,
            on_press = function()
                -- One-click single-player: seat 1 is human, every other
                -- seat is a bot under the active template's player count.
                -- Mirrors the New Game picker's default composition so
                -- the most common path skips the picker entirely.
                auto_save.clear()
                local config = app_templates.resolve_active_config()
                local seat_kinds = { "human" }
                for _ = 2, config.players.count do
                    seat_kinds[#seat_kinds + 1] = "bot"
                end
                self._manager:set_session(Session.new({
                    config = config,
                    seat_kinds = seat_kinds,
                }))
                self._manager:switch_to("table", { seat_kinds = seat_kinds })
            end,
        }),
        Button.new({
            id = "new_game", -- i18n-ok
            label_key = "scene.menu.new_game",
            enabled = true,
            on_press = function()
                -- Phase 4.2: New Game routes through the picker so the
                -- player can place humans on any seat (mixed comps,
                -- spectator-mode all-bot, etc.). The picker handles
                -- auto_save.clear and Session.new itself.
                self._manager:switch_to("new_game")
            end,
        }),
        Button.new({
            id = "continue", -- i18n-ok
            label_key = "scene.menu.continue",
            enabled = self._manager:is_game_active(),
            on_press = function()
                if self._manager:is_game_active() then
                    self._manager:switch_to("table")
                end
            end,
        }),
        Button.new({
            id = "abandon", -- i18n-ok
            label_key = "scene.menu.abandon",
            enabled = self._manager:is_game_active(),
            on_press = function()
                self:_open_modal()
            end,
        }),
        Button.new({
            id = "templates", -- i18n-ok
            label_key = "scene.menu.templates",
            enabled = true,
            on_press = function()
                self._manager:switch_to("template_picker")
            end,
        }),
        Button.new({
            id = "settings", -- i18n-ok
            label_key = "scene.menu.settings",
            enabled = true,
            on_press = function()
                self._manager:switch_to("settings")
            end,
        }),
        Button.new({
            id = "quit", -- i18n-ok
            label_key = "scene.menu.quit",
            enabled = true,
            on_press = function()
                if love.event and love.event.quit then
                    love.event.quit()
                end
            end,
        }),
    }
    self._modal_buttons = {
        Button.new({
            id = "yes", -- i18n-ok
            label_key = "scene.menu.confirm_abandon.yes",
            enabled = true,
            on_press = function()
                self._manager:clear_session()
                auto_save.clear()
                self:_close_modal()
                self:_refresh_enabled_states()
            end,
        }),
        Button.new({
            id = "no", -- i18n-ok
            label_key = "scene.menu.confirm_abandon.no",
            enabled = true,
            on_press = function()
                self:_close_modal()
            end,
        }),
    }
    self._focus = FocusGroup.new(self._buttons)
    self._modal_focus = FocusGroup.new(self._modal_buttons)
end

function M:_refresh_enabled_states()
    local active = self._manager:is_game_active()
    for _, b in ipairs(self._buttons) do
        if b.id == "abandon" or b.id == "continue" then -- i18n-ok
            b:set_enabled(active)
        end
    end
    -- If keyboard nav had landed on a button that just got disabled, drop
    -- focus rather than auto-advance — focus-visible should only return
    -- when the user nav's again.
    local focused = self._focus:focused()
    if focused and not focused.enabled then
        self._focus:clear()
    end
end

function M:_open_modal()
    self._modal = "confirm_abandon" -- i18n-ok
    -- Modal opens with explicit focus on Cancel so an inadvertent Enter
    -- press dismisses the modal rather than abandoning the game. This
    -- IS a deliberate focus-on-open, distinct from the entry-time
    -- focus-on-Tab convention.
    self._modal_focus:focus(self._modal_buttons[2])
end

function M:_close_modal()
    self._modal = nil
    self._modal_focus:clear()
end

function M:enter(_prev_id, _params)
    self:_close_modal()
    self:_refresh_enabled_states()
    -- Drop any leftover focus from a previous visit so the menu opens
    -- without a yellow focus ring; the user has not navigated yet.
    self._focus:clear()
end

local function compute_layout(self, w, h)
    local n = #self._buttons
    local total_h = n * BUTTON_H + (n - 1) * BUTTON_GAP
    local start_y = math.floor(h * 0.5 - total_h * 0.5 + 30)
    local x = math.floor(w * 0.5 - BUTTON_W * 0.5)
    for i, b in ipairs(self._buttons) do
        local y = start_y + (i - 1) * (BUTTON_H + BUTTON_GAP)
        b:set_rect(x, y, BUTTON_W, BUTTON_H)
    end

    self._title_x = math.floor(w * 0.5 - 120)
    self._title_y = math.floor(h * 0.18)
    self._subtitle_x = math.floor(w * 0.5 - 220)
    self._subtitle_y = self._title_y + 36
end

local function compute_modal_layout(self, w, h)
    local panel_w, panel_h = 480, 220
    local panel_x = math.floor(w * 0.5 - panel_w * 0.5)
    local panel_y = math.floor(h * 0.5 - panel_h * 0.5)
    self._modal_panel = { x = panel_x, y = panel_y, w = panel_w, h = panel_h }
    self._modal_prompt = { x = panel_x + 40, y = panel_y + 60 }

    local btn_w, btn_h, btn_gap = 200, 48, 24
    local total_w = btn_w * 2 + btn_gap
    local btn_y = panel_y + panel_h - btn_h - 28
    local left_x = panel_x + math.floor(panel_w * 0.5 - total_w * 0.5)

    self._modal_buttons[1]:set_rect(left_x, btn_y, btn_w, btn_h)
    self._modal_buttons[2]:set_rect(left_x + btn_w + btn_gap, btn_y, btn_w, btn_h)
end

function M:draw(w, h)
    w = w or 800
    h = h or 600

    love.graphics.clear(0.07, 0.18, 0.10)
    compute_layout(self, w, h)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(t("scene.menu.title"), self._title_x, self._title_y)
    love.graphics.print(t("scene.menu.subtitle"), self._subtitle_x, self._subtitle_y)

    for _, b in ipairs(self._buttons) do
        b:draw()
    end

    if self._modal == "confirm_abandon" then -- i18n-ok
        compute_modal_layout(self, w, h)
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 0, 0, w, h)
        love.graphics.setColor(0.12, 0.18, 0.14, 1)
        love.graphics.rectangle(
            "fill",
            self._modal_panel.x,
            self._modal_panel.y,
            self._modal_panel.w,
            self._modal_panel.h
        )
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(
            t("scene.menu.confirm_abandon.prompt"),
            self._modal_prompt.x,
            self._modal_prompt.y
        )
        for _, b in ipairs(self._modal_buttons) do
            b:draw()
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

local function active_list(self)
    if self._modal == "confirm_abandon" then -- i18n-ok
        return self._modal_buttons, self._modal_focus
    end
    return self._buttons, self._focus
end

function M:mousemoved(x, y, _dx, _dy)
    local list = active_list(self)
    for _, b in ipairs(list) do
        b:on_mousemoved(x, y)
    end
end

function M:mousepressed(x, y, button)
    local list = active_list(self)
    for _, b in ipairs(list) do
        if b:on_mousepressed(x, y, button) then
            return
        end
    end
end

function M:mousereleased(x, y, button)
    local list = active_list(self)
    for _, b in ipairs(list) do
        b:on_mousereleased(x, y, button)
    end
end

local function shift_held()
    if not (love.keyboard and love.keyboard.isDown) then
        return false
    end
    return love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") -- i18n-ok
end

function M:keypressed(key)
    local _, focus = active_list(self)
    if key == "tab" then -- i18n-ok
        focus:advance(shift_held() and -1 or 1)
    elseif key == "down" or key == "right" then -- i18n-ok
        focus:advance(1)
    elseif key == "up" or key == "left" then -- i18n-ok
        focus:advance(-1)
    elseif key == "return" or key == "space" or key == "kpenter" then -- i18n-ok
        focus:activate()
    elseif key == "escape" then -- i18n-ok
        if self._modal == "confirm_abandon" then -- i18n-ok
            self:_close_modal()
        end
    end
end

return M
