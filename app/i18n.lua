-- The Thousand i18n module.
--
-- Every player-visible string flows through `t(key, params?)`. Locale tables
-- live in assets/i18n/<code>.lua and are plain Lua tables of key → string.
-- Phase 0 ships stubs for en, ru, pl, uk; ru/pl/uk mirror en until Phase 8.
--
-- Interpolation: i18n.t("hello", { name = "Alice" }) substitutes %{name}.
--
-- Fallback: when a key is missing in the active locale, t() returns the en
-- value if one exists, and logs the gap once per (locale, key) pair so a
-- translator can see what still needs work without flooding the console.

local i18n = {}

local FALLBACK_LOCALE = "en"

-- Module-level state.
local loaded = {}
local active_locale = FALLBACK_LOCALE
local missing_logged = {}
local logger = function(msg)
    print(msg)
end

local function load_locale(code)
    if loaded[code] ~= nil then
        return loaded[code] or nil
    end
    local ok, result = pcall(require, "assets.i18n." .. code)
    if ok and type(result) == "table" then
        loaded[code] = result
        return result
    end
    loaded[code] = false
    return nil
end

local function interpolate(s, params)
    if params == nil then
        return s
    end
    return (
        s:gsub("%%{(%w+)}", function(name)
            local v = params[name]
            if v ~= nil then
                return tostring(v)
            end
            return "%{" .. name .. "}"
        end)
    )
end

local function log_missing_once(key, locale)
    local id = locale .. "\0" .. key
    if missing_logged[id] then
        return
    end
    missing_logged[id] = true
    logger(string.format("[i18n] missing key %q in locale %q", key, locale))
end

function i18n.set_locale(code)
    assert(type(code) == "string", "locale code must be a string")
    if not load_locale(code) then
        error("locale not found: " .. code, 2)
    end
    active_locale = code
end

function i18n.get_locale()
    return active_locale
end

function i18n.t(key, params)
    assert(type(key) == "string", "translation key must be a string")
    local active = load_locale(active_locale)
    if active then
        local val = active[key]
        if type(val) == "string" then
            return interpolate(val, params)
        end
    end
    -- Active locale doesn't have the key. Log the gap and try en.
    log_missing_once(key, active_locale)
    if active_locale ~= FALLBACK_LOCALE then
        local fallback = load_locale(FALLBACK_LOCALE)
        if fallback then
            local val = fallback[key]
            if type(val) == "string" then
                return interpolate(val, params)
            end
        end
        log_missing_once(key, FALLBACK_LOCALE)
    end
    return key
end

-- Test-only escape hatch: drops all module state. Not part of the runtime API.
function i18n._reset()
    loaded = {}
    active_locale = FALLBACK_LOCALE
    missing_logged = {}
    logger = function(msg)
        print(msg)
    end
end

-- Test-only: install a custom logger so specs can capture missing-key
-- diagnostics without spamming the test runner.
function i18n._set_logger(fn)
    if fn == nil then
        logger = function(msg)
            print(msg)
        end
    else
        assert(type(fn) == "function", "logger must be a function")
        logger = fn
    end
end

-- Test-only: inject a locale table directly into the cache so a spec can
-- exercise fallback paths without depending on the production stub
-- contents (which currently mirror en exactly).
function i18n._set_locale_table(code, tbl)
    assert(type(code) == "string", "locale code must be a string")
    assert(tbl == nil or type(tbl) == "table", "locale table must be nil or table")
    loaded[code] = tbl or false
end

return i18n
