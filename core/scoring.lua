-- The Thousand deal scoring and contract resolution.
--
-- Phase 1.7 of the engine: once the trick layer has run out the eight
-- tricks, each player has a captured card-point total and a marriage
-- bonus credited by the marriages layer. This module turns those
-- per-deal totals into the per-deal contract result and the change
-- applied to each player's running total. Subsequent phase 1.7 work
-- (the barrel and game-end scoring) lives in a separate task; this
-- module only computes a single deal's outcome.
--
-- The canonical Russian rule (the only template Phase 1 ships) is:
--   * captured card points round to the nearest `scoring.round_to_nearest`
--     (Russian default 5); marriage bonuses are exact.
--   * deal_score[player] = rounded_card_points[player]
--                          + marriage_bonuses[player].
--   * declarer's contract is made iff deal_score[declarer] >= bid.
--   * declarer adds bid on success and subtracts bid on failure.
--   * defenders always add their own deal_score.
-- Variants change behavior through `RuleConfig.scoring` toggles in
-- Phase 3 (e.g. score actual points on success, round before checking
-- the contract); none of those toggles is read here.
--
-- API mirrors `core.auction` / `core.talon` / `core.marriages` /
-- `core.tricks`:
--   * Single public function `M.score_deal(config, opts)` returns
--     either { ok = true, scoring = <state> } or
--     { ok = false, error = { code, message, ...extra } }.
--   * The result state is type-tagged via `__metatable` so
--     `M.is_scoring` recognises it.
--   * Every transition produces a fresh state; the input is never
--     mutated. The output's per-player lists are independent copies.

local rule_config = require("core.rule_config")

local M = {}

M.SCHEMA_VERSION = 1

local SCORING_TYPE = "thousand.scoring"

local function failure(code, message, extra)
    local err = { code = code, message = message }
    if extra then
        for k, v in pairs(extra) do
            err[k] = v
        end
    end
    return { ok = false, error = err }
end

local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

local function tag_as_scoring(state)
    return setmetatable(state, { __metatable = SCORING_TYPE })
end

-- Round to the nearest multiple of `nearest`, half-up. Inputs are
-- always integer captured-card totals in practice; the half-up branch
-- guarantees a deterministic answer for any future fractional input.
local function round_to_nearest(value, nearest)
    return math.floor((value + nearest / 2) / nearest) * nearest
end

local function copy_int_list(list, count)
    local copy = {}
    for i = 1, count do
        copy[i] = list[i]
    end
    return copy
end

local function validate_player_list(name, list, count)
    if type(list) ~= "table" then
        return failure("bad_" .. name, name .. " must be a list of " .. count .. " integers", {
            actual = type(list),
        })
    end
    if #list ~= count then
        return failure(
            "bad_" .. name,
            name .. " must hold one entry per player",
            { actual = #list, expected = count }
        )
    end
    for i = 1, count do
        if not is_integer(list[i]) then
            return failure("bad_" .. name, name .. " entries must be integers", {
                player = i,
                actual = list[i],
            })
        end
    end
    return nil
end

function M.score_deal(config, opts)
    if not rule_config.is_rule_config(config) then
        return failure("not_a_rule_config", "scoring.score_deal requires a RuleConfig", {
            actual = type(config),
        })
    end
    if type(opts) ~= "table" then
        return failure("bad_opts", "scoring.score_deal requires an opts table", {
            actual = type(opts),
        })
    end

    local player_count = config.players.count
    local nearest = config.scoring.round_to_nearest
    if not (is_integer(nearest) and nearest >= 1) then
        return failure(
            "bad_round_to_nearest",
            "config.scoring.round_to_nearest must be a positive integer",
            { actual = nearest }
        )
    end

    local declarer = opts.declarer
    if not (is_integer(declarer) and declarer >= 1 and declarer <= player_count) then
        return failure(
            "bad_declarer",
            "declarer must be an integer in 1.." .. player_count,
            { actual = declarer, player_count = player_count }
        )
    end

    local bid = opts.bid
    if not is_integer(bid) then
        return failure("bad_bid", "bid must be an integer", { actual = bid })
    end

    local captured_err = validate_player_list("captured_points", opts.captured_points, player_count)
    if captured_err then
        return captured_err
    end
    local bonuses_err =
        validate_player_list("marriage_bonuses", opts.marriage_bonuses, player_count)
    if bonuses_err then
        return bonuses_err
    end
    local totals_err = validate_player_list("running_totals", opts.running_totals, player_count)
    if totals_err then
        return totals_err
    end

    local captured_sum = 0
    for i = 1, player_count do
        if opts.captured_points[i] < 0 then
            return failure(
                "bad_captured_points",
                "captured_points entries must be non-negative",
                { player = i, actual = opts.captured_points[i] }
            )
        end
        captured_sum = captured_sum + opts.captured_points[i]
    end
    if captured_sum > 120 then
        return failure(
            "captured_points_exceed_deck",
            "captured card points sum must not exceed 120 across all sides",
            { actual = captured_sum, max = 120 }
        )
    end

    for i = 1, player_count do
        if opts.marriage_bonuses[i] < 0 then
            return failure(
                "bad_marriage_bonuses",
                "marriage_bonuses entries must be non-negative",
                { player = i, actual = opts.marriage_bonuses[i] }
            )
        end
    end

    local card_points_rounded = {}
    local deal_scores = {}
    for i = 1, player_count do
        card_points_rounded[i] = round_to_nearest(opts.captured_points[i], nearest)
        deal_scores[i] = card_points_rounded[i] + opts.marriage_bonuses[i]
    end

    local made_contract = deal_scores[declarer] >= bid

    local deltas = {}
    for i = 1, player_count do
        if i == declarer then
            deltas[i] = made_contract and bid or -bid
        else
            deltas[i] = deal_scores[i]
        end
    end

    local running_totals_after = {}
    for i = 1, player_count do
        running_totals_after[i] = opts.running_totals[i] + deltas[i]
    end

    local state = tag_as_scoring({
        schema_version = M.SCHEMA_VERSION,
        config = config,
        declarer = declarer,
        bid = bid,
        captured_points = copy_int_list(opts.captured_points, player_count),
        card_points_rounded = card_points_rounded,
        marriage_bonuses = copy_int_list(opts.marriage_bonuses, player_count),
        deal_scores = deal_scores,
        made_contract = made_contract,
        deltas = deltas,
        running_totals_before = copy_int_list(opts.running_totals, player_count),
        running_totals = running_totals_after,
    })
    return { ok = true, scoring = state }
end

function M.is_scoring(value)
    if type(value) ~= "table" then
        return false
    end
    return getmetatable(value) == SCORING_TYPE
end

return M
