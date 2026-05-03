-- New-game picker scene. Lets the player choose which seats are human
-- and which are bots before a fresh deal opens. The active rule
-- template's `players.count` decides how many rows render; each row
-- exposes a Human / Bot segmented toggle plus an Easy / Normal / Hard
-- difficulty toggle that disables itself for human seats. Defaults to
-- seat 1 = human, the rest = bots, and every difficulty = "normal" —
-- the same composition the menu's "Single Player" entry produces in
-- one click — so the most common path is just "press Start". An
-- all-bot composition is permitted on purpose: it's a legitimate way
-- to spectate Phase 4.3+ play under any built-in template without a
-- code change.
--
-- Layout follows the menu / template-picker convention: one centred
-- column, fixed widths, vertically reflowed by `compute_layout` from
-- the (w, h) handed into draw. Buttons / toggles are built once on
-- `enter()` so press / release stay paired across draw frames; only
-- their rects change per layout pass.
--
-- The scene never reaches into engine state directly. Pressing Start
-- builds a fresh `Session` with the chosen `seat_kinds` and
-- `seat_difficulties` and hands it to the manager; the table scene
-- reads the bindings off the session (auto-save Continue path) or off
-- the switch params (this path).

local i18n = require("app.i18n")
local Button = require("ui.button")
local Toggle = require("ui.toggle")
local FocusGroup = require("ui.focus_group")
local Session = require("app.session")
local auto_save = require("app.auto_save")
local app_templates = require("app.templates")
local rule_config = require("core.rule_config")
local difficulty_module = require("app.bot.difficulty")
local t = i18n.t

local M = {}
M.__index = M

local TITLE_COLOR = { 1, 1, 1, 1 }
local SUBTITLE_COLOR = { 0.78, 0.92, 0.82, 1 }
local LABEL_COLOR = { 0.92, 0.96, 0.92, 1 }

local TITLE_Y = 80
local SUBTITLE_Y = 120
local ROWS_TOP = 200
local ROW_LABEL_W = 140
local ROW_TOGGLE_W = 240
local ROW_DIFFICULTY_W = 270
local ROW_GAP_X = 24
local ROW_HEIGHT = 56
local ROW_VGAP = 16

local START_BTN_W = 280
local START_BTN_H = 56
local START_BTN_TOP_PAD = 36

local BACK_BTN_W = 120
local BACK_BTN_H = 44
local SAFE_MARGIN = 16

local SEAT_KIND_VALUES = { "human", "bot" } -- i18n-ok: enum values
local SEAT_KIND_LABELS = { "scene.new_game.kind.human", "scene.new_game.kind.bot" } -- i18n-ok: keys

-- Difficulty enum sourced from `app.bot.difficulty` so the new-game
-- scene, the session, the auto-save, and Phase 7's character presets
-- all read the same canonical list.
local DIFFICULTY_VALUES = difficulty_module.VALUES
local DIFFICULTY_LABELS = {
    "scene.new_game.difficulty.easy", -- i18n-ok: keys
    "scene.new_game.difficulty.normal", -- i18n-ok: keys
    "scene.new_game.difficulty.hard", -- i18n-ok: keys
}

local function default_seat_kinds(count)
    local out = {}
    out[1] = "human"
    for i = 2, count do
        out[i] = "bot"
    end
    return out
end

local function default_seat_difficulties(count)
    local out = {}
    for i = 1, count do
        out[i] = difficulty_module.DEFAULT
    end
    return out
end

local function active_template_label()
    local active_id = app_templates.get_active_id()
    if type(active_id) == "string" then
        if rule_config.builtins[active_id] then
            return t("templates.builtin." .. active_id) -- i18n-ok: composes a key
        end
        local custom = app_templates.get(active_id)
        if custom and type(custom.name) == "string" then
            return custom.name
        end
    end
    return t("templates.builtin.russian")
end

function M.new(manager)
    return setmetatable({
        _manager = manager,
        _seat_toggles = {},
        _difficulty_toggles = {},
        _start_button = nil,
        _back_button = nil,
        _focus = nil,
        _last_w = 1280,
        _last_h = 720,
    }, M)
end

function M:_collect_seat_kinds()
    local out = {}
    for i, toggle in ipairs(self._seat_toggles) do
        out[i] = toggle.current
    end
    return out
end

function M:_collect_seat_difficulties()
    local out = {}
    for i, toggle in ipairs(self._difficulty_toggles) do
        out[i] = toggle.current
    end
    return out
end

function M:_start_game()
    auto_save.clear()
    local config = app_templates.resolve_active_config()
    local seat_kinds = self:_collect_seat_kinds()
    local seat_difficulties = self:_collect_seat_difficulties()
    local session = Session.new({
        config = config,
        seat_kinds = seat_kinds,
        seat_difficulties = seat_difficulties,
    })
    self._manager:set_session(session)
    self._manager:switch_to("table", {
        seat_kinds = seat_kinds,
        seat_difficulties = seat_difficulties,
    })
end

