-- The Thousand trick-taking phase.
--
-- Phase 1.6 of the engine: after the talon pass and the optional post-talon
-- raise, the deal becomes a sequence of tricks. Each player has 8 cards,
-- the declarer leads the first trick, the trick winner leads the next, and
-- the deal ends after exactly 8 tricks.
--
-- The trick layer enforces Thousand's four play-legality rules, each read
-- from `RuleConfig.tricks` so future variants can soften them as data:
--   * must_follow      — when holding the led suit, must play it.
--   * must_beat        — when following, must play a higher card of the led
--                        suit if one is available *and* a higher led-suit
--                        card would actually be currently winning the trick
--                        (i.e. no trump has been played on this trick).
--   * must_trump       — when void in the led suit and trump exists, must
--                        play a trump.
--   * must_overtrump   — when trumping into a trick that already holds a
--                        trump, must play a higher trump if one is held.
-- Any illegal play is rejected with a typed error whose `code` and `rule`
-- fields name the broken constraint.
--
-- Trump itself is owned by the orchestrator, not this module. The marriage
-- layer (`core.marriages`) credits its bonus and announces a new trump suit;
-- the orchestrator forwards that suit via `M.set_trump` between tricks. The
-- rule "trump becomes the marriage suit effective from the *next* trick" is
-- honoured by callers — `set_trump` is rejected while a trick has plays on
-- it, so the trump in effect for any in-flight trick is locked in at lead
-- time.
--
-- Inputs come from the prior phases:
--   * `core.dealing` + `core.talon` produce three 8-card hands once the
--     declarer has finished passing and (optionally) raising the bid.
--   * The orchestrator chooses the leader; in canonical Russian rules this
--     is the declarer.
--
-- API mirrors `core.auction` / `core.talon` / `core.marriages`:
--   * Every public function returns either { ok = true, tricks = <state> }
--     or { ok = false, error = { code, message, ...extra } }.
--   * State is type-tagged via `__metatable` so `is_tricks` recognises it.
--   * Transitions never mutate the input; they return a fresh state.

local rule_config = require("core.rule_config")
local card = require("core.card")

local M = {}

M.SCHEMA_VERSION = 1

local TRICKS_TYPE = "thousand.tricks"

local SUPPORTED_PLAYER_COUNT = 3
local CARDS_PER_HAND_AT_START = 8

local SUITS = { "hearts", "diamonds", "clubs", "spades" }
local SUIT_SET = {}
for _, suit in ipairs(SUITS) do
    SUIT_SET[suit] = true
end

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

local function is_valid_player(value)
    return is_integer(value) and value >= 1 and value <= SUPPORTED_PLAYER_COUNT
end

local function is_card_like(value)
    if type(value) ~= "table" then
        return false
    end
    return type(value.suit) == "string" and type(value.rank) == "string"
end

local function shallow_copy_list(list)
    local copy = {}
    for i = 1, #list do
        copy[i] = list[i]
    end
    return copy
end

local function shallow_copy_hands(hands)
    local copy = {}
    for i = 1, #hands do
        copy[i] = shallow_copy_list(hands[i])
    end
    return copy
end

local function copy_play_list(plays)
    local copy = {}
    for i = 1, #plays do
        copy[i] = { player = plays[i].player, card = plays[i].card }
    end
    return copy
end

local function copy_int_list(list, count)
    local copy = {}
    for i = 1, count do
        copy[i] = list[i] or 0
    end
    return copy
end

local function copy_completed(completed)
    local copy = {}
    for i = 1, #completed do
        local t = completed[i]
        copy[i] = {
            leader = t.leader,
            winner = t.winner,
            captured_points = t.captured_points,
            trump = t.trump,
            led_suit = t.led_suit,
            plays = copy_play_list(t.plays),
        }
    end
    return copy
end

local function copy_history(history)
    local copy = {}
    for i = 1, #history do
        local entry = history[i]
        copy[i] = {
            action = entry.action,
            player = entry.player,
            card = entry.card,
            suit = entry.suit,
            trick_index = entry.trick_index,
            winner = entry.winner,
            captured_points = entry.captured_points,
        }
    end
    return copy
end

local function tag_as_tricks(state)
    return setmetatable(state, { __metatable = TRICKS_TYPE })
end

local function clone_state(state)
    return {
        schema_version = state.schema_version,
        config = state.config,
        trump = state.trump,
        hands = shallow_copy_hands(state.hands),
        current_trick = { plays = copy_play_list(state.current_trick.plays) },
        next_to_play = state.next_to_play,
        tricks_played = state.tricks_played,
        tricks_per_deal = state.tricks_per_deal,
        captured_points = copy_int_list(state.captured_points, SUPPORTED_PLAYER_COUNT),
        tricks_won = copy_int_list(state.tricks_won, SUPPORTED_PLAYER_COUNT),
        completed_tricks = copy_completed(state.completed_tricks),
        status = state.status,
        history = copy_history(state.history),
    }
