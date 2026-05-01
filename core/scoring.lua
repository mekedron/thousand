-- The Thousand deal scoring and contract resolution.
--
-- Phase 1.7 of the engine. Two layers live here:
--
--  1. `score_deal(config, opts)` turns the captured card points and
--     marriage bonuses of one finished deal into a per-player delta
--     against running totals.
--  2. `advance_game(config, opts)` applies one deal's deltas to the
--     game-level state — running totals, the per-player barrel state,
--     and the winner — under the rules in docs/rules/scoring.md
--     (mounting the barrel at the threshold, the score-frozen window
--     of `barrel.deal_count` deals to score the closing 120, falling
--     off, the last-mounter-survives collision rule, and the
--     declarer-wins-ties rule when crossing the target score).
--
-- The canonical Russian rule (the only template Phase 1 ships) is:
--   * captured card points round to the nearest `scoring.round_to_nearest`
--     (Russian default 5); marriage bonuses are exact.
--   * deal_score[player] = rounded_card_points[player]
--                          + marriage_bonuses[player].
--   * declarer's contract is made iff deal_score[declarer] >= bid.
--   * declarer adds bid on success and subtracts bid on failure.
--   * defenders always add their own deal_score.
--   * the barrel sits at `config.barrel.threshold` (880); the closing
--     gap to win is `endgame.target_score - barrel.threshold` (120);
--     three barrel deals are allowed (`barrel.deal_count`); failing all
--     three drops the player by `barrel.fall_off_penalty` (-120) back
--     to 760.
-- Variants change behavior through `RuleConfig.scoring` / `barrel` /
-- `endgame` toggles in Phase 3 (score actual points on success, round
-- before checking the contract, different threshold, different barrel
-- deal count, ...); none of those toggles is read here yet.
--
-- API mirrors `core.auction` / `core.talon` / `core.marriages` /
-- `core.tricks`:
--   * `M.score_deal(config, opts)` returns either
--     { ok = true, scoring = <state> } or
--     { ok = false, error = { code, message, ...extra } }.
--   * `M.advance_game(config, opts)` returns either
--     { ok = true, game = <state> } or { ok = false, error = ... }.
--   * The result states are type-tagged via `__metatable` so
--     `M.is_scoring` / `M.is_game` recognise them.
--   * Every transition produces a fresh state; the input is never
--     mutated. The output's per-player lists are independent copies.

local rule_config = require("core.rule_config")
local card = require("core.card")

local M = {}

M.SCHEMA_VERSION = 1

local SCORING_TYPE = "thousand.scoring"
local GAME_TYPE = "thousand.game_score"

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

