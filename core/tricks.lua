-- The Thousand trick-taking phase.
--
-- Phase 1.6 of the engine. After the talon pass and the optional
-- post-talon raise, the deal becomes a sequence of tricks: each active
-- seat plays one card per trick, the trick winner takes the captured
-- points and leads the next, and the deal ends when the hands are
-- empty.
--
-- The trick layer enforces Thousand's four play-legality rules, each
-- read from `RuleConfig.tricks`:
--   * must_follow      — when holding the led suit, must play it.
--   * must_beat        — when following, must play a higher card of the
--                        led suit if one is available *and* a higher
--                        led-suit card would currently be winning the
--                        trick (i.e. no trump has been played yet).
--   * must_trump       — when void in the led suit and trump exists,
--                        must play a trump.
--   * must_overtrump   — when trumping into a trick that already holds
--                        a trump, must play a higher trump if one is
--                        held.
-- Any illegal play is rejected with a typed error whose `code` and
-- `rule` fields name the broken constraint.
--
-- Phase 3.6 generalises the layer past the canonical 3-player Russian
-- shape:
--
--   * 4-player Configuration A — 4 active seats, 6-card hands, 6
--     tricks per deal, no talon, fixed across-the-table partnerships.
--   * 4-player Configuration B — 3 active seats (the dealer sits out),
--     8-card hands, 8 tricks per deal, standard 3-card-talon flow.
--   * 2-player Variant A (closed talon, draw stock) — 2 active seats,
--     9-card hands at deal start, 6-card stock with the bottom card
--     exposed as the trump indicator. After each trick during the
--     "draw" phase the winner and then the loser each draw one card
--     from the stock; once the stock is exhausted the phase snaps to
--     "strict" and the must-follow / must-beat / must-trump rules
--     start to bite. 12 tricks per deal total (3 draw + 9 strict).
--   * 2-player Variant B — 2 active seats, 8-card hands after
--     declarer's pass-and-discard, 8 tricks per deal.
--
-- Trump itself is owned by the orchestrator. The marriage layer
-- (`core.marriages`) credits its bonus and announces a new trump suit;
-- the orchestrator forwards that suit via `M.set_trump` between tricks.
-- 2-player Variant A's stock-bottom trump is set on construction via
-- `opts.trump`.
--
-- Inputs come from the prior phases:
--   * `core.dealing` produces hands sized for the layout (and a stock
--     for 2-player Variant A).
--   * `core.talon` (when present) finishes the take/pass/discard flow
--     and the orchestrator chooses the leader (canonical Russian =
--     declarer leads; future variants will read this from RuleConfig).
--
-- API mirrors `core.auction` / `core.talon` / `core.marriages`:
--   * Every public function returns either { ok = true, tricks = <state> }
--     or { ok = false, error = { code, message, ...extra } }.
--   * State is type-tagged via `__metatable` so `is_tricks` recognises
--     it.
--   * Transitions never mutate the input; they return a fresh state.

local rule_config = require("core.rule_config")
local card = require("core.card")

local M = {}

M.SCHEMA_VERSION = 1

local TRICKS_TYPE = "thousand.tricks"

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
            phase = entry.phase,
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
        captured_points = copy_int_list(state.captured_points, state.player_count),
        tricks_won = copy_int_list(state.tricks_won, state.player_count),
        completed_tricks = copy_completed(state.completed_tricks),
        status = state.status,
        history = copy_history(state.history),
        player_count = state.player_count,
        active_seats = shallow_copy_list(state.active_seats),
        sits_out = state.sits_out,
        partnership_sides = state.partnership_sides and shallow_copy_list(state.partnership_sides)
            or nil,
        stock = shallow_copy_list(state.stock),
        trump_indicator = state.trump_indicator,
        phase = state.phase,
    }
end

