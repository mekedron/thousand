-- The Thousand i18n module.
--
-- Every player-visible string flows through `t(key, params?)`. Locale tables
-- live in assets/i18n/<code>.lua and are plain Lua tables of key → string.
-- Phase 0 ships stubs for en, ru, pl, uk; ru/pl/uk mirror en until Phase 8.
--
-- Interpolation: i18n.t("hello", { name = "Alice" }) substitutes %{name}.
--
-- Phase 0 returns the bare key when the active locale is missing it. The
-- en-fallback + log-once behaviour is added in the next task.

local i18n = {}

-- Module-level state. `loaded` caches locale tables so the gsub-heavy
-- t() path avoids re-resolving require() each call.
local loaded = {}
local active_locale = "en"

local function load_locale(code)
    if loaded[code] ~= nil then
        return loaded[code] or nil
    end
    local ok, result = pcall(require, "assets.i18n." .. code)
    if ok and type(result) == "table" then
        loaded[code] = result
        return result
    end
    loaded[code] = false -- cache the negative so repeated lookups are cheap
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
    local tbl = load_locale(active_locale)
    if tbl then
        local val = tbl[key]
        if type(val) == "string" then
            return interpolate(val, params)
        end
    end
    return key
end

-- Test-only escape hatch: drops the locale cache and resets active locale.
-- Not part of the runtime API; kept under an underscore so it stays out of
-- normal autocomplete and grep-able audits.
function i18n._reset()
    loaded = {}
    active_locale = "en"
end

return i18n
