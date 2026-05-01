-- Custom-template wrapper around RuleConfig. Pure-Lua bridge between a
-- user-saved variant and a JSON-encodable plain table. Lives in core/ so
-- the validation, clone, reset, serialization and id minting all run
-- under plain `lua` — the actual filesystem read/write happens in
-- app/templates/init.lua, which delegates to this module for the data
-- shape.
--
-- Schema versioning. The wrapper's `schemaVersion` is the contract for
-- the *outer* envelope; the inner ruleConfig carries its own
-- `schema_version` per core.rule_config. Future wrapper bumps add a
-- migration step in `try_new` before validation.
--
-- Wrapper schema:
--   {
--     schemaVersion     = 1,
--     id                = "<16 hex>",       -- stable across import/export
--     name              = "<user string>",
--     parentTemplateId  = "russian"|nil,    -- key into rule_config.builtins
--     starred           = false,
--     createdAt         = <unix seconds>,
--     updatedAt         = <unix seconds>,
--     ruleConfig        = { schema_version = 1, ... }   -- rule_config.to_json blob
--   }

local rule_config = require("core.rule_config")
local app_json = require("app.json")

local M = {}

M.SCHEMA_VERSION = 1

-- Failure helper. Mirrors core.rule_config's typed-error envelope so the
-- whole validation chain composes through one shape:
--   { ok = false, error = { code, ...context } }
local function failure(code, extra)
    local err = { code = code }
    if extra then
        for k, v in pairs(extra) do
            err[k] = v
        end
    end
    return { ok = false, error = err }
end

-- Deep copy of a plain table — used so a returned template never shares
-- structure with its source. Templates are mutated by the editor (toggle
-- by toggle in 3.5) and we don't want a write to a clone to bleed back
-- into the parent built-in's rule_config blob.
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

-- Plain-table snapshot of a frozen RuleConfig. Going through to_json /
-- decode keeps this in lockstep with whatever shape rule_config emits,
-- without reaching into its internal `plain_copy`.
local function rule_config_blob(config)
    return app_json.decode(rule_config.to_json(config))
end

-- Clock & RNG hooks ------------------------------------------------------
--
-- Both default to the system call but can be swapped in specs for
-- deterministic ids and timestamps. `_set_clock(nil)` and `_set_rng(nil)`
-- restore the defaults.

local function default_clock()
    return os.time()
end

local function default_rng()
    return math.random(0, 0xFFFF)
end

local clock = default_clock
local rng = default_rng
local seed_initialized = false

function M._set_clock(fn)
    clock = fn or default_clock
end

function M._set_rng(fn)
    rng = fn or default_rng
    if rng == default_rng then
        seed_initialized = false
    end
end

local function nibble()
    return rng() % 0x10000
end

function M.new_id()
    if rng == default_rng and not seed_initialized then
        math.randomseed(os.time() + (tonumber(tostring({}):match("0x(%x+)"), 16) or 0))
        seed_initialized = true
    end
    return string.format("%04x%04x%04x%04x", nibble(), nibble(), nibble(), nibble())
end

-- Validation -------------------------------------------------------------

local function validate_blob(blob)
    if type(blob) ~= "table" then
        return failure("not_a_table", { actual = type(blob) })
    end

    if blob.schemaVersion ~= M.SCHEMA_VERSION then
        return failure("unsupported_schema_version", {
            version = blob.schemaVersion,
            supported = M.SCHEMA_VERSION,
        })
    end

    if type(blob.id) ~= "string" or blob.id == "" then
        return failure("field_required", { path = "id" })
    end

    if type(blob.name) ~= "string" or blob.name == "" then
        return failure("field_required", { path = "name" })
    end

    if blob.parentTemplateId ~= nil and type(blob.parentTemplateId) ~= "string" then
        return failure("type_mismatch", {
            path = "parentTemplateId",
            expected = "string",
            actual = type(blob.parentTemplateId),
        })
    end

    if blob.starred ~= nil and type(blob.starred) ~= "boolean" then
        return failure("type_mismatch", {
            path = "starred",
            expected = "boolean",
            actual = type(blob.starred),
        })
    end

    if blob.createdAt ~= nil and type(blob.createdAt) ~= "number" then
        return failure("type_mismatch", {
            path = "createdAt",
            expected = "number",
            actual = type(blob.createdAt),
        })
    end

    if blob.updatedAt ~= nil and type(blob.updatedAt) ~= "number" then
        return failure("type_mismatch", {
            path = "updatedAt",
            expected = "number",
            actual = type(blob.updatedAt),
        })
    end

    if blob.ruleConfig == nil then
        return failure("field_required", { path = "ruleConfig" })
    end

    if type(blob.ruleConfig) ~= "table" then
        return failure("type_mismatch", {
            path = "ruleConfig",
            expected = "table",
            actual = type(blob.ruleConfig),
        })
    end

    local inner = rule_config.try_new(blob.ruleConfig)
    if not inner.ok then
        return failure("invalid_rule_config", { cause = inner.error })
    end

    return { ok = true }
