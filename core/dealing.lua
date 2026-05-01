-- The Thousand dealer.
--
-- Given a 24-card deck (already shuffled by the caller — we want `deal` to
-- be pure and reproducible) and a `RuleConfig`, returns hands sized for the
-- active layout, the talon (where one exists), and an optional draw stock
-- for the 2-player closed-talon variant.
--
-- Phase 3.6 generalises the dealer beyond the canonical 3-player Russian
-- shape. The schedule is selected from a small lookup keyed on
-- `(players.count, talon.size, players.four_player_config,
-- players.two_player_config)`:
--
--   * 3-player / talon 3 — canonical Russian / Ukrainian. Pattern:
--       3+3+3 to players, 2 to talon, 2+2+2 to players, 1 to talon,
--       2+2+2 to players. Hands 7/7/7, talon 3.
--   * 4-player / talon 0 (`dealer_plays_no_talon`) — Configuration A.
--       6+6+6+6 to players, no talon. Six tricks per deal.
--   * 4-player / talon 3 (`dealer_sits_out`) — Configuration B.
--       The three non-dealer seats run the 3-player canonical schedule;
--       the dealer's hand stays empty for the deal. Hands 7/7/7 + empty,
--       talon 3.
--   * 2-player / talon 3 (`fixed_deal_no_draw`) — Variant B.
--       7+7 to players, 3 to talon. Declarer takes the talon, passes one
--       card to the opponent and discards one face-down to their captured
--       pile in core.talon, reaching 8/8 before trick play.
--   * 2-player / talon 0 (`closed_talon_draw_stock`) — Variant A.
--       9+9 to players + a 6-card stock; the bottom card of the stock is
--       flipped face-up as the trump indicator. The stock is consumed
--       during tricks (see core.tricks), not by core.talon.
--   * 3-player / talon 2 — Polish Tysiąc. Pattern:
--       3+3+3 to players, 2 to talon, 2+2+2 to players, 2+2+2 to players,
--       1 to the post-pass declarer pickup (`leftover_for_declarer`).
--       Hands 7/7/7, talon 2, leftover 1. core.talon's
--       `pass_without_taking` flow drains the talon to the two
--       opponents (one card each) and routes the leftover to the
--       declarer at the same moment, leaving 8/8/8 for trick play.
--
-- The returned hands and talon (and stock, when present) are plain Lua
-- lists. Hands evolve through play (cards leave them as tricks resolve),
-- so it is the calling layer's job to manage immutability via
-- update-and-replace rather than the engine locking the lists down. The
-- input deck is never mutated.

local card = require("core.card")
local rule_config = require("core.rule_config")

local M = {}

local EXPECTED_DECK_SIZE = 24

local SUIT_SET = {}
for _, suit in ipairs(card.SUITS) do
    SUIT_SET[suit] = true
end

local RANK_SET = {}
for _, rank in ipairs(card.RANKS) do
    RANK_SET[rank] = true
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

local function is_card_like(value)
    if type(value) ~= "table" then
        return false
    end
    if type(value.suit) ~= "string" or type(value.rank) ~= "string" then
        return false
    end
    return SUIT_SET[value.suit] == true and RANK_SET[value.rank] == true
end

local function validate_deck(deck)
    if type(deck) ~= "table" then
        return failure("wrong_deck_size", "deck must be a list of 24 cards", {
            actual = type(deck),
            expected = EXPECTED_DECK_SIZE,
        })
    end
    if #deck ~= EXPECTED_DECK_SIZE then
        return failure("wrong_deck_size", "deck must contain exactly 24 cards", {
            actual = #deck,
            expected = EXPECTED_DECK_SIZE,
        })
    end
    local seen = {}
    for i = 1, EXPECTED_DECK_SIZE do
        local c = deck[i]
        if not is_card_like(c) then
            return failure("not_a_card", "deck contains a non-card entry", { index = i })
        end
        local key = c.suit .. ":" .. c.rank
        if seen[key] then
            return failure("duplicate_card", "deck contains a duplicate card", {
                suit = c.suit,
                rank = c.rank,
                index = i,
            })
        end
        seen[key] = true
    end
    return nil
end

