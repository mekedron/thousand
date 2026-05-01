-- Template picker scene. Lists every built-in template (canonical
-- Russian first), then every user-saved custom template. Each row
-- exposes Use / Edit / Clone / Delete. "Use this template" persists
-- the active id through app.settings; if a game is in progress the
-- press routes through a confirmation modal that abandons the deal.
--
-- Custom rows show the modified-field count against their parent
-- built-in via core.template_diff.summarise.
--
-- Buttons are built once on enter() so press / release stay paired
-- across draw frames. compute_layout only updates rects (with the
-- current scroll offset applied), keeping focus / pressed state
-- attached to stable Button instances.

local i18n = require("app.i18n")
local Button = require("ui.button")
local FocusGroup = require("ui.focus_group")
local rule_config = require("core.rule_config")
local app_templates = require("app.templates")
local app_json = require("app.json")
local template_diff = require("core.template_diff")
local auto_save = require("app.auto_save")

local t = i18n.t

local M = {}
M.__index = M

local TITLE_COLOR = { 1, 1, 1, 1 }
local LABEL_COLOR = { 0.92, 0.96, 0.92, 1 }
local DESC_COLOR = { 0.65, 0.78, 0.68, 1 }
local SECTION_COLOR = { 0.85, 0.95, 0.78, 1 }
local BADGE_COLOR = { 0.95, 0.95, 0.55, 1 }

local TITLE_Y = 24
local BODY_TOP = 80
local SECTION_HEADER_HEIGHT = 38
local ROW_HEIGHT = 96
local ROW_LABEL_X = 24
local ROW_BUTTON_W = 110
local ROW_BUTTON_H = 40
local ROW_BUTTON_GAP = 8
local SAFE_MARGIN = 16
local BACK_BTN_W = 120
local BACK_BTN_H = 44
local SCROLL_STEP = 60

local function builtin_label_key(builtin_id)
    return "templates.builtin." .. builtin_id -- i18n-ok: composes a key
end

local function builtin_blob(builtin_id)
    local builtin = rule_config.builtins[builtin_id]
    if not builtin then
        return nil
    end
    return app_json.decode(rule_config.to_json(builtin))
end

function M.new(manager)
    return setmetatable({
        _manager = manager,
        _builtins = {},
        _customs = {},
        _row_buttons = {},
        _builtin_rows = {},
        _custom_rows = {},
        _modal = nil,
        _pending_action = nil,
        _scroll_y = 0,
        _last_w = 1280,
        _last_h = 720,
    }, M)
end

local function row_buttons_for_builtin(self, b)
    local use = Button.new({
        id = "use_" .. b.id, -- i18n-ok: composes id
        label_key = "scene.template_picker.use",
        enabled = true,
        on_press = function()
            self:_use_template(b.id)
        end,
    })
    local edit = Button.new({
        id = "edit_" .. b.id, -- i18n-ok: composes id
        label_key = "scene.template_picker.edit",
        enabled = true,
        on_press = function()
            self:_edit_template(b.id, true)
        end,
    })
    local clone = Button.new({
        id = "clone_" .. b.id, -- i18n-ok: composes id
        label_key = "scene.template_picker.clone",
        enabled = true,
        on_press = function()
            self:_clone_builtin(b.id)
        end,
    })
    return { use, edit, clone }
end

local function row_buttons_for_custom(self, tmpl)
    local use = Button.new({
        id = "use_" .. tmpl.id, -- i18n-ok: composes id
        label_key = "scene.template_picker.use",
        enabled = true,
        on_press = function()
            self:_use_template(tmpl.id)
        end,
    })
    local edit = Button.new({
        id = "edit_" .. tmpl.id, -- i18n-ok: composes id
        label_key = "scene.template_picker.edit",
        enabled = true,
        on_press = function()
            self:_edit_template(tmpl.id, false)
        end,
    })
    local clone = Button.new({
        id = "clone_" .. tmpl.id, -- i18n-ok: composes id
        label_key = "scene.template_picker.clone",
        enabled = true,
        on_press = function()
            self:_clone_custom(tmpl.id)
        end,
    })
    local del = Button.new({
        id = "delete_" .. tmpl.id, -- i18n-ok: composes id
        label_key = "scene.template_picker.delete",
        enabled = true,
        on_press = function()
            self:_open_delete_modal(tmpl.id)
        end,
    })
    return { use, edit, clone, del }
end

function M:_build_buttons()
    self._back_button = Button.new({
        id = "template_picker_back", -- i18n-ok: id
        label_key = "scene.template_picker.back",
        enabled = true,
        on_press = function()
            self._manager:switch_to("menu")
        end,
    })
    self._modal_yes = Button.new({
        id = "template_picker_modal_yes", -- i18n-ok: id
        label_key = "scene.template_picker.confirm_delete.yes",
        enabled = true,
        on_press = function()
            self:_run_pending_action()
        end,
    })
    self._modal_no = Button.new({
        id = "template_picker_modal_no", -- i18n-ok: id
        label_key = "scene.template_picker.confirm_delete.no",
        enabled = true,
        on_press = function()
            self:_close_modal()
        end,
    })
    self._modal_focus = FocusGroup.new({ self._modal_yes, self._modal_no })
