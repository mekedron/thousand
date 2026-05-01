-- The Thousand RuleConfig value object.
--
-- A `RuleConfig` is the single source of truth for every variable rule in
-- the engine: card values, talon size, bid increments, marriage values,
-- trick-play strictness, scoring rounding, barrel rules, target score.
-- Phase 1 ships exactly one instance — `canonical_russian` — but the schema
-- is shaped so Phase 3 variants (Polish, Ukrainian, 2-/4-player, custom)
-- plug in as data only, with no engine code changes.
--
-- Schema. The private `SCHEMA` table is the contract: every field declares
-- its lua_type, default, status (implemented / selectable / deferred), and
-- where applicable, allowed values, min/max, or required nested keys. New
-- toggles in 3.2 land as new SCHEMA entries; the validator below adapts
-- automatically. `M.schema_for(path)` exposes a descriptor for the UI and
-- tests; `M.try_new` and `M.from_json` use the same descriptors to validate.
--
-- Status flags:
--   * "implemented" — the engine reads the field; UI may set any in-range
--     value.
--   * "selectable"  — same as "implemented" for validation; reserved as a
--     UI hint. Phase 3.2 starts using this for toggles whose UI affordances
--     are settled but whose engine behaviour is still landing.
--   * "deferred"    — only the schema's `default` value is accepted. The
--     framework's promise that the engine's reads remain backed by canonical
--     values until a future task flips the flag.
--
-- JSON. `M.to_json(config)` and `M.from_json(string)` round-trip a config
-- through JSON via app/json. The blob includes `schema_version`; mismatched
-- versions are rejected (Phase 9 owns forward migrations).
--
-- Errors. `M.try_new` and `M.from_json` return
--   { ok = true, config = <frozen> }
-- or
--   { ok = false, error = { code = "...", ...context } }
-- following the same envelope core/auction.lua, core/tricks.lua, etc. use.
-- Codes are stable strings; the UI maps them to "rule_config.error.<code>"
-- in the locale tables. `M.new` keeps its current contract and raises on
-- failure for backwards compatibility with the existing engine wiring.
--
-- Immutability: top-level configs and their section sub-tables are wrapped
-- in a write-blocking proxy. Reads pass through; assignments raise. List-
-- and dict-shaped values inside sections (e.g. `cards.trick_rank_order`,
-- `cards.point_values`, `marriages.values`) are plain tables so `#`, `pairs`
-- and `ipairs` work — engine code reads through them constantly. The
-- protection target is accidental writes to named fields like
-- `config.bidding.opening_min`, which the proxy catches loudly.

local json = require("app.json")

local M = {}

M.SCHEMA_VERSION = 1

local RULE_CONFIG_TYPE = "thousand.rule_config"
local SECTION_TYPE = "thousand.rule_config.section"

-- Schema -----------------------------------------------------------------
--
-- `_section_order` doubles as the section traversal order for validation
-- and serialisation, so error reports and JSON output are deterministic.
-- Inside each section, `field_order` plays the same role: cards lists
-- `trick_rank_order` before `point_values` because point_values's
-- `key_set_from` references trick_rank_order.

