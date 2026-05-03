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

-- Phase 3.6 special-contract scoring path. A named-contract bid is a
-- structured `{ kind = "named", contract = "mizere"|"slam"|"open_hand",
-- value = N }` table carrying the score change to apply. Defenders score
-- zero on every named contract — the documented Russian/Polish/Ukrainian
-- wording treats these as declarer-vs-bid only. The returned state
-- preserves `score_deal`'s shape (zero-filled bonus arrays, structured
-- `bid` echo, named_contract block) so the session and view-model can
-- read the same fields without branching on contract type. Open-hand's
-- documented "doubled scoring" is encoded at the schema level: the
-- structured bid carries `value = 200` (= 2 × the canonical 100 base),
-- so this helper applies no further multiplier.
local function score_named_contract(config, opts, declarer, player_count, nearest)
    local bid = opts.bid
    if bid.kind ~= "named" then
        return failure("bad_bid", "structured bid requires kind = 'named'", {
            actual_kind = bid.kind,
        })
    end
    if type(bid.contract) ~= "string" then
        return failure("bad_bid", "named bid requires a string contract", {
            actual = type(bid.contract),
        })
    end
    if not is_integer(bid.value) or bid.value <= 0 then
        return failure("bad_bid", "named bid requires a positive integer value", {
            actual = bid.value,
        })
    end
    if type(opts.named_contract_made) ~= "boolean" then
        return failure(
            "bad_named_contract_made",
            "named contract requires boolean opts.named_contract_made",
            { actual = type(opts.named_contract_made) }
        )
    end

    local captured_err = validate_player_list("captured_points", opts.captured_points, player_count)
    if captured_err then
        return captured_err
    end
    for i = 1, player_count do
        if opts.captured_points[i] < 0 then
            return failure(
                "bad_captured_points",
                "captured_points entries must be non-negative",
                { player = i, actual = opts.captured_points[i] }
            )
        end
    end
    local totals_err = validate_player_list("running_totals", opts.running_totals, player_count)
    if totals_err then
        return totals_err
    end

    local effective_bid = bid.value
    local made_contract = opts.named_contract_made

    local zeros = {}
    for i = 1, player_count do
        zeros[i] = 0
    end

    local card_points_rounded = {}
    for i = 1, player_count do
        card_points_rounded[i] = round_to_nearest(opts.captured_points[i], nearest)
    end

    local deltas = {}
    for i = 1, player_count do
        if i == declarer then
            deltas[i] = made_contract and effective_bid or -effective_bid
        else
            deltas[i] = 0
        end
    end

    local running_totals_after = {}
    for i = 1, player_count do
        running_totals_after[i] = opts.running_totals[i] + deltas[i]
    end

    local partnership_mode = config.players.partnership_mode
    local sides
    local side_deal_scores
    local side_deltas
    local side_running_totals_before
    local side_running_totals_after
    if partnership_mode == "fixed_across_table" and player_count == 4 then
        sides = { 1, 2, 1, 2 }
        side_deal_scores = { 0, 0 }
        side_deltas = { 0, 0 }
        side_running_totals_before = { 0, 0 }
        for i = 1, player_count do
            local s = sides[i]
            side_deltas[s] = side_deltas[s] + deltas[i]
            side_running_totals_before[s] = side_running_totals_before[s] + opts.running_totals[i]
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
        bid = { kind = "named", contract = bid.contract, value = bid.value },
        bid_multiplier = 1,
        effective_bid = effective_bid,
        captured_points = copy_int_list(opts.captured_points, player_count),
        card_points_rounded = card_points_rounded,
        marriage_bonuses = copy_int_list(zeros, player_count),
        half_marriage_capture_bonuses = copy_int_list(zeros, player_count),
        ace_marriage_bonuses = copy_int_list(zeros, player_count),
        last_trick_bonus = copy_int_list(zeros, player_count),
        slam_bonus = copy_int_list(zeros, player_count),
        slam_against_penalty = copy_int_list(zeros, player_count),
        deal_scores = copy_int_list(zeros, player_count),
        made_contract = made_contract,
        contract_check_value = made_contract and effective_bid or 0,
        success_payout = effective_bid,
        defender_pool_total = nil,
        failed_contract_distribution_extras = copy_int_list(zeros, player_count),
        deltas = deltas,
        running_totals_before = copy_int_list(opts.running_totals, player_count),
        running_totals = running_totals_after,
        partnership_mode = partnership_mode,
        sides = sides,
        side_deal_scores = side_deal_scores,
        side_deltas = side_deltas,
        side_running_totals_before = side_running_totals_before,
        side_running_totals = side_running_totals_after,
        named_contract = { kind = bid.contract, value = bid.value },
    })
    return { ok = true, scoring = state }
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
    -- Phase 3.6 named-contract dispatch. Structured bids carry
    -- `{ kind = "named", contract, value }` from `core.auction`'s
    -- `bid_named` path; route them to the dedicated scorer.
    if type(bid) == "table" then
        return score_named_contract(config, opts, declarer, player_count, nearest)
    end
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
    local side_deal_scores
    local declarer_side
    if sides then
        side_deal_scores = { 0, 0 }
        for i = 1, player_count do
            local s = sides[i]
            side_deal_scores[s] = side_deal_scores[s] + deal_scores[i]
        end
        declarer_side = sides[declarer]
    end

    -- Phase 3.6 scoring house-rule: declarer_rounding_before_contract_check.
    -- `on` (canonical Russian, Phase 1.7 default) checks the declarer's
    -- rounded deal_score against the bid; `off` (strict tournament)
    -- compares the raw captured-points + exact bonuses to the bid so a
    -- 118-captured-vs-120-bid hand fails. Bonuses themselves are exact in
    -- both modes; only captured card-points round.
    local function exact_bonuses_at(seat)
        return opts.marriage_bonuses[seat]
            + half_marriage_capture_bonuses[seat]
            + ace_marriage_bonuses[seat]
            + last_trick_bonus[seat]
            + slam_bonus[seat]
            + slam_against_penalty[seat]
    end
    local rounding_mode = config.scoring.declarer_rounding_before_contract_check
    local contract_check_value
    if sides then
        if rounding_mode == "off" then
            contract_check_value = 0
            for i = 1, player_count do
                if sides[i] == declarer_side then
                    contract_check_value = contract_check_value
                        + opts.captured_points[i]
                        + exact_bonuses_at(i)
                end
            end
        else
            contract_check_value = side_deal_scores[declarer_side]
        end
    else
        if rounding_mode == "off" then
            contract_check_value = opts.captured_points[declarer] + exact_bonuses_at(declarer)
        else
            contract_check_value = deal_scores[declarer]
        end
    end
    local made_contract = contract_check_value >= effective_bid

    -- Phase 3.6 scoring house-rule: actual_points_on_success. When `on`,
    -- a successful declarer scores `max(bid, deal_score)` instead of
    -- just the bid. Falls back to effective_bid on failure (loss path
    -- unchanged).
    local declarer_deal_value = sides and side_deal_scores[declarer_side] or deal_scores[declarer]
    local success_payout = effective_bid
    if
        made_contract
        and config.scoring.actual_points_on_success == "on"
        and declarer_deal_value > effective_bid
    then
        success_payout = declarer_deal_value
    end

    -- Phase 3.6 scoring house-rules: defender_contributions and
    -- failed_contract_distribution. Build the defender seat list (every
    -- seat not on the declarer's side); pool defender deal scores when
    -- requested; add the failed-contract distribution share on failure.
    -- Inert under partnership_mode for `pooled` (the side accounting is
    -- already pooled at the side level) — `failed_contract_distribution`
    -- is honoured in both modes.
    local defender_seats = {}
    for i = 1, player_count do
        if i ~= declarer and (not sides or sides[i] ~= declarer_side) then
            defender_seats[#defender_seats + 1] = i
        end
    end

    local defender_base = {}
    for _, i in ipairs(defender_seats) do
        defender_base[i] = deal_scores[i]
    end

    local defender_pool_total
    if config.scoring.defender_contributions == "pooled" and not sides and #defender_seats > 0 then
        local pool = 0
        for _, i in ipairs(defender_seats) do
            pool = pool + deal_scores[i]
        end
        defender_pool_total = pool
        local share = math.floor(pool / #defender_seats)
        local remainder = pool - share * #defender_seats
        for k, i in ipairs(defender_seats) do
            defender_base[i] = share + (k == 1 and remainder or 0)
        end
    end

    local failed_contract_distribution_extras = {}
    for i = 1, player_count do
        failed_contract_distribution_extras[i] = 0
    end
    if not made_contract and #defender_seats > 0 then
        local mode = config.scoring.failed_contract_distribution
        if mode == "mirrors_forced_concession" then
            local fbc = config.bidding.forced_bid_concession
            if fbc == "equal_split" then
                mode = "split_among_defenders"
            elseif fbc == "each_full" then
                mode = "each_defender_full"
            elseif fbc == "preset_ratio" then
                mode = "preset_ratio_via_concession"
            else
                mode = "lost"
            end
        end
        if mode == "split_among_defenders" then
            local share = math.floor(effective_bid / #defender_seats)
            local remainder = effective_bid - share * #defender_seats
            for k, i in ipairs(defender_seats) do
                failed_contract_distribution_extras[i] = share + (k == 1 and remainder or 0)
            end
        elseif mode == "each_defender_full" then
            for _, i in ipairs(defender_seats) do
                failed_contract_distribution_extras[i] = effective_bid
            end
        elseif mode == "preset_ratio_via_concession" then
            local ratios = config.bidding.forced_bid_concession_preset_ratio or {}
            local credited = 0
            for k, i in ipairs(defender_seats) do
                local r = ratios[k] or 0
                local share = math.floor(effective_bid * r + 0.5)
                failed_contract_distribution_extras[i] = share
                credited = credited + share
            end
            local residual = effective_bid - credited
            if residual ~= 0 then
                local first = defender_seats[1]
                local extras = failed_contract_distribution_extras
                extras[first] = extras[first] + residual
            end
        end
    end

    -- Per-seat deltas. Partnership accounting credits the contract delta
    -- to the declarer's seat alone (the partner contributes 0 at the seat
    -- level); the side total is derived by summing the partner pair so
    -- the declarer's seat carries the +/-bid and the partner's pooled
    -- capture is dropped (the bid replaces it for the side). Defender
    -- deltas combine the (possibly pooled) defender base with the failed-
    -- contract distribution extra.
    local deltas = {}
    for i = 1, player_count do
        if i == declarer then
            deltas[i] = made_contract and success_payout or -effective_bid
        elseif sides and sides[i] == declarer_side then
            deltas[i] = 0
        else
            deltas[i] = (defender_base[i] or deal_scores[i])
                + failed_contract_distribution_extras[i]
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
        contract_check_value = contract_check_value,
        success_payout = success_payout,
        defender_pool_total = defender_pool_total,
        failed_contract_distribution_extras = copy_int_list(
            failed_contract_distribution_extras,
            player_count
        ),
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

-- Phase 3.6 opening-game / barrel / endgame house-rules carry extra
-- per-unit state on the same `barrel_state` array advance_game already
-- threads through the session: a unit may be `pit_locked` (off the
-- barrel but capped at `barrel.pit_score` until cleared by a
-- successful contract), or `on_reverse_barrel` (mirror of the
-- standard barrel at -threshold). Every helper below copies *all*
-- shape-relevant fields so the input is never aliased and saved games
-- round-trip cleanly.
local function copy_barrel_entry(entry)
    local copy = { on_barrel = entry.on_barrel and true or false }
    if entry.on_barrel then
        copy.mounted_on_deal = entry.mounted_on_deal
        copy.deals_remaining = entry.deals_remaining
    end
    if entry.pit_locked then
        copy.pit_locked = true
    end
    if entry.on_reverse_barrel then
        copy.on_reverse_barrel = true
        copy.reverse_mounted_on_deal = entry.reverse_mounted_on_deal
        copy.reverse_deals_remaining = entry.reverse_deals_remaining
    end
    if entry.eliminated then
        copy.eliminated = true
    end
    return copy
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
        -- Phase 3.6 reverse-barrel: a unit cannot be on both barrels at
        -- once. The forward barrel ranges 880..1000; the reverse barrel
        -- ranges -1000..-880. Accept the on_reverse_barrel + counters
        -- shape symmetrically with the forward barrel above.
        if entry.on_reverse_barrel then
            if entry.on_barrel then
                return failure(
                    "bad_barrel_state_before",
                    "a unit cannot sit on the forward and reverse barrel at once",
                    { player = i }
                )
            end
            if
                not is_integer(entry.reverse_mounted_on_deal)
                or entry.reverse_mounted_on_deal < 1
            then
                return failure(
                    "bad_barrel_state_before",
                    "reverse-barrel entries must record a positive-integer reverse_mounted_on_deal",
                    { player = i, actual = entry.reverse_mounted_on_deal }
                )
            end
            if
                not is_integer(entry.reverse_deals_remaining)
                or entry.reverse_deals_remaining < 1
                or entry.reverse_deals_remaining > deal_count
            then
                return failure(
                    "bad_barrel_state_before",
                    "reverse-barrel entries must record reverse_deals_remaining in 1.."
                        .. deal_count,
                    { player = i, actual = entry.reverse_deals_remaining, max = deal_count }
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
--
-- Phase 3.6 opening-game / barrel / endgame house-rules wire eight
-- toggles into this dispatch:
--
--   * `dump_truck`        — running-total reset on landing on ±555.
--   * `pit_lock_in`       — intermediate cap at `barrel.pit_score`
--                            cleared only by a successful declarer
--                            contract.
--   * `overshoot_penalty` — replace the fall-off penalty with the
--                            declarer's bid amount when `bid >
--                            target − threshold` and the contract
--                            failed.
--   * `reverse_barrel`    — symmetric −threshold barrel; reaching
--                            −target eliminates the unit; failing to
--                            climb out falls back to
--                            `reverse_barrel_fallback`.
--   * `collision_rule`    — `last_mounter` (canonical),
--                            `first_mounter`, `all_collide_fall_off`.
--   * `going_over_target` — `win_immediately` (canonical) or
--                            `exact_only`: cap at
--                            `effective_target − 1` until a unit
--                            lands exactly on the target.
--   * `tiebreaker`        — `declarer_wins` (canonical), `high_score`
--                            (lowest seat tiebreaks), `continuation`
--                            (no winner; `effective_target_after`
--                            jumps +500).
--
-- Callers may pass:
--   * `opts.bid`                       — declarer's effective bid for
--                                         overshoot_penalty.
--   * `opts.declarer_made_contract`    — boolean used by pit-lock
--                                         clearing.
--   * `opts.effective_target_before`   — carry the elevated-target
--                                         state across deals when
--                                         `tiebreaker == "continuation"`
--                                         has fired.
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
    local target_default = config.endgame.target_score
    local threshold_default = config.barrel.threshold
    local barrel_deal_count = config.barrel.deal_count
    local barrel_make_default = target_default - threshold_default
    local fall_off_total_default = threshold_default + config.barrel.fall_off_penalty

    -- `effective_target_before` carries the elevated target produced by
    -- prior `tiebreaker == "continuation"` events. When it is missing
    -- (legacy callers, fresh game), fall back to the canonical target.
    -- The barrel threshold and barrel-make gap shift symmetrically so
    -- the closing-gap stays at `target − threshold` (canonically 120).
    local effective_target_before = opts.effective_target_before
    if effective_target_before == nil then
        effective_target_before = target_default
    end
    if not is_integer(effective_target_before) then
        return failure(
            "bad_effective_target_before",
            "effective_target_before must be a positive integer when supplied",
            { actual = effective_target_before }
        )
    end
    local target = effective_target_before
    local target_offset = target - target_default
    local threshold = threshold_default + target_offset
    local fall_off_total = fall_off_total_default + target_offset
    local barrel_make = barrel_make_default

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

    local pit_lock_active = config.barrel.pit_lock_in == "on"
    local pit_score = config.barrel.pit_score
    local overshoot_active = config.barrel.overshoot_penalty == "on"
    local reverse_active = config.barrel.reverse_barrel == "on"
    local reverse_fallback = config.barrel.reverse_barrel_fallback
    local reverse_threshold = -threshold
    local reverse_target = -target
    local collision_rule = config.barrel.collision_rule
    local going_over_target = config.endgame.going_over_target
    local tiebreaker = config.endgame.tiebreaker
    local dump_truck_mode = config.endgame.dump_truck
    local declarer_made_contract = opts.declarer_made_contract and true or false
    local declarer_bid = opts.bid

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

    local declarer_unit = sides and sides[declarer] or declarer

    local unit_running = {}
    local unit_barrel = {}
    -- Phase 3.6 per-unit event arrays surfaced in the returned state so
    -- the session / view-model can render the matching scoreboard rows.
    local unit_dump_truck = {}
    local unit_pit_state = {}
    local unit_overshoot = {}
    local unit_eliminated = {}
    for u = 1, unit_count do
        unit_dump_truck[u] = false
        unit_pit_state[u] = "not_locked"
        unit_overshoot[u] = false
        unit_eliminated[u] = false
    end

    for u = 1, unit_count do
        local before_total = unit_total_before(u)
        local before_entry = unit_barrel_before(u)
        local delta = unit_delta(u)
        local is_declarer_unit = (u == declarer_unit)

        local new_total
        local new_entry
        local pit_state = "not_locked"

        if before_entry.on_reverse_barrel then
            -- Reverse-barrel state machine. Mirrors the forward barrel
            -- at -threshold/-target. Climbing above -threshold escapes;
            -- falling to or past -target eliminates the unit; failing
            -- to do either within `reverse_deals_remaining` deals
            -- falls back to `reverse_barrel_fallback`.
            local raw = before_total + delta
            if raw >= -threshold + 1 then
                -- Escaped above the reverse barrel ceiling. The unit
                -- resumes normal accumulation with the raw new total.
                new_total = raw
                new_entry = off_barrel_entry()
            elseif raw <= -target then
                new_total = -target
                new_entry = off_barrel_entry()
                unit_eliminated[u] = true
            else
                local deals_remaining = before_entry.reverse_deals_remaining - 1
                if deals_remaining <= 0 then
                    new_total = reverse_fallback
                    new_entry = off_barrel_entry()
                else
                    new_total = -threshold
                    new_entry = {
                        on_barrel = false,
                        on_reverse_barrel = true,
                        reverse_mounted_on_deal = before_entry.reverse_mounted_on_deal,
                        reverse_deals_remaining = deals_remaining,
                    }
                end
            end
        elseif before_entry.on_barrel then
            if delta >= barrel_make then
                new_total = target
                new_entry = off_barrel_entry()
            else
                local deals_remaining = before_entry.deals_remaining - 1
                if deals_remaining <= 0 then
                    -- Fall off. Overshoot penalty replaces the standard
                    -- `fall_off_penalty` with the declarer's bid amount
                    -- when (a) the toggle is on, (b) the bid strictly
                    -- exceeds the closing-gap (`barrel_make`), and (c)
                    -- this is the declarer's unit. Defender units fall
                    -- off at the standard rate even under a hero bid.
                    if
                        overshoot_active
                        and is_declarer_unit
                        and is_integer(declarer_bid)
                        and declarer_bid > barrel_make
                    then
                        new_total = threshold - declarer_bid
                        unit_overshoot[u] = true
                    else
                        new_total = fall_off_total
                    end
                    new_entry = off_barrel_entry()
                else
                    new_total = threshold
                    new_entry = {
                        on_barrel = true,
                        mounted_on_deal = before_entry.mounted_on_deal,
                        deals_remaining = deals_remaining,
                    }
                end
            end
        else
            -- Off both barrels. Apply pit-lock-in semantics, then check
            -- for forward / reverse barrel mounts.
            local was_pit_locked = pit_lock_active and (before_entry.pit_locked == true)
            local raw = before_total + delta

            if was_pit_locked then
                if is_declarer_unit and declarer_made_contract then
                    -- Successful declarer contract clears the pit lock.
                    -- Full delta applies; raw new_total resumes normal
                    -- accumulation paths.
                    new_total = raw
                    pit_state = "cleared_this_deal"
                elseif delta < 0 then
                    -- Negative deltas (failed contract penalties) drop
                    -- the unit back below the pit; the lock clears
                    -- naturally.
                    new_total = raw
                    pit_state = "cleared_this_deal"
                else
                    -- Stay capped at pit_score; positive defender
                    -- contributions cannot push past the pit.
                    new_total = pit_score
                    pit_state = "pit_locked"
                end
            else
                new_total = raw
                if pit_lock_active and before_total < pit_score and raw >= pit_score then
                    -- Cross from below: cap at the pit; flag locked.
                    new_total = pit_score
                    pit_state = "pit_locked"
                end
            end

            -- Check forward / reverse barrel mounts against the
            -- (possibly pit-capped) total.
            if new_total >= target then
                new_entry = off_barrel_entry()
            elseif new_total >= threshold then
                new_entry = {
                    on_barrel = true,
                    mounted_on_deal = deal_index,
                    deals_remaining = barrel_deal_count,
                }
                new_total = threshold
            elseif reverse_active and new_total <= reverse_threshold then
                if new_total <= reverse_target then
                    new_total = reverse_target
                    new_entry = off_barrel_entry()
                    unit_eliminated[u] = true
                else
                    new_entry = {
                        on_barrel = false,
                        on_reverse_barrel = true,
                        reverse_mounted_on_deal = deal_index,
                        reverse_deals_remaining = barrel_deal_count,
                    }
                    new_total = reverse_threshold
                end
            else
                new_entry = off_barrel_entry()
            end
        end

        -- Dump truck reset fires last on the settled unit total. Lands
        -- on +555 always (under positive_only / both_signs); lands on
        -- -555 only under both_signs. Resets the running total to 0
        -- and clears any forward / reverse barrel state.
        if dump_truck_mode == "positive_only" or dump_truck_mode == "both_signs" then
            if new_total == 555 then
                new_total = 0
                new_entry = off_barrel_entry()
                unit_dump_truck[u] = true
                pit_state = "not_locked"
            end
        end
        if dump_truck_mode == "both_signs" then
            if new_total == -555 then
                new_total = 0
                new_entry = off_barrel_entry()
                unit_dump_truck[u] = true
                pit_state = "not_locked"
            end
        end

        -- Persist the pit-lock flag onto the new entry. `pit_locked`
        -- only sticks while the unit is off both barrels at exactly
        -- pit_score; mounting either barrel or clearing the lock
        -- removes it.
        if
            pit_state == "pit_locked"
            and not new_entry.on_barrel
            and not new_entry.on_reverse_barrel
        then
            new_entry.pit_locked = true
        end
        unit_pit_state[u] = pit_state

        unit_running[u] = new_total
        unit_barrel[u] = new_entry
    end

    -- Collision rule at the unit level. `last_mounter` is canonical:
    -- only the latest-mounted unit stays. `first_mounter` keeps the
    -- earliest mount. `all_collide_fall_off` knocks every colliding
    -- unit off. Same-deal mount ties break by declarer-wins, then
    -- lowest unit index (preserved for backward compat).
    local on_barrel_units = {}
    for u = 1, unit_count do
        if unit_barrel[u].on_barrel then
            on_barrel_units[#on_barrel_units + 1] = u
        end
    end
    if #on_barrel_units > 1 then
        if collision_rule == "all_collide_fall_off" then
            for _, u in ipairs(on_barrel_units) do
                unit_running[u] = fall_off_total
                unit_barrel[u] = off_barrel_entry()
            end
        else
            local pick = -1
            if collision_rule == "first_mounter" then
                pick = math.huge
            end
            for _, u in ipairs(on_barrel_units) do
                local mod = unit_barrel[u].mounted_on_deal
                if collision_rule == "first_mounter" then
                    if mod < pick then
                        pick = mod
                    end
                else
                    if mod > pick then
                        pick = mod
                    end
                end
            end
            local at_pick = {}
            for _, u in ipairs(on_barrel_units) do
                if unit_barrel[u].mounted_on_deal == pick then
                    at_pick[#at_pick + 1] = u
                end
            end
            local survivor
            for _, u in ipairs(at_pick) do
                if u == declarer_unit then
                    survivor = u
                    break
                end
            end
            if not survivor then
                survivor = at_pick[1]
            end
            for _, u in ipairs(on_barrel_units) do
                if u ~= survivor then
                    unit_running[u] = fall_off_total
                    unit_barrel[u] = off_barrel_entry()
                end
            end
        end
    end

    -- Going-over-target. Under `exact_only`, cap totals strictly above
    -- the effective target at `target − 1` before winner detection so
    -- only an exact landing wins. Caps barrel-resolved totals (which
    -- never exceed `target`) too: target itself stays the canonical
    -- "make the barrel" output and remains a winner.
    local going_over_caps = {}
    if going_over_target == "exact_only" then
        for u = 1, unit_count do
            if unit_running[u] > target then
                going_over_caps[u] = true
                unit_running[u] = target - 1
            end
        end
    end

    -- Winner at unit level. `tiebreaker` selects the resolution rule
    -- when more than one unit reaches the target this deal.
    local winning_unit
    local tiebreaker_continuation_event = false
    local at_or_above = {}
    for u = 1, unit_count do
        if unit_running[u] >= target then
            at_or_above[#at_or_above + 1] = u
        end
    end
    if #at_or_above == 1 then
        winning_unit = at_or_above[1]
    elseif #at_or_above > 1 then
        if tiebreaker == "continuation" then
            -- No winner this deal; cap each at-or-above unit at
            -- `target − 1` so they re-enter the off-barrel state below
            -- the new effective target.
            for _, u in ipairs(at_or_above) do
                unit_running[u] = target - 1
                unit_barrel[u] = off_barrel_entry()
            end
            tiebreaker_continuation_event = true
        elseif tiebreaker == "high_score" then
            -- Highest total wins; ties broken by lowest unit index
            -- (no declarer favouritism).
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
            winning_unit = at_max[1]
        else
            -- declarer_wins (canonical): highest total wins; ties at
            -- the top break for the declarer's unit.
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
    end

    local effective_target_after = target
    if tiebreaker_continuation_event then
        effective_target_after = target + 500
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

    -- Per-seat event arrays surfaced to the session.
    local dump_truck_events = {}
    local pit_lock_in_state_seat = {}
    local overshoot_penalty_applied = {}
    local eliminated_seat = {}
    local going_over_target_capped = {}
    for i = 1, player_count do
        local u = sides and sides[i] or i
        dump_truck_events[i] = unit_dump_truck[u] and true or false
        pit_lock_in_state_seat[i] = unit_pit_state[u]
        overshoot_penalty_applied[i] = unit_overshoot[u] and true or false
        eliminated_seat[i] = unit_eliminated[u] and true or false
        going_over_target_capped[i] = going_over_caps[u] and true or false
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
        -- Phase 3.6 echo arrays.
        dump_truck_events = dump_truck_events,
        pit_lock_in_state = pit_lock_in_state_seat,
        overshoot_penalty_applied = overshoot_penalty_applied,
        eliminated = eliminated_seat,
        going_over_target_capped = going_over_target_capped,
        effective_target_before = target,
        effective_target_after = effective_target_after,
        tiebreaker_continuation_event = tiebreaker_continuation_event,
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