-- Resolve the deal recipe for the given config. Returns either
--   { ok = true, recipe = { schedule, hand_size, talon_size, stock_size,
--                           active_seats, sits_out } }
-- or a typed failure for shapes the dealer does not yet support.
--
-- `active_seats` is the ordered list of seats the schedule cycles
-- through; `sits_out` is the seat (if any) that stays at zero cards
-- because they are dealing and the variant excludes them. Both depend
-- on `dealer` so the caller passes it in via `opts`.
local function resolve_recipe(config, dealer)
    local count = config.players.count
    local talon_size = config.talon.size

    local function active_seats_skipping(skip)
        local list = {}
        local seat = (skip % count) + 1
        for _ = 1, count - 1 do
            list[#list + 1] = seat
            seat = (seat % count) + 1
        end
        return list
    end

    local function active_seats_all()
        local list = {}
        for i = 1, count do
            list[i] = i
        end
        return list
    end

    if count == 3 and talon_size == 3 then
        return {
            ok = true,
            recipe = {
                schedule = {
                    { to = "player", size = 3 },
                    { to = "player", size = 3 },
                    { to = "player", size = 3 },
                    { to = "talon", size = 2 },
                    { to = "player", size = 2 },
                    { to = "player", size = 2 },
                    { to = "player", size = 2 },
                    { to = "talon", size = 1 },
                    { to = "player", size = 2 },
                    { to = "player", size = 2 },
                    { to = "player", size = 2 },
                },
                hand_size = 7,
                talon_size = 3,
                stock_size = 0,
                active_seats = active_seats_all(),
                sits_out = nil,
            },
        }
    end

    if count == 4 and talon_size == 0 then
        if config.players.four_player_config ~= "dealer_plays_no_talon" then
            return failure(
                "unsupported_four_player_config",
                "4-player no-talon dealing requires four_player_config = 'dealer_plays_no_talon'",
                { four_player_config = config.players.four_player_config }
            )
        end
        return {
            ok = true,
            recipe = {
                schedule = {
                    { to = "player", size = 3 },
                    { to = "player", size = 3 },
                    { to = "player", size = 3 },
                    { to = "player", size = 3 },
                    { to = "player", size = 3 },
                    { to = "player", size = 3 },
                    { to = "player", size = 3 },
                    { to = "player", size = 3 },
                },
                hand_size = 6,
                talon_size = 0,
                stock_size = 0,
                active_seats = active_seats_all(),
                sits_out = nil,
            },
        }
    end

    if count == 4 and talon_size == 3 then
        if config.players.four_player_config ~= "dealer_sits_out" then
            return failure(
                "unsupported_four_player_config",
                "4-player 3-card-talon dealing requires four_player_config = 'dealer_sits_out'",
                { four_player_config = config.players.four_player_config }
            )
        end
        return {
            ok = true,
            recipe = {
                schedule = {
                    { to = "player", size = 3 },
                    { to = "player", size = 3 },
                    { to = "player", size = 3 },
                    { to = "talon", size = 2 },
                    { to = "player", size = 2 },
                    { to = "player", size = 2 },
                    { to = "player", size = 2 },
                    { to = "talon", size = 1 },
                    { to = "player", size = 2 },
                    { to = "player", size = 2 },
                    { to = "player", size = 2 },
                },
                hand_size = 7,
                talon_size = 3,
                stock_size = 0,
                active_seats = active_seats_skipping(dealer),
                sits_out = dealer,
            },
        }
    end

    if count == 2 and talon_size == 3 then
        if config.players.two_player_config ~= "fixed_deal_no_draw" then
            return failure(
                "unsupported_two_player_config",
                "2-player 3-card-talon dealing requires two_player_config = 'fixed_deal_no_draw'",
                { two_player_config = config.players.two_player_config }
            )
        end
        return {
            ok = true,
            recipe = {
                schedule = {
                    { to = "player", size = 3 },
                    { to = "player", size = 3 },
                    { to = "talon", size = 2 },
                    { to = "player", size = 2 },
                    { to = "player", size = 2 },
                    { to = "talon", size = 1 },
                    { to = "player", size = 2 },
                    { to = "player", size = 2 },
                },
                hand_size = 7,
                talon_size = 3,
                stock_size = 0,
                active_seats = active_seats_all(),
                sits_out = nil,
            },
        }
    end

    if count == 2 and talon_size == 0 then
        if config.players.two_player_config ~= "closed_talon_draw_stock" then
            return failure(
                "unsupported_two_player_config",
                "2-player no-talon dealing requires two_player_config = 'closed_talon_draw_stock'",
                { two_player_config = config.players.two_player_config }
            )
        end
        return {
            ok = true,
            recipe = {
                schedule = {
                    { to = "player", size = 3 },
                    { to = "player", size = 3 },
                    { to = "player", size = 3 },
                    { to = "player", size = 3 },
                    { to = "player", size = 3 },
                    { to = "player", size = 3 },
                    { to = "stock", size = 6 },
                },
                hand_size = 9,
                talon_size = 0,
                stock_size = 6,
                active_seats = active_seats_all(),
                sits_out = nil,
            },
        }
    end

    if count == 3 and talon_size == 2 then
        -- Polish Tysiąc 2-card musik: 7-card hands, 2-card talon, plus
        -- a single "leftover" card the talon module hands to the
        -- declarer when the Polish pass-without-taking flow completes.
        -- Each player ends at 8 (7 dealt + 1 from talon for opponents,
        -- 7 dealt + 1 from leftover for declarer) so the trick layer
        -- sees a symmetric 8/8/8 layout. The companion
        -- `talon.distribution = "pass_without_taking"` (see core.talon)
        -- enforces the no-take, no-raise flow.
        return {
            ok = true,
            recipe = {
                schedule = {
                    { to = "player", size = 3 },
                    { to = "player", size = 3 },
                    { to = "player", size = 3 },
                    { to = "talon", size = 2 },
                    { to = "player", size = 2 },
                    { to = "player", size = 2 },
                    { to = "player", size = 2 },
                    { to = "player", size = 2 },
                    { to = "player", size = 2 },
                    { to = "player", size = 2 },
                    { to = "leftover_for_declarer", size = 1 },
                },
                hand_size = 7,
                talon_size = 2,
                stock_size = 0,
                leftover_for_declarer_size = 1,
                active_seats = active_seats_all(),
                sits_out = nil,
            },
        }
    end

    -- Catch-alls for unsupported player_count / talon.size combinations.
    if talon_size ~= 0 and talon_size ~= 2 and talon_size ~= 3 then
        return failure(
            "unsupported_talon_size",
            "dealer supports only 0-, 2- and 3-card talons in the active layout",
            { talon_size = talon_size, player_count = count }
        )
    end
    return failure(
        "unsupported_player_count",
        "dealer does not yet support this player_count / talon.size combination",
        { player_count = count, talon_size = talon_size }
    )
end

function M.deal(deck, config, opts)
    if not rule_config.is_rule_config(config) then
        return failure("not_a_rule_config", "deal requires a RuleConfig", {
            actual = type(config),
        })
    end

    opts = opts or {}
    local dealer = opts.dealer or 1
    local count = config.players.count
    if type(dealer) ~= "number" or dealer ~= math.floor(dealer) or dealer < 1 or dealer > count then
        return failure("bad_dealer_position", "dealer must be an integer in 1.." .. count, {
            actual = dealer,
            player_count = count,
        })
    end

    local recipe_result = resolve_recipe(config, dealer)
    if not recipe_result.ok then
        return recipe_result
    end
    local recipe = recipe_result.recipe

    local deck_error = validate_deck(deck)
    if deck_error then
        return deck_error
    end

    local hands = {}
    for i = 1, count do
        hands[i] = {}
    end
    local talon = {}
    local stock = {}
    local leftover_for_declarer = {}

    local idx = 1
    local cursor = 1
    local active = recipe.active_seats
    for _, chunk in ipairs(recipe.schedule) do
        if chunk.to == "player" then
            local seat = active[cursor]
            local hand = hands[seat]
            for _ = 1, chunk.size do
                hand[#hand + 1] = deck[idx]
                idx = idx + 1
            end
            cursor = (cursor % #active) + 1
        elseif chunk.to == "talon" then
            for _ = 1, chunk.size do
                talon[#talon + 1] = deck[idx]
                idx = idx + 1
            end
        elseif chunk.to == "stock" then
            for _ = 1, chunk.size do
                stock[#stock + 1] = deck[idx]
                idx = idx + 1
            end
        elseif chunk.to == "leftover_for_declarer" then
            for _ = 1, chunk.size do
                leftover_for_declarer[#leftover_for_declarer + 1] = deck[idx]
                idx = idx + 1
            end
        end
    end

    local result = {
        ok = true,
        hands = hands,
        talon = talon,
        sits_out = recipe.sits_out,
        hand_size = recipe.hand_size,
    }
    if recipe.stock_size > 0 then
        result.stock = stock
        -- The bottom card of the stock is the trump indicator in
        -- 2-player Variant A. The Schnapsen convention: bottom card is
        -- the last card drawn, exposed face-up from the start of the
        -- deal so both players know the trump suit before bidding.
        result.trump_indicator = stock[#stock]
    end
    if (recipe.leftover_for_declarer_size or 0) > 0 then
        -- Polish Tysiąc reserves one card off-deck during dealing; the
        -- talon module hands it to the declarer at the end of the
        -- pass_without_taking flow so all hands reach 8 for symmetric
        -- trick play. See core/talon.lua's pass_from_talon and
        -- docs/variations/polish.md.
        result.leftover_for_declarer = leftover_for_declarer
    end
    return result
end

return M
