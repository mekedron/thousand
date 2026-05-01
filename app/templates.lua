-- Custom rule-template store. One JSON file (`templates.json`) at the
-- love.filesystem root holds the user's library of cloned-and-edited
-- RuleConfig variants; the built-in templates remain immutable factory
-- data exposed read-only by the same API.
--
-- Pairs with core/templates.lua (validation, serialization, clone,
-- reset, id minting) the same way app/auto_save.lua pairs with
-- core/auto_save.lua: this module owns the filesystem I/O and the
-- in-memory list, the core module owns the data shape.
--
-- API
--   M.list()                  → { templates = [...], builtins = [...] }
--   M.get(id)                 → template?
--   M.create(opts)            → { ok, template, error }
--   M.update(id, blob)        → { ok, template, error }
--   M.rename(id, name)        → { ok, template, error }
--   M.delete(id)              → { ok, error }
--   M.duplicate(id)           → { ok, template, error }
--   M.set_starred(id, bool)   → { ok, template, error }
--   M.reset(id)               → { ok, template, error }
--   M.export(id)              → { ok, json, error }
--   M.import(json_string)     → { ok, template, error }
--   M.last_load_error()       → { code, dropped_count? }?
--
-- Test hooks: M._set_storage(reader, writer), M._reset(),
-- M._reload(), M._set_clock(fn), M._set_rng(fn).

local app_json = require("app.json")
local core_templates = require("core.templates")
local rule_config = require("core.rule_config")
local settings = require("app.settings")
local i18n = require("app.i18n")

local M = {}

local TEMPLATES_PATH = "templates.json"

-- Module state ----------------------------------------------------------

local current = {} -- ordered array of templates
local loaded = false
local last_error = nil

-- Storage hooks. Both are nil until install_default_storage decides
-- whether love.filesystem is available, or a test replaces them.
local read_fn
local write_fn

local function install_default_storage()
    if read_fn and write_fn then
        return
    end
    if love and love.filesystem then
        read_fn = function(path)
            local info = love.filesystem.getInfo and love.filesystem.getInfo(path)
            if not info then
                return nil
            end
            local content, err = love.filesystem.read(path)
            if not content then
                return nil, err
            end
            return content
        end
        write_fn = function(path, content)
            return love.filesystem.write(path, content)
        end
    else
        -- No engine, no test override → in-memory transient storage so a
        -- stray require from outside a test doesn't blow up.
        local memory
        read_fn = function()
            return memory
        end
        write_fn = function(_, content)
            memory = content
            return true
        end
    end
end

-- Load --------------------------------------------------------------------
--
-- The wrapper file shape is { schemaVersion = 1, templates = [ ... ] }.
-- A whole-file failure (corrupt JSON, schemaVersion mismatch, root not a
-- table) silently falls back to an empty list and surfaces a code via
-- last_load_error(). A per-template failure inside an otherwise-valid
-- file drops the bad row and increments dropped_count; the rest load.

