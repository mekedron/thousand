-- The Thousand auto-save serializer.
--
-- Pure-Lua bridge between an `app.Session` and a JSON-encodable plain
-- table. Lives in core/ so the serialization protocol stays free of
-- love.* — the actual filesystem read/write happens in app/auto_save.lua,
-- which delegates to this module for the data shape.
--
-- Schema versioning. The blob's `schemaVersion` field is the only contract
-- between save files and reader code. A blob with a mismatched version is
-- treated as "no save" by `deserialize`, which returns nil — the caller
-- starts a fresh game rather than crashing on an upgrade. Future schema
-- bumps add a migration step in `deserialize` before validation.
--
-- Rule template snapshot. Phase 2 ships exactly one rule template
-- (`canonical_russian`); the template name is stored as a string so
-- Phase 3's rule-template registry can resolve it without a code change
-- here. A save written under a template the running build doesn't know
-- about is also treated as "no save" — same fail-soft posture.
--
-- The save shape includes every field `Session.from_state` expects, with
-- the engine `config` references stripped out (they all reference the
-- same RuleConfig and re-attach on deserialize). Each engine state
-- (auction, talon, marriages, tricks, scoring) is type-tagged on
-- deserialize so subsequent engine calls (`auction.bid` etc.) recognise
-- them via `is_auction` and friends. Cards held by the engine are frozen
-- proxy tables whose data lives in `__index`; `data_clone` materialises
-- them into plain `{ suit, rank }` tables that JSON survives unchanged.

local rule_config = require("core.rule_config")

local M = {}

local SCHEMA_VERSION = 1
local TEMPLATE_NAME = "canonical_russian"

-- Type markers replicated from each core/ module. Reading them through
-- the modules would require five `M.tag(state)` exports we'd otherwise
-- never need — duplicating the small string table is the lower-friction
-- choice. The strings are public-facing (they appear in `is_auction`
-- error envelopes), so a downstream rename forces a coordinated update
-- here too.
local METATABLE_TAGS = {
    auction = "thousand.auction",
    talon = "thousand.talon",
    marriages = "thousand.marriages",
    tricks = "thousand.tricks",
    scoring = "thousand.scoring",
}

local TEMPLATES = {
    [TEMPLATE_NAME] = rule_config.canonical_russian,
}

-- Recursively copy a value into a plain JSON-encodable Lua table.
--
-- The two non-obvious cases:
--   * Frozen cards from `core.card` are `setmetatable({}, { __index =
--     data, __metatable = "thousand.card" })`. `pairs()` sees the empty
--     outer table and returns nothing, so a naive walk would lose the
--     suit/rank. We detect "table with no own keys but suit and rank
--     accessible via __index" and copy those fields explicitly.
--   * Engine state tables (auction, talon, …) hold their data
--     directly; the metatable is used only for type tagging. `pairs()`
--     iterates them correctly, so the generic copy below handles them.
local function data_clone(value)
    if type(value) ~= "table" then
        return value
    end
    if next(value) == nil and type(value.suit) == "string" and type(value.rank) == "string" then
        return { suit = value.suit, rank = value.rank }
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = data_clone(v)
    end
    return out
end

-- Engine states embed `config = <RuleConfig>` for rule lookups during
-- mutators. RuleConfig is a frozen __index proxy whose data we don't
-- want to inline into every save (it's identical across all engine
-- states and the top-level session). Strip it on save, re-attach on
-- load. Returns nil when the input is nil so callers can pipe optional
-- engine states through unchanged.
local function strip_config(state)
    if type(state) ~= "table" then
        return nil
    end
    local out = {}
    for k, v in pairs(state) do
        if k ~= "config" then
            out[k] = data_clone(v)
        end
    end
    return out
end

-- talon.passes_received is `{[player] = true}` where the key set is
-- sparse — only seats that have already received a pass appear. JSON
-- object encoding refuses tables with integer keys; converting to a
-- dense list with `false` fill would corrupt the talon module's
-- pass-count check (`for _ in pairs(passes_received)`), which counts
-- only entries actually present. The least-disruptive answer is to
-- stringify the integer keys for the wire format and restore them on
-- load. Same trick for any future field with the same shape.
local function stringify_int_keys(t)
    if type(t) ~= "table" then
        return t
    end
    local out = {}
    for k, v in pairs(t) do
        out[tostring(k)] = v
    end
    return out
end

local function intify_numeric_keys(t)
    if type(t) ~= "table" then
        return t
    end
    local out = {}
    for k, v in pairs(t) do
        local n = type(k) == "string" and tonumber(k) or nil
        if n ~= nil and n == math.floor(n) then
            out[n] = v
        else
            out[k] = v
        end
    end
    return out
end

-- Re-attach the rule config and re-apply the type metatable so the
-- restored state is indistinguishable from one the engine produced.
-- Returns nil for nil so callers can pipe optional fields through.
local function rehydrate(state, kind, config)
    if state == nil then
        return nil
    end
    state.config = config
    return setmetatable(state, { __metatable = METATABLE_TAGS[kind] })
end

-- Public API ------------------------------------------------------------

function M.schema_version()
    return SCHEMA_VERSION
end

function M.template_name()
    return TEMPLATE_NAME