local SCHEMA = {
    _section_order = {
        "cards",
        "players",
        "dealing",
        "talon",
        "bidding",
        "marriages",
        "tricks",
        "scoring",
        "barrel",
        "endgame",
    },
    schema_version = {
        kind = "leaf",
        lua_type = "number",
        allowed = { 1 },
        default = 1,
        status = "implemented",
    },
    cards = {
        kind = "section",
        field_order = { "trick_rank_order", "point_values" },
        fields = {
            trick_rank_order = {
                kind = "list",
                element_type = "string",
                default = { "9", "J", "Q", "K", "10", "A" },
                status = "implemented",
            },
            point_values = {
                kind = "map",
                value_type = "number",
                key_set_from = "cards.trick_rank_order",
                default = {
                    ["A"] = 11,
                    ["10"] = 10,
                    ["K"] = 4,
                    ["Q"] = 3,
                    ["J"] = 2,
                    ["9"] = 0,
                },
                status = "implemented",
            },
        },
    },
    players = {
        kind = "section",
        field_order = {
            "count",
            "partnership_mode",
            "four_player_config",
            "two_player_config",
        },
        fields = {
            -- Phase 3.2 narrowed this to {2, 3, 4} and flipped the status to
            -- "selectable": the picker can offer any of the three, but
            -- dealing/auction still gate runtime to count == 3 until 3.3
            -- ships built-in 2- and 4-player templates.
            count = {
                kind = "leaf",
                lua_type = "number",
                allowed = { 2, 3, 4 },
                default = 3,
                status = "selectable",
            },
            -- Partnership applies only to the 4-player table (see
            -- docs/variations/four-player.md). Locked to "none" until the
            -- 4-player engine path lands.
            partnership_mode = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "none", "fixed_across_table" },
                default = "none",
                status = "deferred",
            },
            -- 4-player seating layout (see docs/variations/four-player.md).
            -- "dealer_plays_no_talon" is Configuration A, the docs' reference;
            -- "dealer_sits_out" is Configuration B.
            four_player_config = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "dealer_plays_no_talon", "dealer_sits_out" },
                default = "dealer_plays_no_talon",
                status = "deferred",
            },
            -- 2-player layout (see docs/variations/two-player.md).
            -- "closed_talon_draw_stock" is Variant A (Schnapsen-style draw);
            -- "fixed_deal_no_draw" is Variant B (8 tricks, identical pattern
            -- to the 3-player game).
            two_player_config = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "closed_talon_draw_stock", "fixed_deal_no_draw" },
                default = "closed_talon_draw_stock",
                status = "deferred",
            },
        },
    },
    -- Dealing & redeal house rules. Every toggle here is "deferred" until
    -- the engine learns to honour an alternative; the locked-in default of
    -- each field is the value that matches the engine's current behaviour,
    -- so canonical_russian carries the new section without any gameplay
    -- change. See docs/variations/house-rules.md "Dealing & redeal house
    -- rules" for the spec each toggle maps to.
    dealing = {
        kind = "section",
        field_order = {
            "four_nine_redeal",
            "three_nine_redeal",
            "four_jack_redeal",
            "weak_hand_redeal",
            "misdeal_handling",
            "all_pass_handling",
        },
        fields = {
            -- A player dealt all four 9s may demand a redeal. "mandatory"
            -- forces the dealer to redeal even if the player would prefer
            -- to play. See house-rules.md "4-nine mandatory redeal".
            four_nine_redeal = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "optional", "mandatory" },
                default = "off",
                status = "deferred",
            },
            -- A player dealt three 9s may optionally request a redeal.
            -- See house-rules.md "3-nine optional redeal".
            three_nine_redeal = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "optional" },
                default = "off",
                status = "deferred",
            },
            -- A player dealt all four Jacks may request a redeal.
            -- See house-rules.md "Four-jack redeal".
            four_jack_redeal = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "on" },
                default = "off",
                status = "deferred",
            },
            -- "Weak hand" entitles the player to request a redeal.
            --   "strict":  no marriage, no Ace, no card above 10.
            --   "loose":   no marriage and no Ace.
            --   "counted": card-point sum below a house-defined threshold;
            --              the threshold sibling field lands with the
            --              gameplay task that flips this to selectable.
            -- See house-rules.md "Weak-hand redeal".
            weak_hand_redeal = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "off", "strict", "loose", "counted" },
                default = "off",
                status = "deferred",
            },
            -- Misdeal recovery branch.
            --   "standard":     same dealer redeals, no penalty.
            --   "soft_penalty": deal moves clockwise.
            --   "flat_penalty": dealer pays a fixed penalty (typically 20)
            --                   and redeals; the amount is a sibling field
            --                   that lands with the gameplay task.
            -- See house-rules.md "Misdeal handling".
            misdeal_handling = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "standard", "soft_penalty", "flat_penalty" },
                default = "standard",
                status = "deferred",
            },
            -- Behaviour when nobody bids and no forced-opening / bolt rule
            -- is in effect.
            --   "redeal":   same dealer redeals, no scoring (current UI
            --               flow's "All players passed" → "Next deal").
            --   "pass_out": deal moves clockwise without scoring.
            --   "raspassy": play the deal without trump or bidding, with
            --               the reverse-scoring rule from house-rules.md.
            -- See house-rules.md "All-pass handling".
            all_pass_handling = {
                kind = "leaf",
                lua_type = "string",
                allowed = { "redeal", "pass_out", "raspassy" },
                default = "redeal",
                status = "deferred",
            },
        },
    },
    talon = {
        kind = "section",
        field_order = { "size" },
        fields = {
            size = {
                kind = "leaf",
                lua_type = "number",
                min = 0,
                default = 3,
                status = "implemented",
            },
        },
    },
    bidding = {
        kind = "section",
        field_order = {
            "opening_min",
            "pre_talon_max",
            "increment_threshold",
            "increment_below_200",
            "increment_from_200",
        },
        fields = {
            opening_min = {
                kind = "leaf",
                lua_type = "number",
                min = 10,
                default = 100,
                status = "implemented",
            },
            pre_talon_max = {
                kind = "leaf",
                lua_type = "number",
                min = 10,
                default = 120,
                status = "implemented",
            },
            -- The bid amount at which the increment switches from
            -- `increment_below_200` to `increment_from_200`. The field
            -- names keep their canonical-Russian shorthand so existing
            -- code stays readable; the threshold itself moves with the
            -- variant (e.g. 250 in some house-rule sets).
            increment_threshold = {
                kind = "leaf",
                lua_type = "number",
                min = 1,
                default = 200,
                status = "implemented",
            },
            increment_below_200 = {
                kind = "leaf",
                lua_type = "number",
                min = 1,
                default = 5,
                status = "implemented",
            },
            increment_from_200 = {
                kind = "leaf",
                lua_type = "number",
                min = 1,
                default = 10,
                status = "implemented",
            },
        },
    },
    marriages = {
        kind = "section",
        field_order = { "values" },
        fields = {
            values = {
                kind = "map",
                value_type = "number",
                required_keys = { "hearts", "diamonds", "clubs", "spades" },
                default = { hearts = 100, diamonds = 80, clubs = 60, spades = 40 },
                status = "implemented",
            },
        },
    },
    tricks = {
        kind = "section",
        field_order = { "must_follow", "must_beat", "must_trump", "must_overtrump" },
        fields = {
            must_follow = {
                kind = "leaf",
                lua_type = "boolean",
                default = true,
                status = "implemented",
            },
            must_beat = {
                kind = "leaf",
                lua_type = "boolean",
                default = true,
                status = "implemented",
            },
            must_trump = {
                kind = "leaf",
                lua_type = "boolean",
                default = true,
                status = "implemented",
            },
            must_overtrump = {
                kind = "leaf",
                lua_type = "boolean",
                default = true,
                status = "implemented",
            },
        },
    },
    scoring = {
        kind = "section",
        field_order = { "round_to_nearest" },
        fields = {
            round_to_nearest = {
                kind = "leaf",
                lua_type = "number",
                allowed = { 5 },
                default = 5,
                status = "implemented",
            },
        },
    },
    barrel = {
        kind = "section",
        field_order = { "threshold", "deal_count", "fall_off_penalty" },
        fields = {
            -- `fall_off_penalty` intentionally omits `min`: -120 is canonical.
            threshold = {
                kind = "leaf",
                lua_type = "number",
                default = 880,
                status = "implemented",
            },
            deal_count = {
                kind = "leaf",
                lua_type = "number",
                min = 1,
                default = 3,
                status = "implemented",
            },
            fall_off_penalty = {
                kind = "leaf",
                lua_type = "number",
                default = -120,
                status = "implemented",
            },
        },
    },
    endgame = {
        kind = "section",
        field_order = { "target_score" },
        fields = {
            target_score = {
                kind = "leaf",
                lua_type = "number",
                default = 1000,
                status = "implemented",
            },
        },
    },
}