end

local function append_history(history, entry)
    local copy = copy_history(history)
    copy[#copy + 1] = entry
    return copy
end

local function validate_hands(hands)
    if type(hands) ~= "table" then
        return failure("bad_hands_shape", "hands must be a list of 3 hands", {
            actual = type(hands),
        })
    end
    if #hands ~= SUPPORTED_PLAYER_COUNT then
        return failure(
            "bad_hands_shape",
            "hands must contain exactly 3 player hands",
            { actual = #hands, expected = SUPPORTED_PLAYER_COUNT }
        )
    end
    for i = 1, SUPPORTED_PLAYER_COUNT do
        local hand = hands[i]
        if type(hand) ~= "table" then
            return failure("bad_hands_shape", "each hand must be a list of cards", {
                player = i,
                actual = type(hand),
            })
        end
        if #hand ~= CARDS_PER_HAND_AT_START then
            return failure(
                "bad_hands_shape",
                "each hand must hold 8 cards at the start of trick play",
                { player = i, actual = #hand, expected = CARDS_PER_HAND_AT_START }
            )
        end
        for j = 1, #hand do
            if not is_card_like(hand[j]) then
                return failure("bad_hands_shape", "hand contains a non-card entry", {
                    player = i,
                    index = j,
                })
            end
        end
    end
    return nil
end

function M.new(config, hands, leader)
    if not rule_config.is_rule_config(config) then
        return failure("not_a_rule_config", "tricks.new requires a RuleConfig", {
            actual = type(config),
        })
    end
    if config.players.count ~= SUPPORTED_PLAYER_COUNT then
        return failure(
            "unsupported_player_count",
            "tricks layer currently supports exactly 3 players",
            { actual = config.players.count, expected = SUPPORTED_PLAYER_COUNT }
        )
    end

    local hands_err = validate_hands(hands)
    if hands_err then
        return hands_err
    end

    if not is_valid_player(leader) then
        return failure(
            "bad_leader",
            "leader must be an integer in 1.." .. SUPPORTED_PLAYER_COUNT,
            { actual = leader, player_count = SUPPORTED_PLAYER_COUNT }
        )
    end

    local captured_points = {}
    local tricks_won = {}
    for i = 1, SUPPORTED_PLAYER_COUNT do
        captured_points[i] = 0
        tricks_won[i] = 0
    end

    local state = tag_as_tricks({
        schema_version = M.SCHEMA_VERSION,
        config = config,
        trump = nil,
        hands = shallow_copy_hands(hands),
        current_trick = { plays = {} },
        next_to_play = leader,
        tricks_played = 0,
        tricks_per_deal = CARDS_PER_HAND_AT_START,
        captured_points = captured_points,
        tricks_won = tricks_won,
        completed_tricks = {},
        status = "in_progress",
        history = {},
    })
    return { ok = true, tricks = state }
end

function M.is_tricks(value)
    if type(value) ~= "table" then
        return false
    end
    return getmetatable(value) == TRICKS_TYPE
end

local function ensure_tricks(state)
    if not M.is_tricks(state) then
        return failure("not_a_tricks", "first argument is not a tricks state", {
            actual = type(state),
        })
    end
    return nil
end

local function ensure_status(state, expected, action)
    if state.status ~= expected then
        return failure(
            "wrong_phase",
            action .. " requires status '" .. expected .. "'",
            { status = state.status, expected = expected }
        )
    end
    return nil
end

function M.set_trump(state, suit)
    local err = ensure_tricks(state)
    if err then
        return err
    end
    local phase_err = ensure_status(state, "in_progress", "set_trump")
    if phase_err then
        return phase_err
    end
    if #state.current_trick.plays ~= 0 then
        return failure(
            "trick_in_progress",
            "trump can only change between tricks, before the lead",
            { plays = #state.current_trick.plays }
        )
    end
    if suit ~= nil then
        if type(suit) ~= "string" or not SUIT_SET[suit] then
            return failure(
                "bad_suit",
                "suit must be nil or one of the four standard suits",
                { actual = suit }
            )
        end
    end

    local next_state = clone_state(state)
    next_state.trump = suit
    next_state.history = append_history(state.history, {
        action = "set_trump",
        suit = suit,
    })
    return { ok = true, tricks = tag_as_tricks(next_state) }
end

local function find_card_index(hand, target)
    for i = 1, #hand do
        local c = hand[i]
        if c.suit == target.suit and c.rank == target.rank then
            return i
        end
    end
    return nil
end

local function player_holds_suit(hand, suit)
    if not suit then
        return false
    end
    for i = 1, #hand do
        if hand[i].suit == suit then
            return true
        end
    end
    return false
end

local function highest_rank_in_suit(hand, suit, config)
    local best = 0
    for i = 1, #hand do
        local c = hand[i]
        if c.suit == suit then
            local r = card.trick_rank(c, config)
            if r > best then
                best = r
            end
        end
    end
    return best
end

local function highest_rank_played_in_suit(plays, suit, config)
    local best = 0
    for i = 1, #plays do
        local c = plays[i].card
        if c.suit == suit then
            local r = card.trick_rank(c, config)
            if r > best then
                best = r
            end
        end
    end
    return best
end

-- Compute (required_suit, must_beat_threshold) given the current trick state
-- and the player's hand. `required_suit` is nil when the player may discard
-- freely. `must_beat_threshold` is the rank a played card must strictly
-- exceed; a value of 0 means there is no beat constraint.
local function play_constraints(hand, plays, trump, rules, config)
    if #plays == 0 then
        return nil, 0
    end

    local led_suit = plays[1].card.suit
    local has_led = player_holds_suit(hand, led_suit)
    local has_trump = player_holds_suit(hand, trump)

    if has_led and rules.must_follow then
        local threshold = 0
        if rules.must_beat then
            local trump_on_trick = trump and highest_rank_played_in_suit(plays, trump, config) or 0
            if trump_on_trick == 0 then
                threshold = highest_rank_played_in_suit(plays, led_suit, config)
            end
        end
        return led_suit, threshold
    end

    if (not has_led) and trump and has_trump and rules.must_trump then
        local threshold = 0
        if rules.must_overtrump then
            threshold = highest_rank_played_in_suit(plays, trump, config)
        end
        return trump, threshold
    end

    return nil, 0
end

local function compute_legal_cards(state, player)
    local hand = state.hands[player]
    if #state.current_trick.plays == 0 then
        return shallow_copy_list(hand)
    end

    local config = state.config
    local rules = config.tricks
    local trump = state.trump
    local required_suit, threshold =
        play_constraints(hand, state.current_trick.plays, trump, rules, config)

    if required_suit == nil then
        return shallow_copy_list(hand)
    end

    local in_suit = {}
    for i = 1, #hand do
        if hand[i].suit == required_suit then
            in_suit[#in_suit + 1] = hand[i]
        end
    end

    if threshold == 0 then
        return in_suit
    end

    if highest_rank_in_suit(hand, required_suit, config) <= threshold then
        return in_suit
    end

    local higher = {}
    for i = 1, #in_suit do
        if card.trick_rank(in_suit[i], config) > threshold then
            higher[#higher + 1] = in_suit[i]
        end
    end
    return higher
end

function M.legal_cards(state, player)
    local err = ensure_tricks(state)
    if err then
        return err
    end
    local phase_err = ensure_status(state, "in_progress", "legal_cards")
    if phase_err then
        return phase_err
    end
    if not is_valid_player(player) then
        return failure(
            "bad_player",
            "player must be an integer in 1.." .. SUPPORTED_PLAYER_COUNT,
            { actual = player, player_count = SUPPORTED_PLAYER_COUNT }
        )
    end
    return { ok = true, cards = compute_legal_cards(state, player) }
end

local function score_play(c, led_suit, trump, config)
    if trump and c.suit == trump then
        return 100 + card.trick_rank(c, config)
    end
    if c.suit == led_suit then
        return card.trick_rank(c, config)
    end
    return 0
end

local function resolve_trick(state)
    local plays = state.current_trick.plays
    local led_suit = plays[1].card.suit
    local trump = state.trump

    local winner_idx = 1
    local best_score = score_play(plays[1].card, led_suit, trump, state.config)
    for i = 2, #plays do
        local s = score_play(plays[i].card, led_suit, trump, state.config)
        if s > best_score then
            best_score = s
            winner_idx = i
        end
    end
    local winner = plays[winner_idx].player

    local captured = 0
    for i = 1, #plays do
        captured = captured + card.point_value(plays[i].card, state.config)
    end

    return winner, captured, led_suit
end

local function check_legality(hand, plays, trump, rules, config, played_card)
    if #plays == 0 then
        return nil
    end

    local led_suit = plays[1].card.suit
    local has_led = player_holds_suit(hand, led_suit)
    local has_trump = player_holds_suit(hand, trump)

    if has_led and rules.must_follow and played_card.suit ~= led_suit then
        return failure("must_follow_violation", "must follow the led suit when holding it", {
            rule = "must_follow",
            led_suit = led_suit,
            played_suit = played_card.suit,
        })
    end

    if has_led and rules.must_follow and played_card.suit == led_suit and rules.must_beat then
        local trump_on_trick = trump and highest_rank_played_in_suit(plays, trump, config) or 0
        if trump_on_trick == 0 then
            local cur_high = highest_rank_played_in_suit(plays, led_suit, config)
            local can_beat = highest_rank_in_suit(hand, led_suit, config) > cur_high
            if can_beat and card.trick_rank(played_card, config) <= cur_high then
                return failure(
                    "must_beat_violation",
                    "must play a higher card of the led suit when one is held",
                    {
                        rule = "must_beat",
                        led_suit = led_suit,
                        played_rank = played_card.rank,
                        current_high_rank = cur_high,
                    }
                )
            end
        end
    end

    if (not has_led) and trump and has_trump and rules.must_trump and played_card.suit ~= trump then
        return failure(
            "must_trump_violation",
            "must play trump when void in the led suit and holding trump",
            {
                rule = "must_trump",
                trump = trump,
                played_suit = played_card.suit,
            }
        )
    end

    if
        not has_led
        and trump
        and has_trump
        and rules.must_trump
        and played_card.suit == trump
        and rules.must_overtrump
    then
        local cur_high = highest_rank_played_in_suit(plays, trump, config)
        if cur_high > 0 then
            local can_over = highest_rank_in_suit(hand, trump, config) > cur_high
            if can_over and card.trick_rank(played_card, config) <= cur_high then
                return failure(
                    "must_overtrump_violation",
                    "must play a higher trump than any already on the trick when held",
                    {
                        rule = "must_overtrump",
                        trump = trump,
                        played_rank = played_card.rank,
                        current_high_rank = cur_high,
                    }
                )
            end
        end
    end

    return nil
end

function M.play(state, player, played)
    local err = ensure_tricks(state)
    if err then
        return err
    end
    local phase_err = ensure_status(state, "in_progress", "play")
    if phase_err then
        return phase_err
    end
    if not is_valid_player(player) then
        return failure(
            "bad_player",
            "player must be an integer in 1.." .. SUPPORTED_PLAYER_COUNT,
            { actual = player, player_count = SUPPORTED_PLAYER_COUNT }
        )
    end
    if player ~= state.next_to_play then
        return failure(
            "not_your_turn",
            "it is not this player's turn to play",
            { player = player, turn = state.next_to_play }
        )
    end
    if not is_card_like(played) then
        return failure("card_not_in_hand", "card argument is not a card", {
            actual = type(played),
        })
    end

    local hand = state.hands[player]
    local idx = find_card_index(hand, played)
    if idx == nil then
        return failure("card_not_in_hand", "card is not in the player's hand", {
            suit = played.suit,
            rank = played.rank,
        })
    end

    local actual_card = hand[idx]
    local legality_err = check_legality(
        hand,
        state.current_trick.plays,
        state.trump,
        state.config.tricks,
        state.config,
        actual_card
    )
    if legality_err then
        return legality_err
    end

    local next_state = clone_state(state)
    table.remove(next_state.hands[player], idx)
    next_state.current_trick.plays[#next_state.current_trick.plays + 1] = {
        player = player,
        card = actual_card,
    }
    next_state.history = append_history(state.history, {
        action = "play",
        player = player,
        card = actual_card,
    })

    if #next_state.current_trick.plays < SUPPORTED_PLAYER_COUNT then
        next_state.next_to_play = (player % SUPPORTED_PLAYER_COUNT) + 1
        return { ok = true, tricks = tag_as_tricks(next_state) }
    end

    local winner, captured, led_suit = resolve_trick(next_state)
    next_state.captured_points[winner] = next_state.captured_points[winner] + captured
    next_state.tricks_won[winner] = next_state.tricks_won[winner] + 1
    next_state.completed_tricks[#next_state.completed_tricks + 1] = {
        leader = next_state.current_trick.plays[1].player,
        winner = winner,
        captured_points = captured,
        trump = next_state.trump,
        led_suit = led_suit,
        plays = copy_play_list(next_state.current_trick.plays),
    }
    next_state.tricks_played = next_state.tricks_played + 1
    next_state.history = append_history(next_state.history, {
        action = "trick_resolved",
        trick_index = next_state.tricks_played,
        winner = winner,
        captured_points = captured,
    })
    next_state.current_trick = { plays = {} }

    if next_state.tricks_played >= next_state.tricks_per_deal then
        next_state.status = "done"
        next_state.next_to_play = nil
    else
        next_state.next_to_play = winner
    end

    return { ok = true, tricks = tag_as_tricks(next_state) }
end

return M