local function append_history(history, entry)
    local copy = copy_history(history)
    copy[#copy + 1] = entry
    return copy
end

-- Resolve the layout for the active config: how many cards each active
-- seat starts with, how many tricks the deal lasts, which seats are
-- active, and whether the layout has a draw-stock phase.
local function resolve_layout(config)
    local count = config.players.count
    local talon_size = config.talon.size

    if count == 3 and talon_size == 3 then
        return {
            ok = true,
            hand_size = 8,
            tricks_per_deal = 8,
            sits_out = nil,
            uses_stock = false,
        }
    end
    if count == 3 and talon_size == 2 then
        -- Polish Tysiąc 2-card pass_without_taking. The talon module
        -- routes the dealer's reserved leftover card to the declarer
        -- when the pass closes the talon out, so all three hands reach
        -- 8 by the time tricks start. Standard 8-trick layout from
        -- here on; the only Polish-specific tells are upstream
        -- (dealing recipe + talon distribution), which are invisible
        -- to the trick layer. See docs/variations/polish.md.
        return {
            ok = true,
            hand_size = 8,
            tricks_per_deal = 8,
            sits_out = nil,
            uses_stock = false,
        }
    end
    if count == 4 and talon_size == 0 then
        if config.players.four_player_config ~= "dealer_plays_no_talon" then
            return failure(
                "unsupported_four_player_config",
                "4-player no-talon tricks require four_player_config = 'dealer_plays_no_talon'",
                { four_player_config = config.players.four_player_config }
            )
        end
        return {
            ok = true,
            hand_size = 6,
            tricks_per_deal = 6,
            sits_out = nil,
            uses_stock = false,
        }
    end
    if count == 4 and talon_size == 3 then
        if config.players.four_player_config ~= "dealer_sits_out" then
            return failure(
                "unsupported_four_player_config",
                "4-player 3-card-talon tricks require four_player_config = 'dealer_sits_out'",
                { four_player_config = config.players.four_player_config }
            )
        end
        return {
            ok = true,
            hand_size = 8,
            tricks_per_deal = 8,
            sits_out_from_dealer = true,
            uses_stock = false,
        }
    end
    if count == 2 and talon_size == 3 then
        if config.players.two_player_config ~= "fixed_deal_no_draw" then
            return failure(
                "unsupported_two_player_config",
                "2-player 3-card-talon tricks require two_player_config = 'fixed_deal_no_draw'",
                { two_player_config = config.players.two_player_config }
            )
        end
        return {
            ok = true,
            hand_size = 8,
            tricks_per_deal = 8,
            sits_out = nil,
            uses_stock = false,
        }
    end
    if count == 2 and talon_size == 0 then
        if config.players.two_player_config ~= "closed_talon_draw_stock" then
            return failure(
                "unsupported_two_player_config",
                "2-player no-talon tricks require two_player_config = 'closed_talon_draw_stock'",
                { two_player_config = config.players.two_player_config }
            )
        end
        return {
            ok = true,
            hand_size = 9,
            tricks_per_deal = 12,
            sits_out = nil,
            uses_stock = true,
            stock_size = 6,
        }
    end
    return failure(
        "unsupported_player_count",
        "tricks layer does not yet support this player_count / talon.size combination",
        { player_count = count, talon_size = talon_size }
    )
end

local function active_seats_skipping(skip, count)
    local list = {}
    local seat = (skip % count) + 1
    for _ = 1, count - 1 do
        list[#list + 1] = seat
        seat = (seat % count) + 1
    end
    return list
end

local function active_seats_all(count)
    local list = {}
    for i = 1, count do
        list[i] = i
    end
    return list
end

local function partnership_sides_for(count, partnership_mode)
    if partnership_mode ~= "fixed_across_table" or count ~= 4 then
        return nil
    end
    -- North-South share side 1; East-West share side 2. Seats 1 and 3
    -- sit across each other; seats 2 and 4 sit across each other.
    return { 1, 2, 1, 2 }
end

local function validate_hands(hands, hand_size, count, sits_out)
    if type(hands) ~= "table" then
        return failure("bad_hands_shape", "hands must be a list of " .. count .. " hands", {
            actual = type(hands),
        })
    end
    if #hands ~= count then
        return failure(
            "bad_hands_shape",
            "hands must contain exactly " .. count .. " player hands",
            { actual = #hands, expected = count }
        )
    end
    for i = 1, count do
        local hand = hands[i]
        if type(hand) ~= "table" then
            return failure("bad_hands_shape", "each hand must be a list of cards", {
                player = i,
                actual = type(hand),
            })
        end
        local expected
        if i == sits_out then
            expected = 0
        else
            expected = hand_size
        end
        if #hand ~= expected then
            return failure(
                "bad_hands_shape",
                "each hand must hold the layout's pre-tricks size",
                { player = i, actual = #hand, expected = expected }
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

local function validate_stock(stock, expected_size)
    if expected_size == 0 then
        if stock ~= nil and #stock ~= 0 then
            return failure(
                "bad_stock_shape",
                "stock must be nil or empty when the layout has no stock",
                { actual = #stock, expected = 0 }
            )
        end
        return nil
    end
    if type(stock) ~= "table" then
        return failure(
            "bad_stock_shape",
            "stock must be a list of " .. expected_size .. " cards",
            { actual = type(stock), expected = expected_size }
        )
    end
    if #stock ~= expected_size then
        return failure(
            "bad_stock_shape",
            "stock must contain exactly " .. expected_size .. " cards",
            { actual = #stock, expected = expected_size }
        )
    end
    for i = 1, expected_size do
        if not is_card_like(stock[i]) then
            return failure("bad_stock_shape", "stock contains a non-card entry", {
                index = i,
            })
        end
    end
    return nil
end

function M.new(config, hands, leader, opts)
    if not rule_config.is_rule_config(config) then
        return failure("not_a_rule_config", "tricks.new requires a RuleConfig", {
            actual = type(config),
        })
    end
    opts = opts or {}

    local layout_result = resolve_layout(config)
    if not layout_result.ok then
        return layout_result
    end
    local count = config.players.count
    local sits_out = layout_result.sits_out
    if layout_result.sits_out_from_dealer then
        if not is_integer(opts.dealer) or opts.dealer < 1 or opts.dealer > count then
            return failure(
                "bad_dealer_position",
                "tricks.new requires opts.dealer when the layout has a sitting-out seat",
                { actual = opts.dealer, player_count = count }
            )
        end
        sits_out = opts.dealer
    end

    local hands_err = validate_hands(hands, layout_result.hand_size, count, sits_out)
    if hands_err then
        return hands_err
    end

    if not is_integer(leader) or leader < 1 or leader > count then
        return failure(
            "bad_leader",
            "leader must be an integer in 1.." .. count,
            { actual = leader, player_count = count }
        )
    end
    if leader == sits_out then
        return failure(
            "bad_leader",
            "leader must be an active seat (not the sitting-out seat)",
            { leader = leader, sits_out = sits_out }
        )
    end

    local trump = opts.trump
    if trump ~= nil and (type(trump) ~= "string" or not SUIT_SET[trump]) then
        return failure(
            "bad_suit",
            "opts.trump must be nil or one of the four standard suits",
            { actual = trump }
        )
    end

    local stock = opts.stock
    if layout_result.uses_stock then
        local stock_err = validate_stock(stock, layout_result.stock_size)
        if stock_err then
            return stock_err
        end
        stock = shallow_copy_list(stock)
    else
        if stock ~= nil and #stock ~= 0 then
            return failure(
                "bad_stock_shape",
                "stock must be nil or empty when the layout has no stock",
                { actual = #stock }
            )
        end
        stock = {}
    end

    local trump_indicator = opts.trump_indicator
    if trump_indicator ~= nil and not is_card_like(trump_indicator) then
        return failure(
            "bad_trump_indicator",
            "opts.trump_indicator must be a card or nil",
            { actual = type(trump_indicator) }
        )
    end

    local active_seats
    if sits_out then
        active_seats = active_seats_skipping(sits_out, count)
    else
        active_seats = active_seats_all(count)
    end

    local captured_points = {}
    local tricks_won = {}
    for i = 1, count do
        captured_points[i] = (opts.initial_captured_points and opts.initial_captured_points[i]) or 0
        tricks_won[i] = 0
    end

    local phase = "strict"
    if layout_result.uses_stock then
        phase = "draw"
    end

    local state = tag_as_tricks({
        schema_version = M.SCHEMA_VERSION,
        config = config,
        trump = trump,
        hands = shallow_copy_hands(hands),
        current_trick = { plays = {} },
        next_to_play = leader,
        tricks_played = 0,
        tricks_per_deal = layout_result.tricks_per_deal,
        captured_points = captured_points,
        tricks_won = tricks_won,
        completed_tricks = {},
        status = "in_progress",
        history = {},
        player_count = count,
        active_seats = active_seats,
        sits_out = sits_out,
        partnership_sides = partnership_sides_for(count, config.players.partnership_mode),
        stock = stock,
        trump_indicator = trump_indicator,
        phase = phase,
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

-- Phase 3.6 trump_activation_timing = "immediate" path. Where the
-- standard `set_trump` requires an empty trick (i.e. trump only
-- changes between tricks), this variant lets a marriage flip trump
-- on the very trick the K or Q led. The resolver re-reads
-- `state.trump` per play, so re-ranking is automatic — this entry
-- point only swaps the suit and records the action.
function M.set_trump_in_trick(state, suit)
    local err = ensure_tricks(state)
    if err then
        return err
    end
    local phase_err = ensure_status(state, "in_progress", "set_trump_in_trick")
    if phase_err then
        return phase_err
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
        action = "set_trump_in_trick",
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

-- Compute (required_suit, must_beat_threshold) given the current trick
-- state and the player's hand. `required_suit` is nil when the player
-- may discard freely. During a 2-player A draw phase the must-follow
-- and must-beat rules are relaxed (the player may always discard).
local function play_constraints(hand, plays, trump, rules, config, phase)
    if #plays == 0 then
        return nil, 0
    end
    if phase == "draw" then
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
        play_constraints(hand, state.current_trick.plays, trump, rules, config, state.phase)

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

local function is_active(state, player)
    if state.sits_out and player == state.sits_out then
        return false
    end
    return is_integer(player) and player >= 1 and player <= state.player_count
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
    if not is_active(state, player) then
        return failure(
            "bad_player",
            "player must be an active seat in 1.." .. state.player_count,
            { actual = player, player_count = state.player_count, sits_out = state.sits_out }
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

local function check_legality(hand, plays, trump, rules, config, played_card, phase)
    if #plays == 0 then
        return nil
    end
    if phase == "draw" then
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

local function next_active_seat(active_seats, current)
    for i = 1, #active_seats do
        if active_seats[i] == current then
            return active_seats[(i % #active_seats) + 1]
        end
    end
    error("tricks: current seat not in active_seats — invariant violated")
end

-- After a trick resolves under the draw phase, the winner draws the
-- top of the stock and the loser draws the next top. When the stock
-- empties the phase snaps to "strict".
local function consume_stock(state, winner)
    if state.phase ~= "draw" or #state.stock == 0 then
        return state
    end
    local active = state.active_seats
    local loser
    for _, seat in ipairs(active) do
        if seat ~= winner then
            loser = seat
            break
        end
    end
    if loser == nil then
        return state
    end
    -- Winner draws first, then loser. Each picks the current top of
    -- the stock; the very last card drawn (when stock has only the
    -- trump indicator left) is the indicator itself, which becomes a
    -- normal card in the loser's hand.
    local top = state.stock[1]
    if top then
        table.remove(state.stock, 1)
        state.hands[winner][#state.hands[winner] + 1] = top
    end
    local next_top = state.stock[1]
    if next_top then
        table.remove(state.stock, 1)
        state.hands[loser][#state.hands[loser] + 1] = next_top
    end
    if #state.stock == 0 then
        state.phase = "strict"
    end
    return state
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
    if not is_active(state, player) then
        return failure(
            "bad_player",
            "player must be an active seat in 1.." .. state.player_count,
            { actual = player, player_count = state.player_count, sits_out = state.sits_out }
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
        actual_card,
        state.phase
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

    if #next_state.current_trick.plays < #next_state.active_seats then
        next_state.next_to_play = next_active_seat(next_state.active_seats, player)
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
        phase = next_state.phase,
    })
    next_state.current_trick = { plays = {} }

    next_state = consume_stock(next_state, winner)

    if next_state.tricks_played >= next_state.tricks_per_deal then
        next_state.status = "done"
        next_state.next_to_play = nil
    else
        next_state.next_to_play = winner
    end

    return { ok = true, tricks = tag_as_tricks(next_state) }
end

-- Map a seat to its partnership side (1 or 2) for `partnership_mode =
-- "fixed_across_table"`. Returns nil for layouts without a partnership.
function M.side_of(state, player)
    if not M.is_tricks(state) then
        return nil
    end
    if not state.partnership_sides then
        return nil
    end
    return state.partnership_sides[player]
end

return M