end

local function normalize(blob, now)
    return {
        schemaVersion = M.SCHEMA_VERSION,
        id = blob.id,
        name = blob.name,
        parentTemplateId = blob.parentTemplateId,
        starred = blob.starred == true,
        createdAt = blob.createdAt or now,
        updatedAt = blob.updatedAt or now,
        ruleConfig = deep_copy(blob.ruleConfig),
    }
end

-- Public API -------------------------------------------------------------

function M.try_new(blob)
    local v = validate_blob(blob)
    if not v.ok then
        return v
    end
    return { ok = true, template = normalize(blob, clock()) }
end

function M.dry_run(blob)
    local v = validate_blob(blob)
    if not v.ok then
        return { ok = false, error = v.error }
    end
    return { ok = true }
end

function M.to_json(template)
    -- Re-normalize on the way out so absent optional fields still produce
    -- a stable output shape (same key set every time).
    local out = {
        schemaVersion = M.SCHEMA_VERSION,
        id = template.id,
        name = template.name,
        parentTemplateId = template.parentTemplateId,
        starred = template.starred == true,
        createdAt = template.createdAt,
        updatedAt = template.updatedAt,
        ruleConfig = template.ruleConfig,
    }
    return app_json.encode(out)
end

function M.from_json(s)
    if type(s) ~= "string" then
        return failure("type_mismatch", {
            path = "json",
            expected = "string",
            actual = type(s),
        })
    end
    local decoded, err = app_json.decode(s)
    if decoded == nil then
        return failure("json_decode_failed", { details = tostring(err) })
    end
    return M.try_new(decoded)
end

function M.clone_from_builtin(builtin_id, opts)
    opts = opts or {}
    local source = rule_config.builtins[builtin_id]
    if source == nil then
        return failure("unknown_parent", { parentTemplateId = builtin_id })
    end
    local name = opts.name
    if type(name) ~= "string" or name == "" then
        return failure("field_required", { path = "name" })
    end
    local now = opts.now or clock()
    local id = opts.id or M.new_id()
    return {
        ok = true,
        template = {
            schemaVersion = M.SCHEMA_VERSION,
            id = id,
            name = name,
            parentTemplateId = builtin_id,
            starred = false,
            createdAt = now,
            updatedAt = now,
            ruleConfig = rule_config_blob(source),
        },
    }
end

function M.reset_to_parent(template, builtins, now)
    if type(template) ~= "table" then
        return failure("not_a_table", { actual = type(template) })
    end
    local parent_id = template.parentTemplateId
    if parent_id == nil then
        return failure("parent_missing", {})
    end
    local parent = builtins and builtins[parent_id] or nil
    if parent == nil then
        return failure("parent_missing", { parentTemplateId = parent_id })
    end
    local stamp = now or clock()
    return {
        ok = true,
        template = {
            schemaVersion = M.SCHEMA_VERSION,
            id = template.id,
            name = template.name,
            parentTemplateId = parent_id,
            starred = template.starred == true,
            createdAt = template.createdAt or stamp,
            updatedAt = stamp,
            ruleConfig = rule_config_blob(parent),
        },
    }
end

function M.with_rule_config(template, rule_config_blob_value, now)
    return {
        schemaVersion = M.SCHEMA_VERSION,
        id = template.id,
        name = template.name,
        parentTemplateId = template.parentTemplateId,
        starred = template.starred == true,
        createdAt = template.createdAt,
        updatedAt = now or clock(),
        ruleConfig = deep_copy(rule_config_blob_value),
    }
end

-- Returns a fresh sorted array. Starred templates first, then by name
-- ascending (locale-naive `<`); ties broken by id ascending. The data
-- module surfaces the helper because the picker UI in 3.5 uses it as a
-- default; the UI may layer locale-aware sort on top.
function M.default_sort(list)
    local out = {}
    for i, t in ipairs(list) do
        out[i] = t
    end
    table.sort(out, function(a, b)
        local sa = a.starred == true
        local sb = b.starred == true
        if sa ~= sb then
            return sa
        end
        if a.name ~= b.name then
            return tostring(a.name) < tostring(b.name)
        end
        return tostring(a.id) < tostring(b.id)
    end)
    return out
end

return M
