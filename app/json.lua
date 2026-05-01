-- Tiny JSON encoder / decoder for local persistence files. Sized to the
-- needs of small flat config and save documents — the kind that fit in
-- a few hundred bytes — and intentionally not a general JSON library.
--
-- Supported on encode and decode:
--   * `nil` ↔ `null`
--   * booleans
--   * finite numbers (integers print without a decimal point)
--   * strings, with escapes for `"` `\` `\n` `\r` `\t`
--   * tables of (string → value), i.e. JSON objects, including nesting
--
-- Not supported:
--   * arrays — we have no need yet, and adding them later is additive
--   * NaN / ±Infinity — encode raises, decode does not produce them
--   * Unicode escapes — strings round-trip as their literal byte content
--
-- The architecture doc mandates JSON for on-disk persistence. This module
-- is the smallest implementation that delivers that without a third-party
-- dependency. Auto-save (Phase 2 / Phase 4) reuses it.
--
-- All quoted literals in this file are JSON syntax tokens, gsub patterns,
-- or programmer-facing diagnostics raised via error() — none reach the
-- player, hence the broad `-- i18n-ok` annotations.

local M = {}

-- Encoder ----------------------------------------------------------------

local encode_value

local function encode_string(s)
    -- The five gsub literals below are JSON-escape syntax, not text. -- i18n-ok
    local out = s:gsub("\\", "\\\\") -- i18n-ok: JSON escape
    out = out:gsub('"', '\\"') -- i18n-ok: JSON escape
    out = out:gsub("\n", "\\n") -- i18n-ok: JSON escape
    out = out:gsub("\r", "\\r") -- i18n-ok: JSON escape
    out = out:gsub("\t", "\\t") -- i18n-ok: JSON escape
    return '"' .. out .. '"' -- i18n-ok: JSON delimiter
end

local function encode_number(n)
    if n ~= n or n == math.huge or n == -math.huge then
        error("json.encode: non-finite number", 2)
    end
    if n == math.floor(n) and math.abs(n) < 1e15 then
        return string.format("%d", n)
    end
    return string.format("%.14g", n)
end

local function encode_object(t)
    local keys = {}
    for k in pairs(t) do
        if type(k) ~= "string" then
            error("json.encode: only string-keyed tables are supported", 3)
        end
        keys[#keys + 1] = k
    end
    -- Stable key order — small files diff cleanly across saves and tests
    -- can pin the exact serialised output.
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = encode_string(k) .. ":" .. encode_value(t[k])
    end
    return "{" .. table.concat(parts, ",") .. "}" -- i18n-ok: JSON delimiters
end

encode_value = function(v)
    local tv = type(v)
    if tv == "nil" then
        return "null"
    elseif tv == "boolean" then
        return v and "true" or "false" -- i18n-ok: JSON literal
    elseif tv == "number" then
        return encode_number(v)
    elseif tv == "string" then
        return encode_string(v)
    elseif tv == "table" then
        return encode_object(v)
    end
    error("json.encode: unsupported type " .. tv, 2)
end

function M.encode(v)
    return encode_value(v)
end

-- Decoder ----------------------------------------------------------------
--
-- Parser state is passed explicitly through every helper so the module
-- has no reentrancy concerns. Every diagnostic raised here is wrapped
-- in `error(...)` directly so the i18n check skips the message.

local function new_state(s)
    return { src = s, pos = 1 }
end

local function peek(state)
    return state.src:sub(state.pos, state.pos)
end

local function skip_ws(state)
    while true do
        local c = peek(state)
        -- The four whitespace chars below are syntax, not user text. -- i18n-ok
        if c == " " or c == "\t" or c == "\n" or c == "\r" then -- i18n-ok: whitespace
            state.pos = state.pos + 1
        else
            return
        end
    end
end

local parse_value

local function parse_string(state)
    if peek(state) ~= '"' then
        error("json.decode: expected string at position " .. state.pos, 3)
    end
    state.pos = state.pos + 1
    local start = state.pos
    while true do
        local c = peek(state)
        if c == "" then
            error("json.decode: unterminated string at position " .. state.pos, 3)
        elseif c == "\\" then
            state.pos = state.pos + 2
        elseif c == '"' then
            local raw = state.src:sub(start, state.pos - 1)
            state.pos = state.pos + 1
            -- Single-pass unescape via a callback so we don't need a
            -- placeholder for `\\`. An earlier two-step approach with
            -- "\0\1" placeholders broke under LuaJIT, which treats a
            -- NUL byte in the pattern as the end of the pattern and
            -- matches at every position.
            local out = raw:gsub("\\(.)", function(esc)
                if esc == "n" then
                    return "\n"
                end
                if esc == "r" then
                    return "\r"
                end
                if esc == "t" then
                    return "\t"
                end
                -- Any other escape (\\ \" \/ ...) maps to the literal
                -- second character.
                return esc
            end)
            return out
        else
            state.pos = state.pos + 1
        end
    end
end

local function parse_number(state)
    local start = state.pos
    if peek(state) == "-" then
        state.pos = state.pos + 1
    end
    while true do
        local c = peek(state)
        if c == "" or not c:match("[%d%.eE%+%-]") then -- i18n-ok: char-class pattern
            break
        end
        state.pos = state.pos + 1
    end
    local raw = state.src:sub(start, state.pos - 1)
    local n = tonumber(raw)
    if not n then
        error("json.decode: bad number " .. raw .. " at position " .. state.pos, 3)
    end
    return n
end

local function parse_keyword(state, keyword, value)
    local len = #keyword
    if state.src:sub(state.pos, state.pos + len - 1) ~= keyword then
        error("json.decode: expected " .. keyword .. " at position " .. state.pos, 3)
    end
    state.pos = state.pos + len
    return value
end

local function parse_object(state)
    if peek(state) ~= "{" then
        error("json.decode: expected { at position " .. state.pos, 3)
    end
    state.pos = state.pos + 1
    skip_ws(state)
    local out = {}
    if peek(state) == "}" then
        state.pos = state.pos + 1
        return out
    end
    while true do
        skip_ws(state)
        local k = parse_string(state)
        skip_ws(state)
        if peek(state) ~= ":" then
            error("json.decode: expected : at position " .. state.pos, 3)
        end
        state.pos = state.pos + 1
        skip_ws(state)
        out[k] = parse_value(state)
        skip_ws(state)
        local c = peek(state)
        if c == "," then
            state.pos = state.pos + 1
        elseif c == "}" then
            state.pos = state.pos + 1
            return out
        else
            error("json.decode: expected , or } at position " .. state.pos, 3)
        end
    end
end

parse_value = function(state)
    skip_ws(state)
    local c = peek(state)
    if c == '"' then
        return parse_string(state)
    elseif c == "{" then
        return parse_object(state)
    elseif c == "t" then
        return parse_keyword(state, "true", true)
    elseif c == "f" then
        return parse_keyword(state, "false", false)
    elseif c == "n" then
        return parse_keyword(state, "null", nil)
    elseif c == "-" or c:match("%d") then -- i18n-ok: pattern chars
        return parse_number(state)
    end
    local seen = c == "" and "<EOF>" or c -- i18n-ok: dev diagnostic
    error("json.decode: unexpected character " .. seen .. " at position " .. state.pos, 3)
end

-- Decode `s`. Returns the value plus a non-nil error on failure rather
-- than raising: callers handling user-supplied or on-disk data can fall
-- back without wrapping every read in `pcall`.
function M.decode(s)
    if type(s) ~= "string" then
        return nil, "json.decode: input must be a string" -- i18n-ok: dev diagnostic
    end
    local state = new_state(s)
    local ok, result = pcall(parse_value, state)
    if not ok then
        return nil, result
    end
    skip_ws(state)
    if state.pos <= #state.src then
        return nil, "json.decode: trailing characters at position " .. state.pos -- i18n-ok
    end
    return result
end

return M
