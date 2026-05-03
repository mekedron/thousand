-- Phase 4.2: per-seat bot difficulty enum.
--
-- A standalone module so the enum and validator have a single source of
-- truth across the codebase: `app.session` carries it on every session,
-- `core.auto_save` round-trips it, the bot driver passes it to choosers
-- at tick time, and the new-game scene picks it per seat. Phase 7's
-- `CharacterPreset.default_difficulty` will reuse the same enum without
-- pulling in `app.session`.
--
-- Algorithm-vs-LLM firewall: this module imports nothing from `ui.*`
-- or `app.llm.*`. Enforced by tests/spec/lint/firewall_spec.lua.

local M = {}

M.VALUES = { "easy", "normal", "hard" } -- i18n-ok: difficulty enum
M.DEFAULT = "normal" -- i18n-ok: difficulty enum

local VALUE_SET = {}
for _, v in ipairs(M.VALUES) do
    VALUE_SET[v] = true
end

-- Validate a per-seat difficulty array against `count` seats. Returns a
-- new copy on success so callers cannot mutate the input through the
-- stored field. nil is allowed and round-trips as nil — Session and
-- save callers treat nil as "default to M.DEFAULT per seat at use site".
function M.validate(value, count, where)
    if value == nil then
        return nil
    end
    if type(value) ~= "table" then
        error(where .. ": seat_difficulties must be a table or nil", 3)
    end
    if #value ~= count then
        error(
            where
                .. ": seat_difficulties length " -- i18n-ok: developer assertion
                .. tostring(#value)
                .. " disagrees with players.count " -- i18n-ok: developer assertion
                .. tostring(count),
            3
        )
    end
    local out = {}
    for i = 1, count do
        local d = value[i]
        if not VALUE_SET[d] then
            error(
                where
                    .. ": seat_difficulties[" -- i18n-ok: developer assertion
                    .. tostring(i)
                    .. "] must be one of " -- i18n-ok: developer assertion
                    .. "'easy' | 'normal' | 'hard'", -- i18n-ok: developer assertion
                3
            )
        end
        out[i] = d
    end
    return out
end

return M