end

-- Turns a Session into a JSON-encodable blob. Returns nil if the
-- session is missing or malformed.
function M.serialize(session)
    if type(session) ~= "table" then
        return nil
    end
    local talon = strip_config(session._talon)
    if talon and type(talon.passes_received) == "table" then
        talon.passes_received = stringify_int_keys(talon.passes_received)
    end
    return {
        schemaVersion = SCHEMA_VERSION,
        templateName = TEMPLATE_NAME,
        seed = session._seed,
        dealer = session._dealer,
        deal_index = session._deal_index,
        hands = data_clone(session._hands),
        talon_cards = data_clone(session._talon_cards),
        auction = strip_config(session._auction),
        talon = talon,
        marriages = strip_config(session._marriages),
        tricks = strip_config(session._tricks),
        scoring = strip_config(session._scoring),
        running_totals = data_clone(session._running_totals),
        barrel_state = data_clone(session._barrel_state),
        winner = session._winner,
        deal_done = data_clone(session._deal_done),
        pending_trump_apply = session._pending_trump_apply,
        -- Phase 3.6 endgame house-rules persistence.
        effective_target = session._effective_target,
        in_golden_deal = session._in_golden_deal,
        golden_deal_failures = session._golden_deal_failures,
        -- Phase 3.6 special-contracts persistence. Carries the
        -- active named contract record so a saved deal restores
        -- with the same mizère / slam / open-hand semantics.
        active_named_contract = data_clone(session._active_named_contract),
        -- Phase 3.6 penalty house-rules persistence. The bolt and
        -- cross counters span deals; the recorded-violations log
        -- spans the current deal. All three round-trip cleanly so a
        -- saved game continues penalty bookkeeping where it left off.
        zero_tricks_bolts = data_clone(session._zero_tricks_bolts),
        cross_count = data_clone(session._cross_count),
        recorded_penalties = data_clone(session._recorded_penalties),
        -- Phase 3.7 write-off counter: per-seat persistent count under
        -- bidding.write_off / penalties.write_off_streak. Older saves
        -- written before the field existed simply round-trip as nil
        -- and Session.from_state defaults to all-zeros.
        write_off_counts = data_clone(session._write_off_counts),
        -- Phase 3.7 cross-deal counters: no-win streak (under
        -- penalties.no_win_streak) and barrel-fall (under
        -- barrel.fall_count_resets_to_zero). Both round-trip per-seat
        -- as plain integer arrays. Older saves load with all-zeros
        -- because Session.from_state defaults missing fields.
        no_win_streak_counts = data_clone(session._no_win_streak_counts),
        barrel_fall_counts = data_clone(session._barrel_fall_counts),
        -- Phase 3.8 cut-deck ritual: in-flight cut phase and the
        -- per-deal cut event log. `cut_phase` is nil unless the
        -- ritual is open (toggle on AND no cut yet); `bottom_card`
        -- inside it is a frozen card whose {suit, rank} round-trip
        -- through `data_clone`'s frozen-card branch. Old saves load
        -- with both fields nil/empty and `Session.from_state`
        -- defaults the log to {}.
        cut_phase = data_clone(session._cut_phase),
        cut_deck_log = data_clone(session._cut_deck_log),
    }
end

-- Validates a decoded blob and returns a state-shaped table ready for
-- `Session.from_state`. Returns nil on schema mismatch or unknown
-- template — callers fall back to "no save" rather than crashing.
function M.deserialize(blob)
    if type(blob) ~= "table" then
        return nil
    end
    if blob.schemaVersion ~= SCHEMA_VERSION then
        return nil
    end
    local config = TEMPLATES[blob.templateName]
    if config == nil then
        return nil
    end
    local talon = blob.talon
    if talon and type(talon.passes_received) == "table" then
        talon.passes_received = intify_numeric_keys(talon.passes_received)
    end
    return {
        config = config,
        seed = blob.seed,
        dealer = blob.dealer,
        deal_index = blob.deal_index,
        hands = blob.hands,
        talon_cards = blob.talon_cards,
        auction = rehydrate(blob.auction, "auction", config),
        talon = rehydrate(talon, "talon", config),
        marriages = rehydrate(blob.marriages, "marriages", config),
        tricks = rehydrate(blob.tricks, "tricks", config),
        scoring = rehydrate(blob.scoring, "scoring", config),
        running_totals = blob.running_totals,
        barrel_state = blob.barrel_state,
        winner = blob.winner,
        deal_done = blob.deal_done,
        pending_trump_apply = blob.pending_trump_apply,
        effective_target = blob.effective_target,
        in_golden_deal = blob.in_golden_deal,
        golden_deal_failures = blob.golden_deal_failures,
        active_named_contract = blob.active_named_contract,
        zero_tricks_bolts = blob.zero_tricks_bolts,
        cross_count = blob.cross_count,
        recorded_penalties = blob.recorded_penalties,
        write_off_counts = blob.write_off_counts,
        no_win_streak_counts = blob.no_win_streak_counts,
        barrel_fall_counts = blob.barrel_fall_counts,
        cut_phase = blob.cut_phase,
        cut_deck_log = blob.cut_deck_log,
    }
end

return M
