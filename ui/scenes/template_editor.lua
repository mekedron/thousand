-- Template editor scene. Schema-driven form: walks rule_config.sections()
-- and renders a control per leaf field — segmented toggle for enums and
-- booleans, numeric stepper for free-range numbers, read-only text for
-- list/map fields and for fields whose status is "deferred". Live
-- validation runs every interaction; invariant failures surface as a
-- banner and disable Save.
--
-- Built-in templates open here in read-only mode (Clone-to-edit only).
-- Custom templates expose Save / Reset / Duplicate / Delete.
--
-- Per-row "modified" badges come from core.template_diff against the
-- parent built-in's blob.

local i18n = require("app.i18n")
local Button = require("ui.button")
local Toggle = require("ui.toggle")
local NumberStepper = require("ui.number_stepper")
local FocusGroup = require("ui.focus_group")
local rule_config = require("core.rule_config")
local app_templates = require("app.templates")
local app_json = require("app.json")
local template_diff = require("core.template_diff")

local t = i18n.t

local M = {}
M.__index = M

local TITLE_Y = 20
local PARENT_Y = 56
local HEADER_BOTTOM = 88
local FOOTER_HEIGHT = 64
local ROW_HEIGHT = 88
local SECTION_HEADER_HEIGHT = 40
local LABEL_X = 20
local CONTROL_X = 360
local CONTROL_W = 320
local CONTROL_H = 44
local BADGE_X_OFFSET = 12
local BANNER_HEIGHT = 32
-- Width available for the label + help text column (right-padded so
-- wrapped lines don't kiss the toggle/stepper at CONTROL_X).
local LABEL_COLUMN_W = CONTROL_X - LABEL_X - 16

local SCENE_BG = { 0.05, 0.13, 0.08, 1 }
local PANEL_BG = { 0.05, 0.13, 0.08, 1 }
local PANEL_DIVIDER = { 0.18, 0.30, 0.20, 1 }
local TITLE_COLOR = { 1, 1, 1, 1 }
local LABEL_COLOR = { 0.92, 0.96, 0.92, 1 }
local DESC_COLOR = { 0.65, 0.78, 0.68, 1 }
local SECTION_COLOR = { 0.85, 0.95, 0.78, 1 }
local BANNER_COLOR = { 0.42, 0.10, 0.10, 1 }
local BANNER_TEXT = { 1, 0.92, 0.78, 1 }
local MODIFIED_COLOR = { 0.95, 0.95, 0.55, 1 }

local function builtin_label_key(builtin_id)
    return "templates.builtin." .. builtin_id
end

local function deep_copy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = deep_copy(v)
    end
    return out
end

local function blob_from_template(template)
    return deep_copy(template.ruleConfig)
end

local function blob_from_builtin(builtin_id)
    local builtin = rule_config.builtins[builtin_id]
    if builtin == nil then
        return nil
    end
    return app_json.decode(rule_config.to_json(builtin))
end

local function set_field(blob, section, field, value)
    blob[section] = blob[section] or {}
    blob[section][field] = value
end

function M.new(manager)
    return setmetatable({
        _manager = manager,
        _template = nil,
        _builtin_id = nil,
        _is_builtin = false,
        _parent_blob = nil,
        _working_blob = nil,
        _widgets = {},
        _modified = {},
        _dry_run_error = nil,
        _modal = nil,
        _last_w = 0,
        _last_h = 0,
        _scroll_y = 0,
    }, M)
end

local function field_label_key(section, field)
    return "templates.field." .. section .. "." .. field .. ".label" -- i18n-ok: composes a key
end

local function field_help_key(section, field)
    return "templates.field." .. section .. "." .. field .. ".help" -- i18n-ok: composes a key
end

local function value_label_key_for(section, field, value)
    if type(value) == "boolean" then
        return value and "scene.settings.toggle.on" or "scene.settings.toggle.off" -- i18n-ok: keys
    end
    return string.format("templates.field.%s.%s.%s", section, field, tostring(value))
end

local function build_toggle_for_field(self, section, field, descriptor)
    local current = self._working_blob[section][field]
    local values, value_labels
    if descriptor.lua_type == "boolean" then
        values = { false, true }
        value_labels = { "scene.settings.toggle.off", "scene.settings.toggle.on" } -- i18n-ok: keys
    else
        values = {}
        value_labels = {}
        for i, v in ipairs(descriptor.allowed) do
            values[i] = v
            value_labels[i] = value_label_key_for(section, field, v)
        end
    end
    local widget = Toggle.new({
        id = section .. "." .. field,
        values = values,
        value_labels = value_labels,
        current = current,
        enabled = descriptor.status ~= "deferred" and not self._is_builtin,
        on_change = function(v)
            set_field(self._working_blob, section, field, v)
            self:_recompute()
        end,
    })
    return widget
end

local function build_stepper_for_field(self, section, field, descriptor)
    local current = self._working_blob[section][field]
    local min_v = descriptor.min or 0
    local max_v = descriptor.max or 9999
    local range = max_v - min_v
    local step = 1
    if range >= 100 then
        step = 5
    elseif range >= 20 then
        step = 1
    end
    local widget = NumberStepper.new({
        id = section .. "." .. field,
        current = current,
        step = step,
        min = min_v,
        max = max_v,
        enabled = descriptor.status ~= "deferred" and not self._is_builtin,
        on_change = function(v)
            set_field(self._working_blob, section, field, v)
            self:_recompute()
        end,
    })
    return widget
end

local function build_field_entry(self, section, field, descriptor)
    local entry = {
        section = section,
        field = field,
        descriptor = descriptor,
        kind = descriptor.kind,
        widget = nil,
        readonly = false,
    }
    if descriptor.kind == "leaf" then
        local has_enum = type(descriptor.allowed) == "table"
        local is_bool = descriptor.lua_type == "boolean" -- i18n-ok: type guard
        if has_enum or is_bool then
            entry.widget = build_toggle_for_field(self, section, field, descriptor)
        elseif descriptor.lua_type == "number" and (descriptor.min or descriptor.max) then
            entry.widget = build_stepper_for_field(self, section, field, descriptor)
        else
            entry.readonly = true
        end
    else
        entry.readonly = true
    end
    return entry
end

local function build_widgets(self)
    self._widgets = {}
    for _, section in ipairs(rule_config.sections()) do
        local section_desc = rule_config.schema_for(section)
        if section_desc and section_desc.fields then
            for _, field in ipairs(section_desc.fields) do
                local descriptor = rule_config.schema_for(section .. "." .. field)
                if descriptor then
                    local entry = build_field_entry(self, section, field, descriptor)
                    self._widgets[#self._widgets + 1] = entry
                end
            end
        end
    end
end

function M:_recompute()
    local result = rule_config.try_new(self._working_blob)
    if result.ok then
        self._dry_run_error = nil
    else
        self._dry_run_error = result.error
    end
    self._modified = {}
    if self._parent_blob then
        local diff = template_diff.diff(self._parent_blob, self._working_blob)
        for _, change in ipairs(diff.changes) do
            self._modified[change.path] = change
        end
    end
    self:_refresh_save_state()
end

function M:_refresh_save_state()
    if not self._save_button then
        return
    end
    local can_save = self._dry_run_error == nil and not self._is_builtin
    self._save_button:set_enabled(can_save)
end

local function build_focus_group(self)
    local list = {}
    for _, entry in ipairs(self._widgets) do
        if entry.widget and entry.widget.enabled then
            list[#list + 1] = entry.widget
        end
    end
    if self._save_button then
        list[#list + 1] = self._save_button
    end
    if self._cancel_button then
        list[#list + 1] = self._cancel_button
    end
    if self._reset_button then
        list[#list + 1] = self._reset_button
    end
    if self._duplicate_button then
        list[#list + 1] = self._duplicate_button
    end
    if self._delete_button then
        list[#list + 1] = self._delete_button
    end
    self._focus = FocusGroup.new(list)
end

local function build_buttons(self)
    self._save_button = Button.new({
        id = "tpl_editor_save",
        label_key = "scene.template_editor.save",
        enabled = not self._is_builtin,
        on_press = function()
            self:_save()
        end,
    })
    self._cancel_button = Button.new({
        id = "tpl_editor_cancel",
        label_key = "scene.template_editor.cancel",
        enabled = true,
        on_press = function()
            self:_back()
        end,
    })
    self._reset_button = Button.new({
        id = "tpl_editor_reset",
        label_key = "scene.template_editor.reset",
        enabled = self:_can_reset(),
        on_press = function()
            self:_reset_to_parent()
        end,
    })
    self._duplicate_button = Button.new({
        id = "tpl_editor_duplicate",
        label_key = "scene.template_editor.duplicate",
        enabled = self._template ~= nil,
        on_press = function()
            self:_duplicate()
        end,
    })
    self._delete_button = Button.new({
        id = "tpl_editor_delete",
        label_key = "scene.template_editor.delete",
        enabled = self._template ~= nil,
        on_press = function()
            self:_open_delete_modal()
        end,
    })
    self._modal_yes = Button.new({
        id = "tpl_editor_modal_yes",
        label_key = "scene.template_editor.confirm_delete.yes",
        enabled = true,
        on_press = function()
            self:_confirm_delete()
        end,
    })
    self._modal_no = Button.new({
        id = "tpl_editor_modal_no",
        label_key = "scene.template_editor.confirm_delete.no",
        enabled = true,
        on_press = function()
            self:_close_modal()
        end,
    })
    self._modal_focus = FocusGroup.new({ self._modal_yes, self._modal_no })
end

function M:_can_reset()
    if self._is_builtin or self._template == nil then
        return false
    end
    if self._template.parentMissing then
        return false
    end
    return self._parent_blob ~= nil
end

function M:enter(_prev_id, params)
    self._modal = nil
    self._scroll_y = 0
    params = params or {}
    if params.template_id then
        local template = app_templates.get(params.template_id)
        if template then
            self._template = template
            self._template_id = template.id
            self._is_builtin = false
            self._parent_blob = blob_from_builtin(template.parentTemplateId)
            self._working_blob = blob_from_template(template)
        else
            -- Unknown id — bail to picker.
            self._manager:switch_to("template_picker")
            return
        end
    elseif params.builtin_id then
        local blob = blob_from_builtin(params.builtin_id)
        if blob == nil then
            self._manager:switch_to("template_picker")
            return
        end
        self._template = nil
        self._template_id = nil
        self._builtin_id = params.builtin_id
        self._is_builtin = true
        self._parent_blob = blob
        self._working_blob = deep_copy(blob)
    else
        self._manager:switch_to("template_picker")
        return
    end
    build_buttons(self)
    build_widgets(self)
    self:_recompute()
    build_focus_group(self)
end

function M:_back()
    self._manager:switch_to("template_picker")
end

function M:_save()
    if self._is_builtin or self._dry_run_error ~= nil then
        return
    end
    if self._template_id == nil then
        return
    end
    local result = app_templates.update(self._template_id, self._working_blob)
    if result.ok then
        self._template = result.template
        self._parent_blob = blob_from_builtin(result.template.parentTemplateId) or self._parent_blob
        self:_recompute()
    else
        self._dry_run_error = result.error
        self:_refresh_save_state()
    end
end

function M:_reset_to_parent()
    if not self:_can_reset() then
        return
    end
    local result = app_templates.reset(self._template_id)
    if result.ok then
        self._template = result.template
        self._working_blob = blob_from_template(result.template)
        build_widgets(self)
        self:_recompute()
        build_focus_group(self)
    end
end

function M:_duplicate()
    if self._template == nil then
        return
    end
    local result = app_templates.duplicate(self._template_id)
    if result.ok then
        self._manager:switch_to("template_editor", { template_id = result.template.id })
    end
end

function M:_open_delete_modal()
    self._modal = "confirm_delete"
    self._modal_focus:focus(self._modal_no)
end

function M:_close_modal()
    self._modal = nil
    self._modal_focus:clear()
end

function M:_confirm_delete()
    if self._template == nil then
        return
    end
    local result = app_templates.delete(self._template_id)
    if result.ok then
        -- If the user just deleted the active template, reset settings.
        if app_templates.get_active_id() == self._template_id then
            app_templates.set_active_id("russian")
        end
        self:_close_modal()
        self._manager:switch_to("template_picker")
    else
        self:_close_modal()
    end
end

local function compute_layout(self, w, h)
    self._last_w = w
    self._last_h = h
    -- Header buttons: Save / Cancel top-right.
    local btn_w, btn_h = 140, 44
    local margin = 16
    self._cancel_button:set_rect(w - btn_w - margin, margin, btn_w, btn_h)
    self._save_button:set_rect(w - 2 * (btn_w + margin) + margin, margin, btn_w, btn_h)
    -- Footer.
    local footer_y = h - FOOTER_HEIGHT + 12
    self._reset_button:set_rect(margin, footer_y, btn_w, btn_h)
    self._duplicate_button:set_rect(margin + btn_w + 12, footer_y, btn_w + 24, btn_h)
    self._delete_button:set_rect(w - btn_w - margin, footer_y, btn_w, btn_h)
    -- Body widgets: assigned positions during draw.
end

local function compute_modal_layout(self, w, h)
    local panel_w, panel_h = 480, 220
    local panel_x = math.floor(w * 0.5 - panel_w * 0.5)
    local panel_y = math.floor(h * 0.5 - panel_h * 0.5)
    self._modal_panel = { x = panel_x, y = panel_y, w = panel_w, h = panel_h }
    local btn_w, btn_h, btn_gap = 200, 48, 24
    local total_w = btn_w * 2 + btn_gap
    local btn_y = panel_y + panel_h - btn_h - 28
    local left_x = panel_x + math.floor(panel_w * 0.5 - total_w * 0.5)
    self._modal_yes:set_rect(left_x, btn_y, btn_w, btn_h)
    self._modal_no:set_rect(left_x + btn_w + btn_gap, btn_y, btn_w, btn_h)
end

function M:_apply_focus_marks()
    local focused = self._focus and self._focus:focused()
    for _, entry in ipairs(self._widgets) do
        if entry.widget then
            entry.widget.focused = (focused == entry.widget)
        end
    end
    if self._save_button then
        self._save_button.focused = (focused == self._save_button)
    end
    if self._cancel_button then
        self._cancel_button.focused = (focused == self._cancel_button)
    end
    if self._reset_button then
        self._reset_button.focused = (focused == self._reset_button)
    end
    if self._duplicate_button then
        self._duplicate_button.focused = (focused == self._duplicate_button)
    end
    if self._delete_button then
        self._delete_button.focused = (focused == self._delete_button)
    end
end

local function row_path(entry)
    return entry.section .. "." .. entry.field
end

local function format_error(err)
    if not err or not err.code then
        return ""
    end
    if err.code == "incompatible_combination" and err.invariant then -- i18n-ok: error code
        local key = "rule_config.invariant." .. err.invariant -- i18n-ok: composes a key
        return t(key, err)
    end
    return t("rule_config.error." .. err.code, err) -- i18n-ok: composes a key
end

function M:draw(w, h)
    w = w or 800
    h = h or 600
    love.graphics.clear(SCENE_BG[1], SCENE_BG[2], SCENE_BG[3])
    compute_layout(self, w, h)
    self:_apply_focus_marks()

    -- Body — section-grouped rows under a scissor clip so the scrolled
    -- content never bleeds into the header or footer panels. Y positions
    -- account for the active scroll offset; widgets keep stable Button
    -- instances across frames so only their rect moves.
    local body_top = HEADER_BOTTOM
    local body_h = math.max(0, h - HEADER_BOTTOM - FOOTER_HEIGHT)
    love.graphics.setScissor(0, body_top, w, body_h)
    local y = body_top - self._scroll_y
    local current_section
    for _, entry in ipairs(self._widgets) do
        if entry.section ~= current_section then
            current_section = entry.section
            love.graphics.setColor(SECTION_COLOR)
            local section_label = t("templates.section." .. entry.section) -- i18n-ok: key
            love.graphics.print(section_label, LABEL_X, y + 8)
            y = y + SECTION_HEADER_HEIGHT
        end
        love.graphics.setColor(LABEL_COLOR)
        love.graphics.print(t(field_label_key(entry.section, entry.field)), LABEL_X, y + 6)
        love.graphics.setColor(DESC_COLOR)
        local help_key = field_help_key(entry.section, entry.field)
        local help = t(help_key)
        if help == help_key and entry.descriptor.status == "deferred" then -- i18n-ok: status
            help = t("templates.field.deferred_help")
        end
        if help ~= help_key then
            love.graphics.printf(help, LABEL_X, y + 26, LABEL_COLUMN_W, "left")
        end
        if entry.widget then
            entry.widget:set_rect(CONTROL_X, y, CONTROL_W, CONTROL_H)
            entry.widget:draw()
        elseif entry.readonly then
            love.graphics.setColor(DESC_COLOR)
            love.graphics.print(t("scene.template_editor.read_only_field"), CONTROL_X, y + 14)
        end
        if entry.descriptor.status == "deferred" then -- i18n-ok: status
            love.graphics.setColor(DESC_COLOR)
            love.graphics.print(
                t("scene.template_editor.deferred_badge"),
                CONTROL_X + CONTROL_W + BADGE_X_OFFSET,
                y + 14
            )
        end
        if self._modified[row_path(entry)] then
            love.graphics.setColor(MODIFIED_COLOR)
            love.graphics.print(
                t("scene.template_editor.modified_badge"),
                CONTROL_X + CONTROL_W + BADGE_X_OFFSET,
                y + 30
            )
        end
        y = y + ROW_HEIGHT
    end
    love.graphics.setScissor()

    -- Header panel (opaque backdrop + divider so scrolled rows above
    -- HEADER_BOTTOM don't show through).
    love.graphics.setColor(PANEL_BG)
    love.graphics.rectangle("fill", 0, 0, w, HEADER_BOTTOM)
    love.graphics.setColor(PANEL_DIVIDER)
    love.graphics.rectangle("fill", 0, HEADER_BOTTOM - 1, w, 1)

    -- Title.
    love.graphics.setColor(TITLE_COLOR)
    local base_key = self._is_builtin and "scene.template_editor.title_builtin" -- i18n-ok: keys
        or "scene.template_editor.title"
    local title_text
    if self._template and self._template.name then
        title_text = t("scene.template_editor.title_with_name", {
            title = t(base_key),
            name = self._template.name,
        })
    else
        title_text = t(base_key)
    end
    love.graphics.printf(title_text, 0, TITLE_Y, w, "center")

    -- Parent badge.
    love.graphics.setColor(DESC_COLOR)
    local parent_id
    if self._is_builtin then
        parent_id = self._builtin_id
    elseif self._template then
        parent_id = self._template.parentTemplateId
    end
    if parent_id then
        local parent_label = t(builtin_label_key(parent_id))
        love.graphics.printf(
            t("scene.template_editor.parent_label", { name = parent_label }),
            0,
            PARENT_Y,
            w,
            "center"
        )
    end
    if self._is_builtin then
        love.graphics.setColor(MODIFIED_COLOR)
        local msg = t("scene.template_editor.builtin_readonly")
        love.graphics.printf(msg, 0, PARENT_Y + 18, w, "center")
    elseif self._template and self._template.parentMissing then
        love.graphics.setColor(MODIFIED_COLOR)
        local msg = t("scene.template_editor.parent_missing")
        love.graphics.printf(msg, 0, PARENT_Y + 18, w, "center")
    end

    -- Validation banner (under header backdrop, on top of divider).
    if self._dry_run_error then
        love.graphics.setColor(BANNER_COLOR)
        love.graphics.rectangle("fill", 0, HEADER_BOTTOM - BANNER_HEIGHT, w, BANNER_HEIGHT)
        love.graphics.setColor(BANNER_TEXT)
        local message = format_error(self._dry_run_error)
        love.graphics.printf(
            t("scene.template_editor.validation_banner", { message = message }),
            16,
            HEADER_BOTTOM - BANNER_HEIGHT + 6,
            w - 32,
            "left"
        )
    end

    -- Header buttons (top-right): Save / Cancel.
    self._save_button:draw()
    self._cancel_button:draw()

    -- Footer panel (opaque backdrop + divider).
    love.graphics.setColor(PANEL_BG)
    love.graphics.rectangle("fill", 0, h - FOOTER_HEIGHT, w, FOOTER_HEIGHT)
    love.graphics.setColor(PANEL_DIVIDER)
    love.graphics.rectangle("fill", 0, h - FOOTER_HEIGHT, w, 1)

    -- Footer buttons.
    self._reset_button:draw()
    self._duplicate_button:draw()
    self._delete_button:draw()

    -- Modal — full-screen overlay so it sits on top of header + footer.
    if self._modal == "confirm_delete" then
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
        love.graphics.printf(
            t("scene.template_editor.confirm_delete.prompt"),
            self._modal_panel.x + 24,
            self._modal_panel.y + 60,
            self._modal_panel.w - 48,
            "center"
        )
        for _, b in ipairs({ self._modal_yes, self._modal_no }) do
            b:draw()
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

local function dispatch_widgets(self, name, ...)
    for _, entry in ipairs(self._widgets) do
        local w = entry.widget
        if w and w[name] then
            w[name](w, ...)
        end
    end
end

function M:mousemoved(x, y, dx, dy)
    if self._modal then
        for _, b in ipairs({ self._modal_yes, self._modal_no }) do
            b:on_mousemoved(x, y)
        end
        return
    end
    dispatch_widgets(self, "on_mousemoved", x, y, dx, dy)
    self._save_button:on_mousemoved(x, y)
    self._cancel_button:on_mousemoved(x, y)
    self._reset_button:on_mousemoved(x, y)
    self._duplicate_button:on_mousemoved(x, y)
    self._delete_button:on_mousemoved(x, y)
end

function M:mousepressed(x, y, button)
    if self._modal then
        for _, b in ipairs({ self._modal_yes, self._modal_no }) do
            if b:on_mousepressed(x, y, button) then
                return
            end
        end
        return
    end
    for _, entry in ipairs(self._widgets) do
        if entry.widget and entry.widget:on_mousepressed(x, y, button) then
            return
        end
    end
    for _, b in ipairs({
        self._save_button,
        self._cancel_button,
        self._reset_button,
        self._duplicate_button,
        self._delete_button,
    }) do
        if b:on_mousepressed(x, y, button) then
            return
        end
    end
end

function M:mousereleased(x, y, button)
    if self._modal then
        for _, b in ipairs({ self._modal_yes, self._modal_no }) do
            b:on_mousereleased(x, y, button)
        end
        return
    end
    for _, entry in ipairs(self._widgets) do
        if entry.widget then
            entry.widget:on_mousereleased(x, y, button)
        end
    end
    for _, b in ipairs({
        self._save_button,
        self._cancel_button,
        self._reset_button,
        self._duplicate_button,
        self._delete_button,
    }) do
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
        self:_back()
    elseif key == "tab" then -- i18n-ok
        self._focus:advance(shift_held() and -1 or 1)
    elseif key == "down" or key == "right" then -- i18n-ok
        self._focus:advance(1)
    elseif key == "up" or key == "left" then -- i18n-ok
        self._focus:advance(-1)
    elseif key == "return" or key == "space" or key == "kpenter" then -- i18n-ok
        self._focus:activate()
    elseif key == "pageup" then -- i18n-ok
        self:_scroll_by_page(-1)
    elseif key == "pagedown" then -- i18n-ok
        self:_scroll_by_page(1)
    end
end

function M:_content_height()
    local h = 0
    local current_section
    for _, entry in ipairs(self._widgets) do
        if entry.section ~= current_section then
            current_section = entry.section
            h = h + SECTION_HEADER_HEIGHT
        end
        h = h + ROW_HEIGHT
    end
    return h
end

function M:_viewport_height()
    return math.max(0, self._last_h - HEADER_BOTTOM - FOOTER_HEIGHT - 12)
end

function M:_clamp_scroll()
    local content = self:_content_height()
    local view = self:_viewport_height()
    local max_offset = math.max(0, content - view)
    if self._scroll_y < 0 then
        self._scroll_y = 0
    elseif self._scroll_y > max_offset then
        self._scroll_y = max_offset
    end
end

function M:_scroll_by_page(direction)
    self._scroll_y = self._scroll_y + direction * self:_viewport_height()
    self:_clamp_scroll()
end

function M:wheelmoved(_dx, dy)
    if self._modal or not dy or dy == 0 then
        return
    end
    self._scroll_y = self._scroll_y - dy * 60
    self:_clamp_scroll()
end

return M
