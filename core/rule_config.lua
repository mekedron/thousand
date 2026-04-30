-- The Thousand RuleConfig value object.
--
-- A `RuleConfig` is the single source of truth for every variable rule in
-- the engine: card values, talon size, bid increments, marriage values,
-- trick-play strictness, scoring rounding, barrel rules, target score.
-- Phase 1 ships exactly one instance — `canonical_russian` — but the schema
-- is shaped so Phase 3 variants (Polish, Ukrainian, 2-/4-player, custom)
-- plug in as data only, with no engine code changes.
--
-- Shape: top-level keys mirror the toggle catalogue in development/task-list
-- §3.2 (`cards`, `players`, `talon`, `bidding`, `marriages`, `tricks`,
-- `scoring`, `barrel`, `endgame`). Phase 1 populates only the fields it
-- implements; Phase 3 expands the catalogue.
--
-- Immutability: top-level configs and their section sub-tables are wrapped
-- in a write-blocking proxy. Reads pass through; assignments raise. List-
-- and dict-shaped values inside sections (e.g. `cards.trick_rank_order`,
-- `cards.point_values`, `marriages.values`) are plain tables so `#`, `pairs`
-- and `ipairs` work — engine code reads through them constantly. The
-- protection target is accidental writes to named fields like
-- `config.bidding.opening_min`, which the proxy catches loudly.
--
-- Version: `schema_version` is a single integer at the top level. Phase 1
-- ships version 1; future migrations live in a separate module added when
-- the first migration is needed.

local M = {}

M.SCHEMA_VERSION = 1

local SUPPORTED_SCHEMA_VERSIONS = { [1] = true }

local RULE_CONFIG_TYPE = "thousand.rule_config"
local SECTION_TYPE = "thousand.rule_config.section"

local function freeze(data, type_marker)
    return setmetatable({}, {
        __index = data,
        __newindex = function(_, key)
            error("rule_config is frozen: cannot set key " .. tostring(key), 2)
        end,
        __metatable = type_marker,
    })
end

local function require_field(t, key, expected_type, path)
    local value = t[key]
    if value == nil then
        error(string.format("rule_config: missing %s.%s", path, tostring(key)))
    end
    if type(value) ~= expected_type then
        error(
            string.format(
                "rule_config: %s.%s must be a %s, got %s",
                path,
                tostring(key),
                expected_type,
                type(value)
            )
        )
    end
    return value
end

local function validate_cards(section)
    require_field(section, "point_values", "table", "cards")
    require_field(section, "trick_rank_order", "table", "cards")
    for _, rank in ipairs(section.trick_rank_order) do
        if section.point_values[rank] == nil then
            error("rule_config: cards.point_values is missing rank " .. tostring(rank))
        end
        if type(section.point_values[rank]) ~= "number" then
            error("rule_config: cards.point_values." .. tostring(rank) .. " must be a number")
        end
    end
end

local function validate_players(section)
    require_field(section, "count", "number", "players")
end

local function validate_talon(section)
    require_field(section, "size", "number", "talon")
end

local function validate_bidding(section)
    require_field(section, "opening_min", "number", "bidding")
    require_field(section, "pre_talon_max", "number", "bidding")
    require_field(section, "increment_below_200", "number", "bidding")
    require_field(section, "increment_from_200", "number", "bidding")
end

local function validate_marriages(section)
    require_field(section, "values", "table", "marriages")
    require_field(section.values, "hearts", "number", "marriages.values")
    require_field(section.values, "diamonds", "number", "marriages.values")
    require_field(section.values, "clubs", "number", "marriages.values")
    require_field(section.values, "spades", "number", "marriages.values")
end

local function validate_tricks(section)
    require_field(section, "must_follow", "boolean", "tricks")
    require_field(section, "must_beat", "boolean", "tricks")
    require_field(section, "must_trump", "boolean", "tricks")
    require_field(section, "must_overtrump", "boolean", "tricks")
end

local function validate_scoring(section)
    require_field(section, "round_to_nearest", "number", "scoring")
end

local function validate_barrel(section)
    require_field(section, "threshold", "number", "barrel")
    require_field(section, "deal_count", "number", "barrel")
    require_field(section, "fall_off_penalty", "number", "barrel")
end

local function validate_endgame(section)
    require_field(section, "target_score", "number", "endgame")
end

local SECTION_VALIDATORS = {
    cards = validate_cards,
    players = validate_players,
    talon = validate_talon,
    bidding = validate_bidding,
    marriages = validate_marriages,
    tricks = validate_tricks,
    scoring = validate_scoring,
    barrel = validate_barrel,
    endgame = validate_endgame,
}

local SECTION_NAMES = {
    "cards",
    "players",
    "talon",
    "bidding",
    "marriages",
    "tricks",
    "scoring",
    "barrel",
    "endgame",
}

function M.new(t)
    if type(t) ~= "table" then
        error("rule_config.new expects a table, got " .. type(t))
    end

    local schema_version = t.schema_version
    if type(schema_version) ~= "number" then
        error("rule_config: schema_version must be a number")
    end
    if not SUPPORTED_SCHEMA_VERSIONS[schema_version] then
        error("rule_config: unsupported schema_version " .. tostring(schema_version))
    end

    for _, name in ipairs(SECTION_NAMES) do
        local section = t[name]
        if type(section) ~= "table" then
            error("rule_config: missing or non-table section " .. name)
        end
        SECTION_VALIDATORS[name](section)
    end

    local data = { schema_version = schema_version }
    for _, name in ipairs(SECTION_NAMES) do
        data[name] = freeze(t[name], SECTION_TYPE)
    end
    return freeze(data, RULE_CONFIG_TYPE)
end

function M.is_rule_config(v)
    if type(v) ~= "table" then
        return false
    end
    return getmetatable(v) == RULE_CONFIG_TYPE
end

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
    players = { count = 3 },
    talon = { size = 3 },
    bidding = {
        opening_min = 100,
        pre_talon_max = 120,
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