function M:_build_widgets(count)
    self._seat_toggles = {}
    self._difficulty_toggles = {}
    local kind_defaults = default_seat_kinds(count)
    local difficulty_defaults = default_seat_difficulties(count)
    for i = 1, count do
        local difficulty_toggle = Toggle.new({
            id = "new_game_difficulty_" .. tostring(i), -- i18n-ok: composes id
            values = DIFFICULTY_VALUES,
            value_labels = DIFFICULTY_LABELS,
            current = difficulty_defaults[i],
            -- Difficulty is meaningful only for bot seats; the default
            -- composition has seat 1 human, rest bots, so seat 1's
            -- difficulty toggle starts disabled. The kind toggle's
            -- on_change keeps this in sync as the player flips seats.
            enabled = kind_defaults[i] == "bot",
        })
        difficulty_toggle.on_press = function()
            difficulty_toggle:activate()
        end

        local kind_toggle = Toggle.new({
            id = "new_game_seat_" .. tostring(i), -- i18n-ok: composes id
            values = SEAT_KIND_VALUES,
            value_labels = SEAT_KIND_LABELS,
            current = kind_defaults[i],
            enabled = true,
            on_change = function(new_value)
                difficulty_toggle:set_enabled(new_value == "bot")
            end,
        })
        kind_toggle.on_press = function()
            kind_toggle:activate()
        end

        self._seat_toggles[i] = kind_toggle
        self._difficulty_toggles[i] = difficulty_toggle
    end
    self._start_button = Button.new({
        id = "new_game_start", -- i18n-ok: id
        label_key = "scene.new_game.start",
        enabled = true,
        on_press = function()
            self:_start_game()
        end,
    })
    self._back_button = Button.new({
        id = "new_game_back", -- i18n-ok: id
        label_key = "scene.new_game.back",
        enabled = true,
        on_press = function()
            self._manager:switch_to("menu")
        end,
    })
    -- Tab order: kind -> difficulty within a row, then row to row, then
    -- Start, then Back. Pairs each seat's choice cluster so keyboard
    -- nav reads top-to-bottom in the same order the eyes do.
    local list = {}
    for i = 1, count do
        list[#list + 1] = self._seat_toggles[i]
        list[#list + 1] = self._difficulty_toggles[i]
    end
    list[#list + 1] = self._start_button
    list[#list + 1] = self._back_button
    self._focus = FocusGroup.new(list)
end

function M:enter(_prev_id, _params)
    local config = app_templates.resolve_active_config()
    self:_build_widgets(config.players.count)
end

local function compute_layout(self, w, h)
    self._last_w = w
    self._last_h = h
    self._back_button:set_rect(w - BACK_BTN_W - SAFE_MARGIN, SAFE_MARGIN, BACK_BTN_W, BACK_BTN_H)

    local row_total_w = ROW_LABEL_W + ROW_GAP_X + ROW_TOGGLE_W + ROW_GAP_X + ROW_DIFFICULTY_W
    local row_x = math.floor(w * 0.5 - row_total_w * 0.5)
    self._row_label_x = row_x
    local toggle_x = row_x + ROW_LABEL_W + ROW_GAP_X
    local difficulty_x = toggle_x + ROW_TOGGLE_W + ROW_GAP_X
    local y = ROWS_TOP
    for i, tg in ipairs(self._seat_toggles) do
        tg:set_rect(toggle_x, y, ROW_TOGGLE_W, ROW_HEIGHT)
        self._difficulty_toggles[i]:set_rect(difficulty_x, y, ROW_DIFFICULTY_W, ROW_HEIGHT)
        y = y + ROW_HEIGHT + ROW_VGAP
    end
    self._row_label_top = ROWS_TOP

    local start_x = math.floor(w * 0.5 - START_BTN_W * 0.5)
    local start_y = y + START_BTN_TOP_PAD
    self._start_button:set_rect(start_x, start_y, START_BTN_W, START_BTN_H)
end

function M:draw(w, h)
    w = w or 1280
    h = h or 720
    love.graphics.clear(0.05, 0.13, 0.08)
    compute_layout(self, w, h)

    love.graphics.setColor(TITLE_COLOR)
    love.graphics.printf(t("scene.new_game.title"), 0, TITLE_Y, w, "center")

    love.graphics.setColor(SUBTITLE_COLOR)
    love.graphics.printf(
        t("scene.new_game.template", { name = active_template_label() }),
        0,
        SUBTITLE_Y,
        w,
        "center"
    )

    love.graphics.setColor(LABEL_COLOR)
    local row_y = self._row_label_top
    for i, _ in ipairs(self._seat_toggles) do
        love.graphics.print(
            t("scene.new_game.seat_label", { n = i }),
            self._row_label_x,
            row_y + math.floor(ROW_HEIGHT * 0.5) - 8
        )
        row_y = row_y + ROW_HEIGHT + ROW_VGAP
    end

    for i, tg in ipairs(self._seat_toggles) do
        tg:draw()
        self._difficulty_toggles[i]:draw()
    end
    self._start_button:draw()
    self._back_button:draw()

    love.graphics.setColor(1, 1, 1, 1)
end

function M:mousemoved(x, y, _dx, _dy)
    for i, tg in ipairs(self._seat_toggles) do
        tg:on_mousemoved(x, y)
        self._difficulty_toggles[i]:on_mousemoved(x, y)
    end
    self._start_button:on_mousemoved(x, y)
    self._back_button:on_mousemoved(x, y)
end

function M:mousepressed(x, y, button)
    for i, tg in ipairs(self._seat_toggles) do
        if tg:on_mousepressed(x, y, button) then
            return
        end
        if self._difficulty_toggles[i]:on_mousepressed(x, y, button) then
            return
        end
    end
    if self._start_button:on_mousepressed(x, y, button) then
        return
    end
    self._back_button:on_mousepressed(x, y, button)
end

function M:mousereleased(x, y, button)
    for i, tg in ipairs(self._seat_toggles) do
        tg:on_mousereleased(x, y, button)
        self._difficulty_toggles[i]:on_mousereleased(x, y, button)
    end
    self._start_button:on_mousereleased(x, y, button)
    self._back_button:on_mousereleased(x, y, button)
end

local function shift_held()
    if not (love.keyboard and love.keyboard.isDown) then
        return false
    end
    return love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") -- i18n-ok
end

function M:keypressed(key)
    if key == "escape" then -- i18n-ok
        self._manager:switch_to("menu")
        return
    end
    if not self._focus then
        return
    end
    if key == "tab" then -- i18n-ok
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