-- Cross-field invariants. Each entry's `predicate` returns true when the
-- rule is satisfied; `context` returns a table of detail fields the UI
-- feeds into t("rule_config.invariant." .. name, context).

local INVARIANTS = {
    {
        name = "pre_talon_max_ge_opening_min",
        predicate = function(blob)
            return blob.bidding.pre_talon_max >= blob.bidding.opening_min
        end,
        context = function(blob)
            return {
                pre_talon_max = blob.bidding.pre_talon_max,
                opening_min = blob.bidding.opening_min,
            }
        end,
    },
    {
        name = "barrel_threshold_below_target",
        predicate = function(blob)
            return blob.barrel.threshold < blob.endgame.target_score
        end,
        context = function(blob)
            return {
                threshold = blob.barrel.threshold,
                target_score = blob.endgame.target_score,
            }
        end,
    },
    -- Silent under the production schema today: partnership_mode is
    -- deferred, so deferred_field_changed short-circuits any non-default
    -- attempt before this predicate runs. The invariant lives here so the
    -- task that flips partnership_mode to "selectable" gets the constraint
    -- for free. See docs/variations/four-player.md.
    {
        name = "partnership_mode_requires_four_players",
        predicate = function(blob)
            return blob.players.partnership_mode == "none" or blob.players.count == 4
        end,
        context = function(blob)
            return {
                partnership_mode = blob.players.partnership_mode,
                count = blob.players.count,
            }
        end,
    },
}

