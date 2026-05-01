-- The Thousand settings module. Holds the small collection of
-- per-install user preferences that need to survive a relaunch — only
-- one entry today (the hot-seat privacy curtain), but designed so
-- Phase 4's full Settings screen drops more keys onto the same shape.
--
-- Persistence:
--   * `settings.json` under `love.filesystem.getSaveDirectory()`,
--     written through the engine's sandboxed filesystem so iOS and
--     Android sandboxes work.
--   * JSON document with a `schemaVersion` field — corrupt or
--     incompatible files fall back to defaults rather than crashing.
--   * Save on every `set`. There is no in-memory dirty state we'd
--     lose by writing every time; the file is tiny.
--
-- Test override: `settings._set_storage(read_fn, write_fn)` swaps the
-- filesystem hooks for in-memory closures so unit tests don't touch
-- love.filesystem and don't depend on a Love2D runtime.

local json = require("app.json")

local M = {}

local SETTINGS_PATH = "settings.json"

local SCHEMA_VERSION = 1

local DEFAULTS = {
    schemaVersion = SCHEMA_VERSION,
    -- Show the pass-to-next-player curtain between turns. Default ON
    -- because the hot-seat case is "three humans share a device" — the
    -- curtain is the privacy guarantee. Disable for testing or for a
    -- single human flipping through every seat themselves.
    hot_seat_privacy = true,
    -- Identifier of the rule template a fresh "New Game" should use.
    -- Defaults to the canonical Russian built-in; the picker writes a
    -- different built-in or a custom-template id here when the player
    -- presses "Use this template".
    active_template_id = "russian",
}

local function copy(t)
    local out = {}
    for k, v in pairs(t) do
        out[k] = v
    end
    return out
end

-- Module state -----------------------------------------------------------

local current = copy(DEFAULTS)
local loaded = false

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
        -- No engine, no test override → in-memory transient storage.
        -- Tests should always call _set_storage; this branch keeps a
        -- stray require from blowing up.
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

-- Validation: the loaded blob must be a table with a known
-- schemaVersion. Anything else returns nil and the caller falls back
-- to defaults. Future schemaVersion bumps add a migration step here;
-- for now there is exactly one valid version.
local function validate(blob)
    if type(blob) ~= "table" then
        return nil
    end
    if blob.schemaVersion ~= SCHEMA_VERSION then
        return nil
    end
    local out = copy(DEFAULTS)
    if type(blob.hot_seat_privacy) == "boolean" then
        out.hot_seat_privacy = blob.hot_seat_privacy
    end
    if type(blob.active_template_id) == "string" then
        out.active_template_id = blob.active_template_id
    end
    return out
end

local function lazy_load()
    if loaded then
        return
    end
    install_default_storage()
    loaded = true
    local content = read_fn(SETTINGS_PATH)
    if not content then
        return
    end
    local blob = json.decode(content)
    local validated = validate(blob)
    if validated then
        current = validated
    end
end

local function persist()
    install_default_storage()
    write_fn(SETTINGS_PATH, json.encode(current))
end

-- Public API -------------------------------------------------------------

function M.get(key)
    lazy_load()
    return current[key]
end

function M.set(key, value)
    lazy_load()
    if DEFAULTS[key] == nil then
        error("settings.set: unknown key " .. tostring(key), 2)
    end
    current[key] = value
    persist()
end

-- Reload from storage. Useful after an external change (in tests, or
-- a future sync flow). Resets the lazy-load flag so the next read goes
-- through the storage hook.
function M.reload()
    loaded = false
    current = copy(DEFAULTS)
    lazy_load()
end

-- Reset to defaults and persist.
function M.reset()
    install_default_storage()
    current = copy(DEFAULTS)
    loaded = true
    persist()
end

-- Test-only: drop module state without touching storage. Used by
-- specs to start from a clean slate.
function M._reset()
    current = copy(DEFAULTS)
    loaded = false
    read_fn = nil
    write_fn = nil
end

-- Test-only: replace the love.filesystem hooks with in-memory closures
-- so a spec can drive load/save without a Love2D runtime.
function M._set_storage(reader, writer)
    read_fn = reader
    write_fn = writer
    loaded = false
end

-- Test-only: surface defaults so the schema-bump test can pin them.
function M._defaults()
    return copy(DEFAULTS)
end

return M
