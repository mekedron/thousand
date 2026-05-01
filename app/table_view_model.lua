-- Layer 2 presenter that flattens a Session into a frame-shaped table the
-- table scene can draw without ever touching engine vocabulary.
--
-- The motivation is firewall-style: if the renderer reaches into
-- auction.current_leader / tricks.next_to_play / marriages.trump directly,
-- a future engine refactor ripples into the rendering layer. By going
-- through this view-model the engine vocabulary stays in core/ and app/,
-- and tests for the table scene can build a hand-rolled view-model with
-- no engine objects at all.
--
-- The view-model is widened additively as the scene needs more state
-- (auction panel inputs, talon sub-phases, in-flight tricks, marriage
-- offers, deal-done banners). Existing fields are never removed —
-- removing one is a deliberate change in the table scene first.
--
-- Pure Lua, no love.* — same layer as app/i18n.lua and app/session.lua.

local M = {}

-- Display sort order: keep suits in the canonical order the rules doc
-- uses (spades, clubs, diamonds, hearts) and rank cards low-to-high by
-- their trick rank so the player's hand reads left-to-right like a
-- bridge fan. The renderer relies on this order for hover and focus
-- indices to match what the player sees.
local SUIT_DISPLAY_ORDER = {
    spades = 1, -- i18n-ok
    clubs = 2, -- i18n-ok
    diamonds = 3, -- i18n-ok
    hearts = 4, -- i18n-ok
}
local RANK_DISPLAY_ORDER = {
    ["9"] = 1, -- i18n-ok
    ["J"] = 2, -- i18n-ok
    ["Q"] = 3, -- i18n-ok
    ["K"] = 4, -- i18n-ok
    ["10"] = 5, -- i18n-ok
    ["A"] = 6, -- i18n-ok
}

local function copy_list(list)
    local copy = {}
    for i = 1, #list do
        copy[i] = list[i]
    end
    return copy
end

local function sort_cards_for_display(cards)
    local copy = copy_list(cards)
    table.sort(copy, function(a, b)
        local sa = SUIT_DISPLAY_ORDER[a.suit] or 99
        local sb = SUIT_DISPLAY_ORDER[b.suit] or 99
        if sa ~= sb then
            return sa < sb
        end
        return (RANK_DISPLAY_ORDER[a.rank] or 99) < (RANK_DISPLAY_ORDER[b.rank] or 99)
    end)
    return copy
end

local function legal_card_set(session)
    if session:current_phase() ~= "tricks" then
        return nil
    end
    local turn = session:current_turn()
    if not turn then
        return nil
    end
    local list = session:legal_cards(turn)
    local set = {}
    for _, c in ipairs(list) do
        set[c.suit .. ":" .. c.rank] = true -- i18n-ok
    end
    return set
end

local function card_is_legal(card, legal_set)
    if not legal_set then
        return true
    end
    return legal_set[card.suit .. ":" .. card.rank] == true -- i18n-ok
end