-- Validation -------------------------------------------------------------

local function failure(code, extra)
    local err = { code = code }
    if extra then
        for k, v in pairs(extra) do
            err[k] = v
        end
    end
    return { ok = false, error = err }
end

local function deep_equal(a, b)
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if not deep_equal(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

local function in_set(value, allowed)
    if not allowed then
        return true
    end
    for _, candidate in ipairs(allowed) do
        if value == candidate then
            return true
        end
    end
    return false
end

local function set_from_list(t)
    local out = {}
    for _, v in ipairs(t) do
        out[v] = true
    end
    return out
end

local function format_path(parts)
    return table.concat(parts, ".")
end

local function describe_value_short(v)
    local tv = type(v)
    if tv == "string" then
        return string.format("%q", v)
    elseif tv == "table" then
        return "<table>"
    end
    return tostring(v)
end

local function format_allowed(allowed)
    if not allowed then
        return "[]"
    end
    local parts = {}
    for i, v in ipairs(allowed) do
        parts[i] = describe_value_short(v)
    end
    return "[" .. table.concat(parts, ", ") .. "]"
end

local function lookup_path(blob, path)
    local current = blob
    for segment in tostring(path):gmatch("[^.]+") do
        if type(current) ~= "table" then
            return nil
        end
        current = current[segment]
    end
    return current
end

local function child_path(path, segment)
    local out = {}
    for i = 1, #path do
        out[i] = path[i]
    end
    out[#out + 1] = tostring(segment)
    return out
end

local function validate_leaf(value, descriptor, path)
    if type(value) ~= descriptor.lua_type then
        return failure("type_mismatch", {
            path = format_path(path),
            expected = descriptor.lua_type,
            actual = type(value),
        })
    end
    if descriptor.status == "deferred" and not deep_equal(value, descriptor.default) then
        return failure("deferred_field_changed", { path = format_path(path) })
    end
    if not in_set(value, descriptor.allowed) then
        return failure("value_not_allowed", {
            path = format_path(path),
            value = value,
            allowed = format_allowed(descriptor.allowed),
        })
    end
    if descriptor.min and value < descriptor.min then
        return failure("value_out_of_range", {
            path = format_path(path),
            value = value,
        })
    end
    if descriptor.max and value > descriptor.max then
        return failure("value_out_of_range", {
            path = format_path(path),
            value = value,
        })
    end
    return { ok = true }
end

local function is_dense_array(t)
    local n = #t
    local count = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k ~= math.floor(k) or k < 1 or k > n then
            return false
        end
        count = count + 1
    end
    return count == n
end

local function validate_list(value, descriptor, path)
    if type(value) ~= "table" or not is_dense_array(value) then
        return failure("type_mismatch", {
            path = format_path(path),
            expected = "list",
            actual = type(value) == "table" and "non-list table" or type(value),
        })
    end
    if descriptor.status == "deferred" and not deep_equal(value, descriptor.default) then
        return failure("deferred_field_changed", { path = format_path(path) })
    end
    if descriptor.element_type then
        for i = 1, #value do
            if type(value[i]) ~= descriptor.element_type then
                return failure("type_mismatch", {
                    path = format_path(child_path(path, i)),
                    expected = descriptor.element_type,
                    actual = type(value[i]),
                })
            end
        end
    end
    return { ok = true }
end

local function validate_map(value, descriptor, path, full_blob)
    if type(value) ~= "table" then
        return failure("type_mismatch", {
            path = format_path(path),
            expected = "table",
            actual = type(value),
        })
    end
    if descriptor.status == "deferred" and not deep_equal(value, descriptor.default) then
        return failure("deferred_field_changed", { path = format_path(path) })
    end
    local required
    if descriptor.required_keys then
        required = descriptor.required_keys
    elseif descriptor.key_set_from then
        local resolved = lookup_path(full_blob, descriptor.key_set_from)
        if type(resolved) ~= "table" then
            return failure("missing_field", { path = descriptor.key_set_from })
        end
        required = resolved
    end
    if required then
        for _, key in ipairs(required) do
            local entry = value[key]
            if entry == nil then
                return failure("missing_field", {
                    path = format_path(child_path(path, key)),
                })
            end
            if descriptor.value_type and type(entry) ~= descriptor.value_type then
                return failure("type_mismatch", {
                    path = format_path(child_path(path, key)),
                    expected = descriptor.value_type,
                    actual = type(entry),
                })
            end
        end
    end
    return { ok = true }
end

local function dispatch_validate(value, descriptor, path, full_blob)
    if descriptor.kind == "leaf" then
        return validate_leaf(value, descriptor, path)
    elseif descriptor.kind == "list" then
        return validate_list(value, descriptor, path)
    elseif descriptor.kind == "map" then
        return validate_map(value, descriptor, path, full_blob)
    end
    error("rule_config: bad schema descriptor at " .. format_path(path), 2)
end

local function validate_section(blob, name, section_schema)
    local section = blob[name]
    if section == nil then
        return failure("missing_field", { path = name })
    end
    if type(section) ~= "table" then
        return failure("type_mismatch", {
            path = name,
            expected = "table",
            actual = type(section),
        })
    end
    local known = set_from_list(section_schema.field_order)
    for k in pairs(section) do
        if not known[k] then
            return failure("unknown_field", { path = name .. "." .. tostring(k) })
        end
    end
    for _, field_name in ipairs(section_schema.field_order) do
        local descriptor = section_schema.fields[field_name]
        local value = section[field_name]
        if value == nil then
            return failure("missing_field", { path = name .. "." .. field_name })
        end
        local res = dispatch_validate(value, descriptor, { name, field_name }, blob)
        if not res.ok then
            return res
        end
    end
    return { ok = true }
end

local function validate_blob(blob, schema, invariants)
    schema = schema or SCHEMA
    if type(blob) ~= "table" then
        return failure("not_a_table", { actual = type(blob) })
    end

    local section_order = schema._section_order
    if type(section_order) ~= "table" then
        error("rule_config: schema is missing _section_order", 2)
    end

    -- Schema version. All failures funnel into one code so the UI can
    -- distinguish "save from a different build" from generic validation.
    local sv_descriptor = schema.schema_version
    local sv = blob.schema_version
    if type(sv) ~= sv_descriptor.lua_type or not in_set(sv, sv_descriptor.allowed) then
        return failure("unsupported_schema_version", {
            version = sv,
            supported = format_allowed(sv_descriptor.allowed),
        })
    end

    -- Top-level unknown-key rejection.
    local known_top = { schema_version = true }
    for _, name in ipairs(section_order) do
        known_top[name] = true
    end
    for k in pairs(blob) do
        if not known_top[k] then
            return failure("unknown_field", { path = tostring(k) })
        end
    end

    -- Sections in declared order.
    for _, name in ipairs(section_order) do
        local section_schema = schema[name]
        if section_schema and section_schema.kind == "section" then
            local section_res = validate_section(blob, name, section_schema)
            if not section_res.ok then
                return section_res
            end
        end
    end

    -- Cross-field invariants. Default-on for the production schema only;
    -- a custom test schema opts in by passing its own list (or `nil` for
    -- "no invariants" — the default for any non-production schema).
    local effective
    if invariants ~= nil then
        effective = invariants
    elseif schema == SCHEMA then
        effective = INVARIANTS
    else
        effective = {}
    end
    for _, invariant in ipairs(effective) do
        if not invariant.predicate(blob) then
            local context = invariant.context(blob)
            context.invariant = invariant.name
            return failure("incompatible_combination", context)
        end
    end

    return { ok = true }
end

-- Construction -----------------------------------------------------------

local function freeze(data, type_marker)
    return setmetatable({}, {
        __index = data,
        __newindex = function(_, key)
            error("rule_config is frozen: cannot set key " .. tostring(key), 2)
        end,
        __metatable = type_marker,
    })
end

local function build_frozen(blob)
    local data = { schema_version = blob.schema_version }
    for _, name in ipairs(SCHEMA._section_order) do
        data[name] = freeze(blob[name], SECTION_TYPE)
    end
    return freeze(data, RULE_CONFIG_TYPE)
end

function M.try_new(blob)
    local res = validate_blob(blob)
    if not res.ok then
        return res
    end
    return { ok = true, config = build_frozen(blob) }
end

function M.new(blob)
    local res = M.try_new(blob)
    if res.ok then
        return res.config
    end
    -- Render a developer-facing summary. Existing tests use `assert.has_error`,
    -- so the exact text is not pinned; the error code is the contract for
    -- anyone inspecting structured diagnostics.
    local err = res.error
    local parts = { "rule_config: " .. tostring(err.code) }
    for k, v in pairs(err) do
        if k ~= "code" then
            parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
        end
    end
    error(table.concat(parts, " "), 2)
end

function M.is_rule_config(v)
    if type(v) ~= "table" then
        return false
    end
    return getmetatable(v) == RULE_CONFIG_TYPE
end

-- Schema reflection ------------------------------------------------------

local function clone_descriptor(node)
    local out = {}
    for k, v in pairs(node) do
        if type(v) == "table" then
            local copy = {}
            for ki, vi in pairs(v) do
                copy[ki] = vi
            end
            out[k] = copy
        else
            out[k] = v
        end
    end
    return out
end

function M.schema_for(path)
    if type(path) ~= "string" then
        return nil
    end
    local segments = {}
    for s in path:gmatch("[^.]+") do
        segments[#segments + 1] = s
    end
    if #segments == 0 then
        return nil
    end
    local first = segments[1]
    if first == "schema_version" and #segments == 1 then
        return clone_descriptor(SCHEMA.schema_version)
    end
    local section = SCHEMA[first]
    if not section or section.kind ~= "section" then
        return nil
    end
    if #segments == 1 then
        local fields = {}
        for i, name in ipairs(section.field_order) do
            fields[i] = name
        end
        return { kind = "section", fields = fields }
    end
    if #segments ~= 2 then
        return nil
    end
    local descriptor = section.fields[segments[2]]
    if not descriptor then
        return nil
    end
    return clone_descriptor(descriptor)
end

-- JSON round-trip --------------------------------------------------------

local function plain_copy(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = plain_copy(v)
    end
    return out
end

function M.to_json(config)
    if not M.is_rule_config(config) then
        error("rule_config.to_json expects a RuleConfig, got " .. type(config), 2)
    end
    local data = { schema_version = config.schema_version }
    for _, name in ipairs(SCHEMA._section_order) do
        local section_schema = SCHEMA[name]
        local section_out = {}
        for _, field_name in ipairs(section_schema.field_order) do
            section_out[field_name] = plain_copy(config[name][field_name])
        end
        data[name] = section_out
    end
    return json.encode(data)
end

function M.from_json(s)
    if type(s) ~= "string" then
        return failure("type_mismatch", {
            path = "json",
            expected = "string",
            actual = type(s),
        })
    end
    local decoded, err = json.decode(s)
    if decoded == nil then
        return failure("json_decode_failed", { details = tostring(err) })
    end
    return M.try_new(decoded)
end

-- Test hook: run validation only, optionally against a custom schema and
-- a custom invariants list. Mirrors app/i18n.lua's `_set_locale_table` /
-- `_reset` convention. Used by specs to exercise the deferred-field path,
-- alternative schema shapes, and invariants whose target field is still
-- deferred in production (so try_new can't reach the predicate).
function M._validate(blob, schema_override, invariants_override)
    return validate_blob(blob, schema_override, invariants_override)
end

-- Test hook: returns a shallow copy of the production INVARIANTS list so
-- specs can assert wiring without reaching into the module's locals.
function M._invariants()
    local copy = {}
    for i, inv in ipairs(INVARIANTS) do
        copy[i] = inv
    end
    return copy
end

-- Canonical instance -----------------------------------------------------

M.canonical_russian = M.new({
    schema_version = 1,
    cards = {
        point_values = {
            ["A"] = 11,
            ["10"] = 10,
            ["K"] = 4,
            ["Q"] = 3,
            ["J"] = 2,
            ["9"] = 0,
        },
        trick_rank_order = { "9", "J", "Q", "K", "10", "A" },
    },
    players = {
        count = 3,
        partnership_mode = "none",
        four_player_config = "dealer_plays_no_talon",
        two_player_config = "closed_talon_draw_stock",
    },
    dealing = {
        four_nine_redeal = "off",
        three_nine_redeal = "off",
        four_jack_redeal = "off",
        weak_hand_redeal = "off",
        misdeal_handling = "standard",
        all_pass_handling = "redeal",
    },
    talon = { size = 3 },
    bidding = {
        opening_min = 100,
        pre_talon_max = 120,
        increment_threshold = 200,
        increment_below_200 = 5,
        increment_from_200 = 10,
    },
    marriages = {
        values = { hearts = 100, diamonds = 80, clubs = 60, spades = 40 },
    },
    tricks = {
        must_follow = true,
        must_beat = true,
        must_trump = true,
        must_overtrump = true,
    },
    scoring = { round_to_nearest = 5 },
    barrel = {
        threshold = 880,
        deal_count = 3,
        fall_off_penalty = -120,
    },
    endgame = { target_score = 1000 },
})

return M