local function tag_as_game(state)
    return setmetatable(state, { __metatable = GAME_TYPE })
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

    -- The deck-total cap follows from the active config: every card in
    -- the 24-card pack is captured exactly once across all sides, so the
    -- ceiling is `#SUITS × Σ(point_values)`. Canonical Russian → 120;
    -- a variant that bumps K from 4 to 5 → 124.
    local rank_total = 0
    for _, rank in ipairs(config.cards.trick_rank_order) do
        rank_total = rank_total + config.cards.point_values[rank]
    end
    local deck_point_total = rank_total * #card.SUITS

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
    if captured_sum > deck_point_total then
        return failure(
            "captured_points_exceed_deck",
            "captured card points sum must not exceed the deck total",
            { actual = captured_sum, max = deck_point_total }
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

local function copy_barrel_entry(entry)
    if entry.on_barrel then
        return {
            on_barrel = true,
            mounted_on_deal = entry.mounted_on_deal,
            deals_remaining = entry.deals_remaining,
        }
    end
    return { on_barrel = false }
end

local function off_barrel_entry()
    return { on_barrel = false }
end

local function validate_barrel_state_before(list, count, deal_count)
    if type(list) ~= "table" then
        return failure(
            "bad_barrel_state_before",
            "barrel_state_before must be a list of " .. count .. " entries",
            { actual = type(list) }
        )
    end
    if #list ~= count then
        return failure(
            "bad_barrel_state_before",
            "barrel_state_before must hold one entry per player",
            { actual = #list, expected = count }
        )
    end
    for i = 1, count do
        local entry = list[i]
        if type(entry) ~= "table" then
            return failure(
                "bad_barrel_state_before",
                "barrel_state_before entries must be tables",
                { player = i, actual = type(entry) }
            )
        end
        if type(entry.on_barrel) ~= "boolean" then
            return failure(
                "bad_barrel_state_before",
                "barrel_state_before[i].on_barrel must be a boolean",
                { player = i, actual = type(entry.on_barrel) }
            )
        end
        if entry.on_barrel then
            if not is_integer(entry.mounted_on_deal) or entry.mounted_on_deal < 1 then
                return failure(
                    "bad_barrel_state_before",
                    "on-barrel entries must record a positive-integer mounted_on_deal",
                    { player = i, actual = entry.mounted_on_deal }
                )
            end
            if
                not is_integer(entry.deals_remaining)
                or entry.deals_remaining < 1
                or entry.deals_remaining > deal_count
            then
                return failure(
                    "bad_barrel_state_before",
                    "on-barrel entries must record deals_remaining in 1.." .. deal_count,
                    { player = i, actual = entry.deals_remaining, max = deal_count }
                )
            end
        end
    end
    return nil
end

function M.initial_barrel_state(config)
    if not rule_config.is_rule_config(config) then
        error("scoring.initial_barrel_state requires a RuleConfig", 2)
    end
    local n = config.players.count
    local state = {}
    for i = 1, n do
        state[i] = off_barrel_entry()
    end
    return state
end

-- Apply one deal's per-player deltas against the running game-level
-- state, honouring the barrel rules. The output is a fresh, type-tagged
-- state; the input is never mutated.
function M.advance_game(config, opts)
    if not rule_config.is_rule_config(config) then
        return failure("not_a_rule_config", "scoring.advance_game requires a RuleConfig", {
            actual = type(config),
        })
    end
    if type(opts) ~= "table" then
        return failure("bad_opts", "scoring.advance_game requires an opts table", {
            actual = type(opts),
        })
    end

    local player_count = config.players.count
    local target = config.endgame.target_score
    local threshold = config.barrel.threshold
    local barrel_deal_count = config.barrel.deal_count
    local fall_off_total = threshold + config.barrel.fall_off_penalty
    local barrel_make = target - threshold

    local declarer = opts.declarer
    if not (is_integer(declarer) and declarer >= 1 and declarer <= player_count) then
        return failure(
            "bad_declarer",
            "declarer must be an integer in 1.." .. player_count,
            { actual = declarer, player_count = player_count }
        )
    end

    local deal_index = opts.deal_index
    if not (is_integer(deal_index) and deal_index >= 1) then
        return failure("bad_deal_index", "deal_index must be a positive integer", {
            actual = deal_index,
        })
    end

    local deltas_err = validate_player_list("deltas", opts.deltas, player_count)
    if deltas_err then
        return deltas_err
    end

    local totals_err =
        validate_player_list("running_totals_before", opts.running_totals_before, player_count)
    if totals_err then
        return totals_err
    end

    local barrel_err =
        validate_barrel_state_before(opts.barrel_state_before, player_count, barrel_deal_count)
    if barrel_err then
        return barrel_err
    end

    local running_totals = {}
    local barrel_state = {}

    for i = 1, player_count do
        local before_total = opts.running_totals_before[i]
        local before_entry = opts.barrel_state_before[i]
        local delta = opts.deltas[i]

        if before_entry.on_barrel then
            if delta >= barrel_make then
                running_totals[i] = target
                barrel_state[i] = off_barrel_entry()
            else
                local deals_remaining = before_entry.deals_remaining - 1
                if deals_remaining <= 0 then
                    running_totals[i] = fall_off_total
                    barrel_state[i] = off_barrel_entry()
                else
                    running_totals[i] = threshold
                    barrel_state[i] = {
                        on_barrel = true,
                        mounted_on_deal = before_entry.mounted_on_deal,
                        deals_remaining = deals_remaining,
                    }
                end
            end
        else
            local new_total = before_total + delta
            if new_total >= target then
                running_totals[i] = new_total
                barrel_state[i] = off_barrel_entry()
            elseif new_total >= threshold then
                running_totals[i] = threshold
                barrel_state[i] = {
                    on_barrel = true,
                    mounted_on_deal = deal_index,
                    deals_remaining = barrel_deal_count,
                }
            else
                running_totals[i] = new_total
                barrel_state[i] = off_barrel_entry()
            end
        end
    end

    -- Collision rule: if more than one player ends the deal on the
    -- barrel, only the latest-to-mount stays. Same-deal mounts are
    -- broken by declarer-wins-ties, then lowest player index.
    local on_barrel_indices = {}
    for i = 1, player_count do
        if barrel_state[i].on_barrel then
            on_barrel_indices[#on_barrel_indices + 1] = i
        end
    end
    if #on_barrel_indices > 1 then
        local latest = -1
        for _, i in ipairs(on_barrel_indices) do
            if barrel_state[i].mounted_on_deal > latest then
                latest = barrel_state[i].mounted_on_deal
            end
        end
        local at_latest = {}
        for _, i in ipairs(on_barrel_indices) do
            if barrel_state[i].mounted_on_deal == latest then
                at_latest[#at_latest + 1] = i
            end
        end
        local survivor
        for _, i in ipairs(at_latest) do
            if i == declarer then
                survivor = i
                break
            end
        end
        if not survivor then
            survivor = at_latest[1]
        end
        for _, i in ipairs(on_barrel_indices) do
            if i ~= survivor then
                running_totals[i] = fall_off_total
                barrel_state[i] = off_barrel_entry()
            end
        end
    end

    -- Winner: any player at or above the target. Multiple → highest
    -- total; ties at the highest → declarer wins, else lowest index.
    local winner
    local at_or_above = {}
    for i = 1, player_count do
        if running_totals[i] >= target then
            at_or_above[#at_or_above + 1] = i
        end
    end
    if #at_or_above == 1 then
        winner = at_or_above[1]
    elseif #at_or_above > 1 then
        local max_total = -math.huge
        for _, i in ipairs(at_or_above) do
            if running_totals[i] > max_total then
                max_total = running_totals[i]
            end
        end
        local at_max = {}
        for _, i in ipairs(at_or_above) do
            if running_totals[i] == max_total then
                at_max[#at_max + 1] = i
            end
        end
        if #at_max == 1 then
            winner = at_max[1]
        else
            for _, i in ipairs(at_max) do
                if i == declarer then
                    winner = i
                    break
                end
            end
            if not winner then
                winner = at_max[1]
            end
        end
    end

    local barrel_state_copy = {}
    for i = 1, player_count do
        barrel_state_copy[i] = copy_barrel_entry(barrel_state[i])
    end

    local state = tag_as_game({
        schema_version = M.SCHEMA_VERSION,
        config = config,
        deal_index = deal_index,
        declarer = declarer,
        running_totals = running_totals,
        barrel_state = barrel_state_copy,
        winner = winner,
    })
    return { ok = true, game = state }
end

function M.is_game(value)
    if type(value) ~= "table" then
        return false
    end
    return getmetatable(value) == GAME_TYPE
end

return M