local function load_from_storage()
    install_default_storage()
    last_error = nil
    current = {}

    local content = read_fn(TEMPLATES_PATH)
    if not content then
        return
    end

    local decoded, err = app_json.decode(content)
    if decoded == nil then
        last_error = { code = "json_decode_failed", details = tostring(err) }
        return
    end
    if type(decoded) ~= "table" then
        last_error = { code = "not_a_table", actual = type(decoded) }
        return
    end
    if decoded.schemaVersion ~= core_templates.SCHEMA_VERSION then
        last_error = {
            code = "unsupported_schema_version",
            version = decoded.schemaVersion,
            supported = core_templates.SCHEMA_VERSION,
        }
        return
    end
    if type(decoded.templates) ~= "table" then
        return -- Empty list is fine.
    end

    local dropped = 0
    for _, raw in ipairs(decoded.templates) do
        local result = core_templates.try_new(raw)
        if result.ok then
            current[#current + 1] = result.template
        else
            dropped = dropped + 1
        end
    end
    if dropped > 0 then
        last_error = { code = "per_template_invalid", dropped_count = dropped }
    end
end

local function lazy_load()
    if loaded then
        return
    end
    loaded = true
    load_from_storage()
end

local function persist()
    install_default_storage()
    local out = {
        schemaVersion = core_templates.SCHEMA_VERSION,
        templates = current,
    }
    write_fn(TEMPLATES_PATH, app_json.encode(out))
end

local function find(id)
    for i, t in ipairs(current) do
        if t.id == id then
            return i, t
        end
    end
    return nil, nil
end

local function failure(code, extra)
    local err = { code = code }
    if extra then
        for k, v in pairs(extra) do
            err[k] = v
        end
    end
    return { ok = false, error = err }
end

local function builtins_listing()
    local out = {}
    -- Stable order: alphabetical by id, with the canonical Russian first
    -- so the picker shows the default at the top.
    local names = {}
    for name, _ in pairs(rule_config.builtins) do
        if name ~= "russian" then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    table.insert(names, 1, "russian")
    for i, name in ipairs(names) do
        out[i] = {
            id = name,
            name = name,
            kind = "builtin",
        }
    end
    return out
end

local function with_parent_missing_flag(template)
    -- Returned record is a shallow copy with a transient flag; the
    -- on-disk template stays clean.
    local out = {}
    for k, v in pairs(template) do
        out[k] = v
    end
    local parent_id = template.parentTemplateId
    if parent_id ~= nil and rule_config.builtins[parent_id] == nil then
        out.parentMissing = true
    end
    return out
end

-- Public API -------------------------------------------------------------

function M.list()
    lazy_load()
    local templates_out = {}
    for i, t in ipairs(current) do
        templates_out[i] = with_parent_missing_flag(t)
    end
    return {
        templates = templates_out,
        builtins = builtins_listing(),
    }
end

function M.get(id)
    lazy_load()
    local _, t = find(id)
    if t == nil then
        return nil
    end
    return with_parent_missing_flag(t)
end

function M.create(opts)
    lazy_load()
    opts = opts or {}
    local r = core_templates.clone_from_builtin(opts.fromBuiltin, {
        name = opts.name,
        id = opts.id,
        now = opts.now,
    })
    if not r.ok then
        return r
    end
    current[#current + 1] = r.template
    persist()
    return r
end

function M.update(id, rule_config_blob)
    lazy_load()
    local idx, existing = find(id)
    if existing == nil then
        return failure("unknown_template", { id = id })
    end
    -- Build the candidate wrapper and run it through validation. This
    -- catches both bad-shape blobs and deferred-toggle changes via the
    -- inner rule_config.try_new.
    local candidate = {
        schemaVersion = core_templates.SCHEMA_VERSION,
        id = existing.id,
        name = existing.name,
        parentTemplateId = existing.parentTemplateId,
        starred = existing.starred,
        createdAt = existing.createdAt,
        updatedAt = existing.updatedAt,
        ruleConfig = rule_config_blob,
    }
    local result = core_templates.try_new(candidate)
    if not result.ok then
        return result
    end
    local next_template = core_templates.with_rule_config(existing, rule_config_blob)
    current[idx] = next_template
    persist()
    return { ok = true, template = next_template }
end

function M.rename(id, new_name)
    lazy_load()
    if type(new_name) ~= "string" or new_name == "" then -- i18n-ok: type guard
        return failure("field_required", { path = "name" })
    end
    local idx, existing = find(id)
    if existing == nil then
        return failure("unknown_template", { id = id })
    end
    local next_template = {}
    for k, v in pairs(existing) do
        next_template[k] = v
    end
    next_template.name = new_name
    next_template.updatedAt = (M._clock_for_test or os.time)()
    current[idx] = next_template
    persist()
    return { ok = true, template = next_template }
end

function M.delete(id)
    lazy_load()
    local idx = find(id)
    if idx == nil then
        return failure("unknown_template", { id = id })
    end
    table.remove(current, idx)
    persist()
    return { ok = true }
end

function M.duplicate(id)
    lazy_load()
    local _, existing = find(id)
    if existing == nil then
        return failure("unknown_template", { id = id })
    end
    local now = (M._clock_for_test or os.time)()
    local copy = {
        schemaVersion = core_templates.SCHEMA_VERSION,
        id = core_templates.new_id(),
        name = i18n.t("templates.duplicate_suffix", { name = existing.name }),
        parentTemplateId = existing.parentTemplateId,
        starred = existing.starred == true,
        createdAt = now,
        updatedAt = now,
        ruleConfig = existing.ruleConfig,
    }
    -- Deep-copy the rule_config blob so subsequent edits to the copy
    -- don't bleed back into the source.
    local fresh_blob = app_json.decode(app_json.encode(existing.ruleConfig))
    copy.ruleConfig = fresh_blob
    current[#current + 1] = copy
    persist()
    return { ok = true, template = copy }
end

function M.set_starred(id, starred)
    lazy_load()
    local idx, existing = find(id)
    if existing == nil then
        return failure("unknown_template", { id = id })
    end
    local next_template = {}
    for k, v in pairs(existing) do
        next_template[k] = v
    end
    next_template.starred = starred == true
    next_template.updatedAt = (M._clock_for_test or os.time)()
    current[idx] = next_template
    persist()
    return { ok = true, template = next_template }
end

function M.reset(id)
    lazy_load()
    local idx, existing = find(id)
    if existing == nil then
        return failure("unknown_template", { id = id })
    end
    local r = core_templates.reset_to_parent(existing, rule_config.builtins)
    if not r.ok then
        return r
    end
    current[idx] = r.template
    persist()
    return r
end

function M.export(id)
    lazy_load()
    local _, existing = find(id)
    if existing == nil then
        return failure("unknown_template", { id = id })
    end
    return { ok = true, json = core_templates.to_json(existing) }
end

function M.import(json_string)
    lazy_load()
    local r = core_templates.from_json(json_string)
    if not r.ok then
        return r
    end
    -- Always mint a fresh id so import-then-export-then-import doesn't
    -- collide and so receiving the same shared file twice produces two
    -- distinct rows.
    local imported = r.template
    imported.id = core_templates.new_id()
    current[#current + 1] = imported
    persist()
    return { ok = true, template = imported }
end

function M.last_load_error()
    lazy_load()
    return last_error
end

-- Active template id ----------------------------------------------------
--
-- The picker writes the chosen template's id to settings; the menu's
-- "New Game" reads it back through resolve_active_config to spin up a
-- fresh session under the right rules.

function M.get_active_id()
    return settings.get("active_template_id")
end

function M.set_active_id(id)
    settings.set("active_template_id", id)
end

function M.resolve_active_config()
    lazy_load()
    local id = settings.get("active_template_id")
    if type(id) ~= "string" then
        return rule_config.canonical_russian
    end
    local builtin = rule_config.builtins[id]
    if builtin ~= nil then
        return builtin
    end
    local _, custom = find(id)
    if custom == nil then
        return rule_config.canonical_russian
    end
    local r = rule_config.try_new(custom.ruleConfig)
    if not r.ok then
        return rule_config.canonical_russian
    end
    return r.config
end

-- Test hooks -------------------------------------------------------------

function M._set_storage(reader, writer)
    read_fn = reader
    write_fn = writer
    loaded = false
    current = {}
    last_error = nil
end

function M._reset()
    read_fn = nil
    write_fn = nil
    loaded = false
    current = {}
    last_error = nil
end

function M._reload()
    loaded = false
    current = {}
    last_error = nil
    lazy_load()
end

function M._set_clock(fn)
    M._clock_for_test = fn
    core_templates._set_clock(fn)
end

function M._set_rng(fn)
    core_templates._set_rng(fn)
end

return M
