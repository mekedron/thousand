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

    -- Phase 3.6 marriage house-rule bonus inputs. Both default to a
    -- per-player zero list when absent so existing callers keep
    -- their original contract.
    local half_marriage_capture_bonuses = opts.half_marriage_capture_bonuses
    if half_marriage_capture_bonuses == nil then
        half_marriage_capture_bonuses = {}
        for i = 1, player_count do
            half_marriage_capture_bonuses[i] = 0
        end
    else
        local err = validate_player_list(
            "half_marriage_capture_bonuses",
            half_marriage_capture_bonuses,
            player_count
        )
        if err then
            return err
        end
    end
    local ace_marriage_bonuses = opts.ace_marriage_bonuses
    if ace_marriage_bonuses == nil then
        ace_marriage_bonuses = {}
        for i = 1, player_count do
            ace_marriage_bonuses[i] = 0
        end
    else
        local err = validate_player_list("ace_marriage_bonuses", ace_marriage_bonuses, player_count)
        if err then
            return err
        end
    end

    -- Phase 3.6 trick-play house-rule bonus inputs. Same default-zero
    -- contract as the marriage bonuses; signed (last-trick adds,
    -- slam-against subtracts) so the session can express the
    -- declarer-loses-on-zero-tricks penalty as a negative entry.
    local function default_zero_list_or_validate(name, list)
        if list == nil then
            local zeros = {}
            for i = 1, player_count do
                zeros[i] = 0
            end
            return zeros, nil
        end
        return list, validate_player_list(name, list, player_count)
    end

    local last_trick_bonus, err1 =
        default_zero_list_or_validate("last_trick_bonus", opts.last_trick_bonus)
    if err1 then
        return err1
    end
    local slam_bonus, err2 = default_zero_list_or_validate("slam_bonus", opts.slam_bonus)
    if err2 then
        return err2
    end
    local slam_against_penalty, err3 =
        default_zero_list_or_validate("slam_against_penalty", opts.slam_against_penalty)
    if err3 then
        return err3
    end

    -- bid_multiplier realises `slam_bonus = "doubled_bid"` (2 on success;
    -- 1 otherwise). Applied to the input `bid` before the contract check
    -- and the +/-bid delta, so the success/failure reward scales but
    -- everything else (deal scores, marriage bonuses, trick bonuses) stays
    -- in raw card-point units.
    local bid_multiplier = opts.bid_multiplier
    if bid_multiplier == nil then
        bid_multiplier = 1
    elseif type(bid_multiplier) ~= "number" or bid_multiplier <= 0 then
        return failure(
            "bad_bid_multiplier",
            "bid_multiplier must be a positive number when set",
            { actual = bid_multiplier }
        )
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
        if half_marriage_capture_bonuses[i] < 0 then
            return failure(
                "bad_half_marriage_capture_bonuses",
                "half_marriage_capture_bonuses entries must be non-negative",
                { player = i, actual = half_marriage_capture_bonuses[i] }
            )
        end
        if ace_marriage_bonuses[i] < 0 then
            return failure(
                "bad_ace_marriage_bonuses",
                "ace_marriage_bonuses entries must be non-negative",
                { player = i, actual = ace_marriage_bonuses[i] }
            )
        end
    end

    local card_points_rounded = {}
    local deal_scores = {}
    for i = 1, player_count do
        card_points_rounded[i] = round_to_nearest(opts.captured_points[i], nearest)
        deal_scores[i] = card_points_rounded[i]
            + opts.marriage_bonuses[i]
            + half_marriage_capture_bonuses[i]
            + ace_marriage_bonuses[i]
            + last_trick_bonus[i]
            + slam_bonus[i]
            + slam_against_penalty[i]
    end

    local partnership_mode = config.players.partnership_mode
    local sides
    local side_of_seat
    if partnership_mode == "fixed_across_table" and player_count == 4 then
        side_of_seat = function(seat)
            return ((seat - 1) % 2) + 1
        end
        sides = { side_of_seat(1), side_of_seat(2), side_of_seat(3), side_of_seat(4) }
    end

    local effective_bid = bid * bid_multiplier
    local made_contract
    local side_deal_scores
    local declarer_side
    if sides then
        side_deal_scores = { 0, 0 }
        for i = 1, player_count do
            local s = sides[i]
            side_deal_scores[s] = side_deal_scores[s] + deal_scores[i]
        end
        declarer_side = sides[declarer]
        made_contract = side_deal_scores[declarer_side] >= effective_bid
    else
        made_contract = deal_scores[declarer] >= effective_bid
    end

    -- Per-seat deltas. Partnership accounting credits the contract delta
    -- to the declarer's seat alone (the partner contributes 0 at the seat
    -- level); the side total is derived by summing the partner pair so
    -- the declarer's seat carries the +/-bid and the partner's pooled
    -- capture is dropped (the bid replaces it for the side).
    local deltas = {}
    for i = 1, player_count do
        if i == declarer then
            deltas[i] = made_contract and effective_bid or -effective_bid
        elseif sides and sides[i] == declarer_side then
            deltas[i] = 0
        else
            deltas[i] = deal_scores[i]
        end
    end

    local running_totals_after = {}
    for i = 1, player_count do
        running_totals_after[i] = opts.running_totals[i] + deltas[i]
    end

    -- Side-level aggregates for partnership variants. The UI uses these
    -- to render a pooled-side row alongside per-seat scoreboard entries.
    local side_running_totals_before
    local side_running_totals_after
    local side_deltas
    if sides then
        side_running_totals_before = { 0, 0 }
        side_deltas = { 0, 0 }
        for i = 1, player_count do
            local s = sides[i]
            side_running_totals_before[s] = side_running_totals_before[s] + opts.running_totals[i]
            side_deltas[s] = side_deltas[s] + deltas[i]
        end
        side_running_totals_after = {
            side_running_totals_before[1] + side_deltas[1],
            side_running_totals_before[2] + side_deltas[2],
        }
    end

    local state = tag_as_scoring({
        schema_version = M.SCHEMA_VERSION,
        config = config,
        declarer = declarer,
        bid = bid,
        bid_multiplier = bid_multiplier,
        effective_bid = effective_bid,
        captured_points = copy_int_list(opts.captured_points, player_count),
        card_points_rounded = card_points_rounded,
        marriage_bonuses = copy_int_list(opts.marriage_bonuses, player_count),
        half_marriage_capture_bonuses = copy_int_list(half_marriage_capture_bonuses, player_count),
        ace_marriage_bonuses = copy_int_list(ace_marriage_bonuses, player_count),
        last_trick_bonus = copy_int_list(last_trick_bonus, player_count),
        slam_bonus = copy_int_list(slam_bonus, player_count),
        slam_against_penalty = copy_int_list(slam_against_penalty, player_count),
        deal_scores = deal_scores,
        made_contract = made_contract,
        deltas = deltas,
        running_totals_before = copy_int_list(opts.running_totals, player_count),
        running_totals = running_totals_after,
        partnership_mode = partnership_mode,
        sides = sides,
        side_deal_scores = side_deal_scores,
        side_deltas = side_deltas,
        side_running_totals_before = side_running_totals_before,
        side_running_totals = side_running_totals_after,
    })
    return { ok = true, scoring = state }
