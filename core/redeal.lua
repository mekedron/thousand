-- The Thousand redeal entitlement detector.
--
-- Pure-Lua predicates and a single high-level `entitled_offer(hands,
-- config)` function the session calls right after `core.dealing.deal`.
-- The four house-rule entitlements live here so the engine can express
-- "is anyone entitled to a redeal?" in one place rather than scattering
-- the same hand-walking logic across `app.session`, the table view-model
-- and tests.
--
-- All inputs are plain Lua tables. The module touches no Love2D and no
-- session state.
--
-- The "weak hand" definitions follow `docs/variations/house-rules.md`:
--   * strict  — no marriage AND no Ace AND no card above 10. We read
--               "above 10" by face-value ordering (9 < 10 < J < Q < K
--               < A), so a strict-weak hand contains only 9s and 10s.
--   * loose   — no marriage AND no Ace.
--   * counted — sum of card-points strictly below `weak_hand_threshold`.
--
-- The module exports the per-test predicates so tests can probe each
-- branch without going through `entitled_offer`.
--
-- Note for the future Phase 4 bot player layer (`app/bot/`):
-- when a bot seat is entitled to an *optional* redeal (4-nine optional,
-- 4-jack optional, 3-nine optional, weak-hand any non-off mode), the
-- bot must decide whether to accept by calling `Session:accept_redeal`
-- or `Session:decline_redeal`. The session does not auto-decline on
-- the bot's behalf — it sits in the `awaiting_redeal_decision` phase
-- until the seated agent (human via the table-scene modal, or bot via
-- its decision routine) resolves the offer. Mandatory entitlements
-- are auto-applied by `evaluate_entitlement_with_forced_loop` in the
-- session and never need a bot decision. The bot's heuristic for the
-- optional cases (e.g., "decline if you hold the spades marriage,
-- accept otherwise") lives in `app/bot/`, not here — this module's
-- only job is to surface *who* is entitled and *why*.

local card_module = require("core.card")

local M = {}

-- Ranks NOT considered "above 10" in face-value ordering. A strict-weak
-- hand contains only these two ranks.
local FACE_VALUE_AT_OR_BELOW_TEN = {
    ["9"] = true,
    ["10"] = true,
}

local function rank_count(hand, rank)
    local c = 0
    for i = 1, #hand do
        if hand[i].rank == rank then
            c = c + 1
        end
    end
    return c
end

function M.has_four_nines(hand)
    return rank_count(hand, "9") >= 4
end

function M.has_three_nines(hand)
    return rank_count(hand, "9") == 3
end

function M.has_four_jacks(hand)
    return rank_count(hand, "J") >= 4
end

local function has_any_marriage(hand)
    local kings, queens = {}, {}
    for i = 1, #hand do
        local c = hand[i]
        if c.rank == "K" then
            kings[c.suit] = true
        elseif c.rank == "Q" then
            queens[c.suit] = true
        end
    end
    for suit in pairs(kings) do
        if queens[suit] then
            return true
        end
    end
    return false
end

local function has_any_ace(hand)
    for i = 1, #hand do
        if hand[i].rank == "A" then
            return true
        end
    end
    return false
end

local function only_nines_and_tens(hand)
    for i = 1, #hand do
        if not FACE_VALUE_AT_OR_BELOW_TEN[hand[i].rank] then
            return false
        end
    end
    return true
end

local function hand_card_points(hand, config)
    local total = 0
    for i = 1, #hand do
        total = total + card_module.point_value(hand[i], config)
    end
    return total
end

-- mode: "off" | "strict" | "loose" | "counted"
-- threshold: required when mode == "counted" — falls back to nil-safety
--            (returns false) if absent. Tests pass it explicitly.
function M.is_weak_hand(hand, mode, threshold, config)
    if mode == "off" or mode == nil then
        return false
    end
    if mode == "strict" then
        return (not has_any_marriage(hand))
            and (not has_any_ace(hand))
            and only_nines_and_tens(hand)
    end
    if mode == "loose" then
        return (not has_any_marriage(hand)) and (not has_any_ace(hand))
    end
    if mode == "counted" then
        if type(threshold) ~= "number" or type(config) ~= "table" then
            return false
        end
        return hand_card_points(hand, config) < threshold
    end
    return false
end

-- Walk seats 1..count and return the highest-priority redeal entitlement,
-- if any. Mandatory entitlements always beat optional ones — a table
-- that hard-codes "redeal on 4 jacks" should not yield to an optional
-- 4-nine offer the entitled player might decline. Within each tier the
-- existing kind hierarchy holds (4-nine > 4-jack > 3-nine):
--
--   1. four_nine_redeal  == "mandatory" → forced = true,  kind="four_nine"
--   2. four_jack_redeal  == "mandatory" → forced = true,  kind="four_jack"
--   3. three_nine_redeal == "mandatory" → forced = true,  kind="three_nine"
--   4. four_nine_redeal  == "optional"  → forced = false, kind="four_nine"
--   5. four_jack_redeal  == "optional"  → forced = false, kind="four_jack"
--   6. three_nine_redeal == "optional"  → forced = false, kind="three_nine"
--   7. weak_hand_redeal  != "off"       → forced = false, kind="weak_hand"
--
-- Returns nil if no seat is entitled, or
--   { seat = N, kind = "four_nine"|"four_jack"|"three_nine"|"weak_hand",
--     forced = boolean }
function M.entitled_offer(hands, config)
    if type(hands) ~= "table" then
        return nil
    end
    local count = config.players.count

    local d = config.dealing
    local four_nine_mode = d.four_nine_redeal
    local four_jack_mode = d.four_jack_redeal
    local three_nine_mode = d.three_nine_redeal
    local weak_hand_mode = d.weak_hand_redeal
    local weak_hand_threshold = d.weak_hand_threshold

    local function find_seat_with(predicate)
        for seat = 1, count do
            local hand = hands[seat]
            if hand and predicate(hand) then
                return seat
            end
        end
        return nil
    end

    -- Tier 1: every mandatory rule, in kind order.
    if four_nine_mode == "mandatory" then
        local seat = find_seat_with(M.has_four_nines)
        if seat then
            return { seat = seat, kind = "four_nine", forced = true }
        end
    end
    if four_jack_mode == "mandatory" then
        local seat = find_seat_with(M.has_four_jacks)
        if seat then
            return { seat = seat, kind = "four_jack", forced = true }
        end
    end
    if three_nine_mode == "mandatory" then
        local seat = find_seat_with(M.has_three_nines)
        if seat then
            return { seat = seat, kind = "three_nine", forced = true }
        end
    end

    -- Tier 2: every optional rule, in kind order.
    if four_nine_mode == "optional" then
        local seat = find_seat_with(M.has_four_nines)
        if seat then
            return { seat = seat, kind = "four_nine", forced = false }
        end
    end
    if four_jack_mode == "optional" then
        local seat = find_seat_with(M.has_four_jacks)
        if seat then
            return { seat = seat, kind = "four_jack", forced = false }
        end
    end
    if three_nine_mode == "optional" then
        local seat = find_seat_with(M.has_three_nines)
        if seat then
            return { seat = seat, kind = "three_nine", forced = false }
        end
    end

    -- Tier 3: weak hand has no mandatory variant in the rule docs.
    if weak_hand_mode and weak_hand_mode ~= "off" then
        local seat = find_seat_with(function(hand)
            return M.is_weak_hand(hand, weak_hand_mode, weak_hand_threshold, config)
        end)
        if seat then
            return { seat = seat, kind = "weak_hand", forced = false }
        end
    end

    return nil
end

return M