-- Compute the catalogue of legal opening / next bids the auction panel
-- can render as buttons. Reads the bid increments + ceiling out of
-- RuleConfig so future templates pick up the right values for free.
local function compute_allowed_bids(config, current_bid)
    local bidding = config.bidding
    local result = {}
    local start
    if current_bid == nil then
        start = bidding.opening_min
    else
        local step
        if current_bid + 1 < 200 then
            step = bidding.increment_below_200
        else
            step = bidding.increment_from_200
        end
        start = current_bid + step
    end
    local amount = start
    while amount <= bidding.pre_talon_max do
        result[#result + 1] = amount
        local step
        if amount < 200 then
            step = bidding.increment_below_200
        else
            step = bidding.increment_from_200
        end
        amount = amount + step
    end
    return result
end

-- Same idea for the post-talon raise panel. The pre-talon ceiling
-- doesn't apply once the talon has been revealed — the engine accepts
-- any amount strictly higher than the current bid that respects the
-- increment rule. We cap at a sensible upper bound (300) so the panel
-- doesn't grow unbounded; the player can always re-bid after the
-- ceiling shifts in a future iteration of this UI.
local POST_TALON_RAISE_CAP = 300
local function compute_allowed_raises(config, current_bid)
    local bidding = config.bidding
    local result = {}
    local amount = current_bid
    while amount < POST_TALON_RAISE_CAP do
        local step
        if amount < 200 then
            step = bidding.increment_below_200
        else
            step = bidding.increment_from_200
        end
        amount = amount + step
        if amount > POST_TALON_RAISE_CAP then
            break
        end
        result[#result + 1] = amount
    end
    return result
end

local function build_auction_block(session)
    if session:current_phase() ~= "auction" then
        return nil
    end
    local auction = session._auction
    if not auction or auction.status ~= "in_progress" then
        return nil
    end
    local history_copy = {}
    for i = 1, #auction.history do
        local entry = auction.history[i]
        history_copy[i] = {
            player = entry.player,
            action = entry.action,
            amount = entry.amount,
        }
    end
    return {
        history = history_copy,
        current_bid = auction.current_bid,
        leader = auction.current_leader,
        on_turn = auction.turn,
        can_pass = true,
        allowed_bid_amounts = compute_allowed_bids(session:config(), auction.current_bid),
    }
end

local function build_talon_phase_block(session)
    if session:current_phase() ~= "talon" then
        return nil
    end
    local talon = session._talon
    if not talon then
        return nil
    end
    local pass_target_seat
    if talon.status == "awaiting_pass" then
        local declarer = talon.declarer
        for seat = 1, session:config().players.count do
            if seat ~= declarer and not talon.passes_received[seat] then
                pass_target_seat = seat
                break
            end
        end
    end
    local allowed_raise_amounts
    if talon.status == "awaiting_raise" then
        allowed_raise_amounts = compute_allowed_raises(session:config(), talon.final_bid)
    end
    return {
        status = talon.status,
        declarer = talon.declarer,
        pass_target_seat = pass_target_seat,
        allowed_raise_amounts = allowed_raise_amounts,
    }
end

local function build_current_trick_block(session)
    if session:current_phase() ~= "tricks" then
        return nil
    end
    return session:current_trick()
end

local function build_marriage_offer_block(session)
    if session:current_phase() ~= "tricks" then
        return nil
    end
    local turn = session:current_turn()
    if not turn then
        return nil
    end
    local suits = session:available_marriages(turn)
    if #suits == 0 then
        return nil
    end
    return { suits = copy_list(suits) }
end

local function build_deal_done_block(session)
    local payload = session:deal_done()
    if not payload then
        return nil
    end
    local block = {
        reason = payload.reason,
        running_totals = copy_list(session:running_totals()),
    }
    if payload.declarer ~= nil then
        block.declarer = payload.declarer
    end
    if payload.made_contract ~= nil then
        block.made_contract = payload.made_contract
    end
    if payload.deal_scores then
        block.deal_scores = copy_list(payload.deal_scores)
    end
    return block
end

-- Build a frame-shaped view-model from a Session. The output shape is the
-- contract the renderer relies on; widening it is fine, removing fields
-- needs a deliberate change in the table scene first.
function M.from_session(session)
    assert(session, "table_view_model.from_session: session is required")

    local config = session:config()
    local player_count = config.players.count
    local turn = session:current_turn()
    local dealer = session:dealer()
    local winner = session:winner()
    local final = session:final_scores()
    local running = session:running_totals()
    local barrel = session:barrel_state()

    local legal_set = legal_card_set(session)
    local hands_in = session:hands()
    local hands = {}
    for i = 1, player_count do
        local raw_cards = hands_in[i] or {}
        local is_turn = (i == turn)
        local is_self = is_turn or (turn == nil and i == 1)
        -- Hand cards are sorted by (suit, trick rank) for the active
        -- player so the displayed order matches the player's expected
        -- read; opponents are face-down stacks so card order doesn't
        -- matter for them — we keep the engine's order as-is.
        local visible_cards
        if is_self then
            visible_cards = sort_cards_for_display(raw_cards)
        else
            visible_cards = copy_list(raw_cards)
        end
        local card_legality = {}
        if is_self and legal_set then
            for j, c in ipairs(visible_cards) do
                card_legality[j] = card_is_legal(c, legal_set)
            end
        end
        hands[i] = {
            player = i,
            -- The active seat's hand is rendered face-up so the player
            -- can see and pick. Other seats render face-down — the
            -- privacy hand-off task layers a between-turns overlay on
            -- top of this without changing the rule. Pre-tricks (no
            -- turn yet, or game over) the seat-1 fallback keeps the
            -- table from being entirely face-down. The "self"/"other"
            -- enum below is internal, not user-visible.
            perspective = is_self and "self" or "other", -- i18n-ok
            cards = visible_cards,
            count = #visible_cards,
            card_legality = card_legality,
            is_dealer = (i == dealer),
            is_turn = is_turn,
        }
    end

    local talon_cards = session:talon_cards() or {}
    local talon = {
        face_down = session:talon_face_down(),
        cards = copy_list(talon_cards),
        count = #talon_cards,
    }

    local scoreboard = {}
    for i = 1, player_count do
        scoreboard[i] = {
            player = i,
            total = running[i] or 0,
            barrel = {
                on_barrel = barrel[i] and barrel[i].on_barrel or false,
                deals_remaining = barrel[i] and barrel[i].deals_remaining or nil,
            },
            is_dealer = (i == dealer),
            is_turn = (i == turn),
            is_winner = (winner ~= nil and i == winner),
        }
    end

    return {
        phase = session:current_phase(),
        turn_player = turn,
        dealer = dealer,
        current_bid = session:current_bid(),
        leader = session:current_leader(),
        trump = session:trump(),
        scoreboard = scoreboard,
        hands = hands,
        talon = talon,
        winner = winner,
        final_scores = final and copy_list(final) or nil,
        player_count = player_count,
        auction = build_auction_block(session),
        talon_phase = build_talon_phase_block(session),
        current_trick = build_current_trick_block(session),
        marriage_offer = build_marriage_offer_block(session),
        deal_done = build_deal_done_block(session),
    }
end

return M