end

-- Raspassy scoring. Triggered when `dealing.all_pass_handling = "raspassy"`
-- and the auction terminates with no contract: the deal plays out as 8
-- tricks without trump or marriages, then each seat's captured
-- card-points are *subtracted* from their running total. The convention
-- chosen for this engine — every player loses what they took — captures
-- the spirit of the doc-listed traditions ("fewest scores theirs" /
-- "most loses theirs") without introducing tiebreaker rules. See
-- docs/variations/house-rules.md "All-pass handling".
--
-- Inputs: { captured_points, running_totals }; declarer/bid/marriages are
-- absent because raspassy has no contract and the engine forbids
-- marriages during the deal. Output mirrors `score_deal`'s state shape
-- so the table view-model and tests can read the same fields, with
-- `declarer = nil`, `bid = 0`, `made_contract = nil`,
-- `marriage_bonuses = zeros`.
function M.score_raspassy(config, opts)
    if not rule_config.is_rule_config(config) then
        return failure("not_a_rule_config", "scoring.score_raspassy requires a RuleConfig", {
            actual = type(config),
        })
    end
    if type(opts) ~= "table" then
        return failure("bad_opts", "scoring.score_raspassy requires an opts table", {
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

    local captured_err = validate_player_list("captured_points", opts.captured_points, player_count)
    if captured_err then
        return captured_err
    end
    local totals_err = validate_player_list("running_totals", opts.running_totals, player_count)
    if totals_err then
        return totals_err
    end

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

    local card_points_rounded = {}
    local marriage_bonuses = {}
    local half_marriage_capture_bonuses = {}
    local ace_marriage_bonuses = {}
    local deal_scores = {}
    local deltas = {}
    for i = 1, player_count do
        card_points_rounded[i] = round_to_nearest(opts.captured_points[i], nearest)
        marriage_bonuses[i] = 0
        half_marriage_capture_bonuses[i] = 0
        ace_marriage_bonuses[i] = 0
        deal_scores[i] = card_points_rounded[i]
        deltas[i] = -card_points_rounded[i]
    end

    local running_totals_after = {}
    for i = 1, player_count do
        running_totals_after[i] = opts.running_totals[i] + deltas[i]
    end

    local partnership_mode = config.players.partnership_mode
    local sides
    local side_deal_scores
    local side_running_totals_before
    local side_running_totals_after
    local side_deltas
    if partnership_mode == "fixed_across_table" and player_count == 4 then
        sides = { 1, 2, 1, 2 }
        side_deal_scores = { 0, 0 }
        side_running_totals_before = { 0, 0 }
        side_deltas = { 0, 0 }
        for i = 1, player_count do
            local s = sides[i]
            side_deal_scores[s] = side_deal_scores[s] + deal_scores[i]
            side_running_totals_before[s] = side_running_totals_before[s] + opts.running_totals[i]
            side_deltas[s] = side_deltas[s] + deltas[i]
        end
        side_running_totals_after = {
            side_running_totals_before[1] + side_deltas[1],
            side_running_totals_before[2] + side_deltas[2],
        }
    end

    local state = tag_as_scoring({
        schema_version = M.SCHEMA_VERSION,
        config = config,
        declarer = nil,
        bid = 0,
        captured_points = copy_int_list(opts.captured_points, player_count),
        card_points_rounded = card_points_rounded,
        marriage_bonuses = marriage_bonuses,
        half_marriage_capture_bonuses = half_marriage_capture_bonuses,
        ace_marriage_bonuses = ace_marriage_bonuses,
        deal_scores = deal_scores,
        made_contract = nil,
        deltas = deltas,
        running_totals_before = copy_int_list(opts.running_totals, player_count),
        running_totals = running_totals_after,
        partnership_mode = partnership_mode,
        sides = sides,
        side_deal_scores = side_deal_scores,
        side_deltas = side_deltas,
        side_running_totals_before = side_running_totals_before,
        side_running_totals = side_running_totals_after,
        raspassy = true,
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

local function partnership_sides(config)
    if config.players.partnership_mode == "fixed_across_table" and config.players.count == 4 then
        return { 1, 2, 1, 2 }
    end
    return nil
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

    local sides = partnership_sides(config)

    local running_totals = {}
    local barrel_state = {}

    -- Reduce the per-seat → per-side mapping so the barrel/threshold
    -- rules apply at the side level. Each seat in a side ends the deal
    -- with its side's running total and barrel entry, so per-seat
    -- callers (UI, save format, legacy specs) keep working unchanged.
    local function indices_for(unit)
        if not sides then
            return { unit }
        end
        local list = {}
        for i = 1, player_count do
            if sides[i] == unit then
                list[#list + 1] = i
            end
        end
        return list
    end

    local unit_count
    if sides then
        unit_count = 2
    else
        unit_count = player_count
    end

    -- Aggregate the inputs to whichever unit (per-seat or per-side) the
    -- variant scores at. Partner seats must share a barrel entry on
    -- input — we just take the first seat's entry as representative.
    local function unit_total_before(unit)
        if not sides then
            return opts.running_totals_before[unit]
        end
        local idx = indices_for(unit)[1]
        return opts.running_totals_before[idx]
    end
    local function unit_delta(unit)
        if not sides then
            return opts.deltas[unit]
        end
        local total = 0
        for _, i in ipairs(indices_for(unit)) do
            total = total + opts.deltas[i]
        end
        return total
    end
    local function unit_barrel_before(unit)
        if not sides then
            return opts.barrel_state_before[unit]
        end
        local idx = indices_for(unit)[1]
        return opts.barrel_state_before[idx]
    end

    local unit_running = {}
    local unit_barrel = {}
    for u = 1, unit_count do
        local before_total = unit_total_before(u)
        local before_entry = unit_barrel_before(u)
        local delta = unit_delta(u)

        if before_entry.on_barrel then
            if delta >= barrel_make then
                unit_running[u] = target
                unit_barrel[u] = off_barrel_entry()
            else
                local deals_remaining = before_entry.deals_remaining - 1
                if deals_remaining <= 0 then
                    unit_running[u] = fall_off_total
                    unit_barrel[u] = off_barrel_entry()
                else
                    unit_running[u] = threshold
                    unit_barrel[u] = {
                        on_barrel = true,
                        mounted_on_deal = before_entry.mounted_on_deal,
                        deals_remaining = deals_remaining,
                    }
                end
            end
        else
            local new_total = before_total + delta
            if new_total >= target then
                unit_running[u] = new_total
                unit_barrel[u] = off_barrel_entry()
            elseif new_total >= threshold then
                unit_running[u] = threshold
                unit_barrel[u] = {
                    on_barrel = true,
                    mounted_on_deal = deal_index,
                    deals_remaining = barrel_deal_count,
                }
            else
                unit_running[u] = new_total
                unit_barrel[u] = off_barrel_entry()
            end
        end
    end

    local declarer_unit = sides and sides[declarer] or declarer

    -- Collision rule at the unit level: if more than one unit ends the
    -- deal on the barrel, only the latest-to-mount stays. Same-deal
    -- mounts are broken by declarer-wins-ties, then lowest unit index.
    local on_barrel_units = {}
    for u = 1, unit_count do
        if unit_barrel[u].on_barrel then
            on_barrel_units[#on_barrel_units + 1] = u
        end
    end
    if #on_barrel_units > 1 then
        local latest = -1
        for _, u in ipairs(on_barrel_units) do
            if unit_barrel[u].mounted_on_deal > latest then
                latest = unit_barrel[u].mounted_on_deal
            end
        end
        local at_latest = {}
        for _, u in ipairs(on_barrel_units) do
            if unit_barrel[u].mounted_on_deal == latest then
                at_latest[#at_latest + 1] = u
            end
        end
        local survivor
        for _, u in ipairs(at_latest) do
            if u == declarer_unit then
                survivor = u
                break
            end
        end
        if not survivor then
            survivor = at_latest[1]
        end
        for _, u in ipairs(on_barrel_units) do
            if u ~= survivor then
                unit_running[u] = fall_off_total
                unit_barrel[u] = off_barrel_entry()
            end
        end
    end

    -- Winner at unit level. Per-seat winner is the lowest-numbered seat
    -- in the winning unit so legacy callers reading a single integer
    -- keep working.
    local winning_unit
    local at_or_above = {}
    for u = 1, unit_count do
        if unit_running[u] >= target then
            at_or_above[#at_or_above + 1] = u
        end
    end
    if #at_or_above == 1 then
        winning_unit = at_or_above[1]
    elseif #at_or_above > 1 then
        local max_total = -math.huge
        for _, u in ipairs(at_or_above) do
            if unit_running[u] > max_total then
                max_total = unit_running[u]
            end
        end
        local at_max = {}
        for _, u in ipairs(at_or_above) do
            if unit_running[u] == max_total then
                at_max[#at_max + 1] = u
            end
        end
        if #at_max == 1 then
            winning_unit = at_max[1]
        else
            for _, u in ipairs(at_max) do
                if u == declarer_unit then
                    winning_unit = u
                    break
                end
            end
            if not winning_unit then
                winning_unit = at_max[1]
            end
        end
    end

    -- Fan unit-level state out to per-seat lists. Partner seats end the
    -- deal with the side's running total and barrel entry.
    for i = 1, player_count do
        local u = sides and sides[i] or i
        running_totals[i] = unit_running[u]
        barrel_state[i] = unit_barrel[u]
    end

    local winner
    if winning_unit then
        if sides then
            for i = 1, player_count do
                if sides[i] == winning_unit then
                    winner = i
                    break
                end
            end
        else
            winner = winning_unit
        end
    end

    local barrel_state_copy = {}
    for i = 1, player_count do
        barrel_state_copy[i] = copy_barrel_entry(barrel_state[i])
    end

    -- Per-side aggregates for the UI's pooled-side scoreboard row.
    local side_running_totals
    local side_barrel_state
    local winning_side
    if sides then
        side_running_totals = { unit_running[1], unit_running[2] }
        side_barrel_state = {
            copy_barrel_entry(unit_barrel[1]),
            copy_barrel_entry(unit_barrel[2]),
        }
        winning_side = winning_unit
    end

    local state = tag_as_game({
        schema_version = M.SCHEMA_VERSION,
        config = config,
        deal_index = deal_index,
        declarer = declarer,
        running_totals = running_totals,
        barrel_state = barrel_state_copy,
        winner = winner,
        sides = sides,
        side_running_totals = side_running_totals,
        side_barrel_state = side_barrel_state,
        winning_side = winning_side,
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
