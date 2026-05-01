-- Settings scene. Phase 2 ships a single toggle (the hot-seat privacy
-- curtain) so testers can disable the between-turns overlay; Phase 4
-- will broaden this scene with locale, sound, theme and animation
-- speed entries against the same Settings module.
--
-- Each setting is rendered as one row: label + short description on
-- the left, a toggle button on the right showing the current On/Off
-- state. A persistent "Back" button at the top-right routes to the
-- menu, matching the table scene's touch back-out idiom.
--
-- Keyboard focus walks the toggles in order, then the Back button.
-- Enter / Space activates whichever is focused; Esc always routes to
-- the menu, regardless of focus.

local i18n = require("app.i18n")
local Button = require("ui.button")
local FocusGroup = require("ui.focus_group")
local settings = require("app.settings")
local t = i18n.t

local M = {}
M.__index = M

local TITLE_Y_RATIO = 0.14
local ROW_HEIGHT = 72
local ROW_LABEL_WIDTH = 360
local ROW_TOGGLE_W = 120
local ROW_TOGGLE_H = 48

local BACK_BTN_W = 120
local BACK_BTN_H = 48
local SAFE_MARGIN = 16

local TITLE_COLOR = { 1, 1, 1, 1 }
local LABEL_COLOR = { 0.92, 0.96, 0.92, 1 }
local DESC_COLOR = { 0.65, 0.78, 0.68, 1 }

function M.new(manager)
    local self = setmetatable({
        _manager = manager,
        _last_w = 0,
        _last_h = 0,
    }, M)

    self._toggle_button = Button.new({
        id = "settings_hot_seat_privacy", -- i18n-ok
        label_key = "scene.settings.toggle.on",
        enabled = true,
        on_press = function()
            self:_toggle_hot_seat_privacy()
        end,
    })

    self._back_button = Button.new({
        id = "settings_back", -- i18n-ok
        label_key = "scene.settings.back_to_menu",
        enabled = true,
        on_press = function()
            self:_return_to_menu()
        end,
    })

    self._focus = FocusGroup.new({ self._toggle_button, self._back_button })
    return self
end

function M:_return_to_menu()
    self._manager:switch_to("menu")
end

function M:_toggle_hot_seat_privacy()
    local current = settings.get("hot_seat_privacy")
    settings.set("hot_seat_privacy", not current)
    self:_sync_toggle_label()
end

local TOGGLE_LABEL_ON = "scene.settings.toggle.on" -- i18n-ok: key
local TOGGLE_LABEL_OFF = "scene.settings.toggle.off" -- i18n-ok: key

function M:_sync_toggle_label()
    local on = settings.get("hot_seat_privacy") and true or false
    self._toggle_button.label_key = on and TOGGLE_LABEL_ON or TOGGLE_LABEL_OFF
end

function M:enter(_prev_id, _params)
    self._toggle_button.hovered = false
    self._toggle_button.pressed = false
    self._back_button.hovered = false
    self._back_button.pressed = false
    self._focus:clear()
    self:_sync_toggle_label()
end

local function compute_layout(self, w, h)
    self._last_w = w
    self._last_h = h

    self._title_x = math.floor(w * 0.5)
    self._title_y = math.floor(h * TITLE_Y_RATIO)

    -- One row per setting. Phase 2 has exactly one — the hot-seat
    -- privacy toggle. Stack vertically below the title.
    local row_y = self._title_y + 64
    self._row_label_x = math.floor(w * 0.5 - (ROW_LABEL_WIDTH + ROW_TOGGLE_W) * 0.5)
    self._row_label_y = row_y + 12
    self._row_desc_y = row_y + 38

    local toggle_x = self._row_label_x + ROW_LABEL_WIDTH + 24
    local toggle_y = row_y + math.floor((ROW_HEIGHT - ROW_TOGGLE_H) * 0.5)
    self._toggle_button:set_rect(toggle_x, toggle_y, ROW_TOGGLE_W, ROW_TOGGLE_H)

    self._back_button:set_rect(w - BACK_BTN_W - SAFE_MARGIN, SAFE_MARGIN, BACK_BTN_W, BACK_BTN_H)
end

function M:_apply_focus_marks()
    local focused = self._focus:focused()
    self._toggle_button.focused = (focused == self._toggle_button)
    self._back_button.focused = (focused == self._back_button)
end

function M:draw(w, h)
    w = w or 800
    h = h or 600

    love.graphics.clear(0.07, 0.18, 0.10)
    compute_layout(self, w, h)

    love.graphics.setColor(TITLE_COLOR)
    love.graphics.printf(t("scene.settings.title"), 0, self._title_y, w, "center")

    love.graphics.setColor(LABEL_COLOR)
    love.graphics.print(
        t("scene.settings.hot_seat_privacy.label"),
        self._row_label_x,
        self._row_label_y
    )
    love.graphics.setColor(DESC_COLOR)
    love.graphics.print(
        t("scene.settings.hot_seat_privacy.description"),
        self._row_label_x,
        self._row_desc_y
    )
    love.graphics.setColor(1, 1, 1, 1)

    self:_sync_toggle_label()
    self:_apply_focus_marks()
    self._toggle_button:draw()
    self._back_button:draw()
end

local function active_buttons(self)
    return { self._toggle_button, self._back_button }
end

function M:mousemoved(x, y, _dx, _dy)
    for _, b in ipairs(active_buttons(self)) do
        b:on_mousemoved(x, y)
    end
end

function M:mousepressed(x, y, button)
    for _, b in ipairs(active_buttons(self)) do
        if b:on_mousepressed(x, y, button) then
            return
        end
    end
end

function M:mousereleased(x, y, button)
    for _, b in ipairs(active_buttons(self)) do
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
    if key == "escape" then -- i18n-ok
        self:_return_to_menu()
    elseif key == "tab" then -- i18n-ok
        self._focus:advance(shift_held() and -1 or 1)
    elseif key == "down" or key == "right" then -- i18n-ok
        self._focus:advance(1)
    elseif key == "up" or key == "left" then -- i18n-ok
        self._focus:advance(-1)
    elseif key == "return" or key == "space" or key == "kpenter" then -- i18n-ok
        self._focus:activate()
    end
end

return M