end

function M:_rebuild_rows()
    self._builtin_rows = {}
    self._custom_rows = {}
    self._row_buttons = {}
    for _, b in ipairs(self._builtins) do
        local buttons = row_buttons_for_builtin(self, b)
        self._builtin_rows[#self._builtin_rows + 1] = { entry = b, buttons = buttons }
        for _, btn in ipairs(buttons) do
            self._row_buttons[#self._row_buttons + 1] = btn
        end
    end
    for _, tmpl in ipairs(self._customs) do
        local buttons = row_buttons_for_custom(self, tmpl)
        self._custom_rows[#self._custom_rows + 1] = { entry = tmpl, buttons = buttons }
        for _, btn in ipairs(buttons) do
            self._row_buttons[#self._row_buttons + 1] = btn
        end
    end
end

function M:_load_lists()
    local listing = app_templates.list()
    self._builtins = listing.builtins
    self._customs = listing.templates
end

function M:_rebuild_focus()
    local list = {}
    for _, btn in ipairs(self._row_buttons) do
        list[#list + 1] = btn
    end
    list[#list + 1] = self._back_button
    self._focus = FocusGroup.new(list)
end

function M:_use_template(id)
    if self._manager:is_game_active() then
        self:_open_switch_modal(id)
        return
    end
    app_templates.set_active_id(id)
    self._manager:switch_to("menu")
end

function M:_open_switch_modal(id)
    self._modal = "confirm_switch"
    self._modal_yes.label_key = "scene.template_picker.confirm_switch_mid_game.yes"
    self._modal_no.label_key = "scene.template_picker.confirm_switch_mid_game.no"
    self._pending_action = function()
        auto_save.clear()
        self._manager:clear_session()
        app_templates.set_active_id(id)
        self:_close_modal()
        self._manager:switch_to("menu")
    end
    self._modal_focus:focus(self._modal_no)
end

function M:_open_delete_modal(id)
    self._modal = "confirm_delete"
    self._modal_yes.label_key = "scene.template_picker.confirm_delete.yes"
    self._modal_no.label_key = "scene.template_picker.confirm_delete.no"
    self._pending_action = function()
        local result = app_templates.delete(id)
        if result.ok and app_templates.get_active_id() == id then
            app_templates.set_active_id("russian")
        end
        self:_load_lists()
        self:_rebuild_rows()
        self:_rebuild_focus()
        self:_close_modal()
    end
    self._modal_focus:focus(self._modal_no)
end

function M:_close_modal()
    self._modal = nil
    self._pending_action = nil
    self._modal_focus:clear()
end

function M:_run_pending_action()
    local fn = self._pending_action
    self._pending_action = nil
    if fn then
        fn()
    end
end

function M:_clone_builtin(id)
    local builtin_name = t(builtin_label_key(id))
    local cloned_name = t("templates.duplicate_suffix", { name = builtin_name })
    local result = app_templates.create({ fromBuiltin = id, name = cloned_name })
    if result.ok then
        self._manager:switch_to("template_editor", { template_id = result.template.id })
    end
end

function M:_clone_custom(id)
    local result = app_templates.duplicate(id)
    if result.ok then
        self._manager:switch_to("template_editor", { template_id = result.template.id })
    end
end

function M:_edit_template(id, is_builtin)
    if is_builtin then
        self._manager:switch_to("template_editor", { builtin_id = id })
    else
        self._manager:switch_to("template_editor", { template_id = id })
    end
end

function M:enter(_prev_id, _params)
    if not self._back_button then
        self:_build_buttons()
    end
    self:_load_lists()
    self:_close_modal()
    self._scroll_y = 0
    self:_rebuild_rows()
    self:_rebuild_focus()
end

local function content_height(self)
    -- Two section headers + N built-ins + M customs + empty-state row.
    local h = SECTION_HEADER_HEIGHT
    h = h + #self._builtin_rows * ROW_HEIGHT
    h = h + SECTION_HEADER_HEIGHT
    if #self._custom_rows == 0 then
        h = h + ROW_HEIGHT
    else
        h = h + #self._custom_rows * ROW_HEIGHT
    end
    return h
end

local function viewport_h(self)
    local _ = self._last_w
    return self._last_h - BODY_TOP - SAFE_MARGIN
end

local function clamp_scroll(self)
    local content = content_height(self)
    local view = viewport_h(self)
    local max_offset = math.max(0, content - view)
    if self._scroll_y < 0 then
        self._scroll_y = 0
    elseif self._scroll_y > max_offset then
        self._scroll_y = max_offset
    end
end

local function place_row_buttons(buttons, x_anchor, y)
    local x = x_anchor
    for _, b in ipairs(buttons) do
        b:set_rect(x, y, ROW_BUTTON_W, ROW_BUTTON_H)
        x = x + ROW_BUTTON_W + ROW_BUTTON_GAP
    end
end

local function compute_layout(self, w, h)
    self._last_w = w
    self._last_h = h
    self._back_button:set_rect(w - BACK_BTN_W - SAFE_MARGIN, SAFE_MARGIN, BACK_BTN_W, BACK_BTN_H)
    clamp_scroll(self)

    local row_buttons_count
    if #self._custom_rows == 0 then
        row_buttons_count = 3 -- Use, Edit, Clone for built-ins
    else
        row_buttons_count = 4 -- Delete added for customs
    end
    local x_anchor = w - SAFE_MARGIN - row_buttons_count * (ROW_BUTTON_W + ROW_BUTTON_GAP)

    local y = BODY_TOP - self._scroll_y
    -- Built-in section.
    self._builtins_header_y = y
    y = y + SECTION_HEADER_HEIGHT
    for _, row in ipairs(self._builtin_rows) do
        row.y = y
        place_row_buttons(row.buttons, x_anchor, y)
        y = y + ROW_HEIGHT
    end
    -- Custom section.
    self._customs_header_y = y
    y = y + SECTION_HEADER_HEIGHT
    if #self._custom_rows == 0 then
        self._empty_customs_y = y
        y = y + ROW_HEIGHT
    end
    for _, row in ipairs(self._custom_rows) do
        row.y = y
        place_row_buttons(row.buttons, x_anchor, y)
        y = y + ROW_HEIGHT
    end
end

local function compute_modal_layout(self, w, h)
    local panel_w, panel_h = 520, 220
    local panel_x = math.floor(w * 0.5 - panel_w * 0.5)
    local panel_y = math.floor(h * 0.5 - panel_h * 0.5)
    self._modal_panel = { x = panel_x, y = panel_y, w = panel_w, h = panel_h }
    local btn_w, btn_h, btn_gap = 220, 48, 24
    local total_w = btn_w * 2 + btn_gap
    local btn_y = panel_y + panel_h - btn_h - 28
    local left_x = panel_x + math.floor(panel_w * 0.5 - total_w * 0.5)
    self._modal_yes:set_rect(left_x, btn_y, btn_w, btn_h)
    self._modal_no:set_rect(left_x + btn_w + btn_gap, btn_y, btn_w, btn_h)
end

function M:_apply_focus_marks()
    local focused = self._focus and self._focus:focused()
    for _, btn in ipairs(self._row_buttons) do
        btn.focused = (btn == focused)
    end
    self._back_button.focused = (self._back_button == focused)
end

local function summarise_modified(parent_id, child_blob)
    local p = builtin_blob(parent_id)
    if p == nil then
        return nil
    end
    return template_diff.summarise(p, child_blob)
end

function M:draw(w, h)
    w = w or 1280
    h = h or 720
    love.graphics.clear(0.05, 0.13, 0.08)
    compute_layout(self, w, h)
    self:_apply_focus_marks()

    local active_id = app_templates.get_active_id()

    love.graphics.setColor(TITLE_COLOR)
    love.graphics.printf(t("scene.template_picker.title"), 0, TITLE_Y, w, "center")

    -- Built-in section header.
    love.graphics.setColor(SECTION_COLOR)
    love.graphics.print(
        t("scene.template_picker.builtins_header"),
        ROW_LABEL_X,
        self._builtins_header_y + 8
    )
    for _, row in ipairs(self._builtin_rows) do
        love.graphics.setColor(LABEL_COLOR)
        love.graphics.print(t(builtin_label_key(row.entry.id)), ROW_LABEL_X, row.y + 6)
        if row.entry.id == active_id then
            love.graphics.setColor(BADGE_COLOR)
            love.graphics.print(t("scene.template_picker.in_use_badge"), ROW_LABEL_X, row.y + 30)
        end
        for _, b in ipairs(row.buttons) do
            b:draw()
        end
    end

    -- Custom section header.
    love.graphics.setColor(SECTION_COLOR)
    love.graphics.print(
        t("scene.template_picker.customs_header"),
        ROW_LABEL_X,
        self._customs_header_y + 8
    )
    if #self._custom_rows == 0 then
        love.graphics.setColor(DESC_COLOR)
        love.graphics.print(
            t("scene.template_picker.empty_customs"),
            ROW_LABEL_X,
            (self._empty_customs_y or 0) + 6
        )
    end
    for _, row in ipairs(self._custom_rows) do
        love.graphics.setColor(LABEL_COLOR)
        love.graphics.print(row.entry.name, ROW_LABEL_X, row.y + 6)
        love.graphics.setColor(DESC_COLOR)
        local parent_id = row.entry.parentTemplateId
        if parent_id then
            local parent_label = t(builtin_label_key(parent_id))
            love.graphics.print(
                t("scene.template_picker.parent_label", { name = parent_label }),
                ROW_LABEL_X,
                row.y + 30
            )
        end
        if row.entry.parentMissing then
            love.graphics.setColor(BADGE_COLOR)
            love.graphics.print(t("scene.template_picker.parent_missing"), ROW_LABEL_X, row.y + 50)
        else
            local summary = summarise_modified(parent_id, row.entry.ruleConfig)
            if summary and summary.total_modified > 0 then
                love.graphics.setColor(BADGE_COLOR)
                love.graphics.print(
                    t("scene.template_picker.modified_count", { n = summary.total_modified }),
                    ROW_LABEL_X,
                    row.y + 50
                )
            end
        end
        if row.entry.id == active_id then
            love.graphics.setColor(BADGE_COLOR)
            local badge = t("scene.template_picker.in_use_badge")
            love.graphics.print(badge, ROW_LABEL_X + 280, row.y + 6)
        end
        for _, b in ipairs(row.buttons) do
            b:draw()
        end
    end

    self._back_button:draw()

    if self._modal then
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
        local prompt_key
        if self._modal == "confirm_switch" then -- i18n-ok: state
            prompt_key = "scene.template_picker.confirm_switch_mid_game.prompt"
        else
            prompt_key = "scene.template_picker.confirm_delete.prompt"
        end
        love.graphics.printf(
            t(prompt_key),
            self._modal_panel.x + 24,
            self._modal_panel.y + 50,
            self._modal_panel.w - 48,
            "center"
        )
        self._modal_yes:draw()
        self._modal_no:draw()
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function M:mousemoved(x, y, _dx, _dy)
    if self._modal then
        self._modal_yes:on_mousemoved(x, y)
        self._modal_no:on_mousemoved(x, y)
        return
    end
    for _, b in ipairs(self._row_buttons) do
        b:on_mousemoved(x, y)
    end
    self._back_button:on_mousemoved(x, y)
end

function M:mousepressed(x, y, button)
    if self._modal then
        if self._modal_yes:on_mousepressed(x, y, button) then
            return
        end
        if self._modal_no:on_mousepressed(x, y, button) then
            return
        end
        return
    end
    for _, b in ipairs(self._row_buttons) do
        if b:on_mousepressed(x, y, button) then
            return
        end
    end
    self._back_button:on_mousepressed(x, y, button)
end

function M:mousereleased(x, y, button)
    if self._modal then
        self._modal_yes:on_mousereleased(x, y, button)
        self._modal_no:on_mousereleased(x, y, button)
        return
    end
    for _, b in ipairs(self._row_buttons) do
        b:on_mousereleased(x, y, button)
    end
    self._back_button:on_mousereleased(x, y, button)
end

function M:wheelmoved(_dx, dy)
    if self._modal or not dy or dy == 0 then
        return
    end
    self._scroll_y = self._scroll_y - dy * SCROLL_STEP
    clamp_scroll(self)
end

local function shift_held()
    if not (love.keyboard and love.keyboard.isDown) then
        return false
    end
    return love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") -- i18n-ok
end

function M:keypressed(key)
    if self._modal then
        if key == "tab" then -- i18n-ok
            self._modal_focus:advance(shift_held() and -1 or 1)
        elseif key == "down" or key == "right" then -- i18n-ok
            self._modal_focus:advance(1)
        elseif key == "up" or key == "left" then -- i18n-ok
            self._modal_focus:advance(-1)
        elseif key == "return" or key == "space" or key == "kpenter" then -- i18n-ok
            self._modal_focus:activate()
        elseif key == "escape" then -- i18n-ok
            self:_close_modal()
        end
        return
    end
    if key == "escape" then -- i18n-ok
        self._manager:switch_to("menu")
    elseif key == "tab" then -- i18n-ok
        self._focus:advance(shift_held() and -1 or 1)
    elseif key == "down" or key == "right" then -- i18n-ok
        self._focus:advance(1)
    elseif key == "up" or key == "left" then -- i18n-ok
        self._focus:advance(-1)
    elseif key == "return" or key == "space" or key == "kpenter" then -- i18n-ok
        self._focus:activate()
    elseif key == "pageup" then -- i18n-ok
        self._scroll_y = self._scroll_y - viewport_h(self)
        clamp_scroll(self)
    elseif key == "pagedown" then -- i18n-ok
        self._scroll_y = self._scroll_y + viewport_h(self)
        clamp_scroll(self)
    end
end

return M
