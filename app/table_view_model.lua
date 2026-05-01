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

-- Display sort order: spades → hearts → clubs → diamonds, alternating
-- the dark/red colour pairs so adjacent suits are visually distinct in
-- a fanned hand. Within each suit, cards run low-to-high by trick rank
-- so the player can read the hand left-to-right. The renderer relies
-- on this order for hover and focus indices to match what the player
-- sees.
local SUIT_DISPLAY_ORDER = {
    spades = 1, -- i18n-ok
    hearts = 2, -- i18n-ok
    clubs = 3, -- i18n-ok
    diamonds = 4, -- i18n-ok
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
    local phase = session:current_phase()
    if phase ~= "tricks" and phase ~= "raspassy_play" then -- i18n-ok: phase enums
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
        if current_bid + 1 < bidding.increment_threshold then
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
        if amount < bidding.increment_threshold then
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
        if amount < bidding.increment_threshold then
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
    local phase = session:current_phase()
    local talon_phase = "talon" -- i18n-ok: phase enum
    local bad_talon_phase = "awaiting_bad_talon_decision" -- i18n-ok: phase enum
    local rebuy_phase = "awaiting_rebuy_decision" -- i18n-ok: phase enum
    if phase ~= talon_phase and phase ~= bad_talon_phase and phase ~= rebuy_phase then
        return nil
    end
    local talon = session._talon
    if not talon then
        return nil
    end
    local pass_target_seat
    if talon.status == "awaiting_pass" then
        local declarer = talon.declarer
        local sits_out = talon.sits_out
        for seat = 1, session:config().players.count do
            if seat ~= declarer and seat ~= sits_out and not talon.passes_received[seat] then
                pass_target_seat = seat
                break
            end
        end
    end
    local allowed_raise_amounts
    if talon.status == "awaiting_raise" then
        allowed_raise_amounts = compute_allowed_raises(session:config(), talon.final_bid)
    end
    -- Phase 3.6 talon-variants: declarer can concede or buy back at the
    -- "revealed" status (before take). Both require the parent toggle
    -- to be on and no bad-talon / rebuy offer pending — those are
    -- prior-in-line decisions that block the declarer's pre-take menu.
    local config = session:config()
    local pre_take = talon.status == "revealed"
        and not session:bad_talon_offer_state()
        and not session:rebuy_offer_state()
    local declarer_can_concede = pre_take and config.talon.pass_the_talon == "on"
    local declarer_can_buyback
    if pre_take and config.talon.buyback == "on" then
        declarer_can_buyback = { penalty = config.talon.buyback_penalty or 0 }
    end
    -- Polish Tysiąc direct-pass affordance: at status "revealed" with
    -- `distribution = "pass_without_taking"` the take button is replaced
    -- by a "Pass talon" affordance. The remaining-opponents list orders
    -- recipients clockwise from the declarer so the scene can render
    -- "Pass to Player X" deterministically.
    local distribution = talon.distribution or "declarer_takes_then_passes"
    local polish_pass_pending = pre_take and distribution == "pass_without_taking"
    local polish_pass_remaining_seats
    if polish_pass_pending then
        polish_pass_remaining_seats = {}
        local count = config.players.count
        local seat = (talon.declarer % count) + 1
        for _ = 1, count - 1 do
            if seat ~= talon.sits_out and not talon.passes_received[seat] then
                polish_pass_remaining_seats[#polish_pass_remaining_seats + 1] = seat
            end
            seat = (seat % count) + 1
        end
    end
    return {
        status = talon.status,
        declarer = talon.declarer,
        pass_target_seat = pass_target_seat,
        allowed_raise_amounts = allowed_raise_amounts,
        requires_discard = talon.requires_discard or false,
        sits_out = talon.sits_out,
        declarer_can_concede = declarer_can_concede,
        declarer_can_buyback = declarer_can_buyback,
        passes_face_up = session:talon_passes_face_up(),
        distribution = distribution,
        polish_pass_pending = polish_pass_pending,
        polish_pass_remaining_seats = polish_pass_remaining_seats,
    }
end

-- The active bad-talon prompt, surfaced while the session is in
-- `awaiting_bad_talon_decision`. Mirrors `redeal_prompt`.
local function build_bad_talon_prompt_block(session)
    local offer = session:bad_talon_offer_state()
    if not offer then
        return nil
    end
    return {
        kind = offer.kind,
        declarer = offer.declarer,
        points = offer.points,
    }
end

-- The active rebuy prompt, surfaced while the session is in
-- `awaiting_rebuy_decision`. Mirrors `bad_talon_prompt`. The `seat` is
-- the head-of-queue defender currently asked to accept or pass; the
-- table scene addresses the modal to that seat.
local function build_rebuy_prompt_block(session)
    local offer = session:rebuy_offer_state()
    if not offer then
        return nil
    end
    return {
        seat = offer.seats[1],
        contract = offer.contract,
        from_declarer = offer.original_declarer,
    }
end

-- Latest buyback log entry, surfaced as a banner. Cleared when the
-- next deal starts via `start_next_deal`.
local function build_buyback_banner_block(session)
    local log = session:buyback_log()
    if not log or #log == 0 then
        return nil
    end
    local entry = log[#log]
    return {
        declarer = entry.declarer,
        dealer = entry.dealer,
        penalty = entry.penalty or 0,
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

-- Phase 3.6: dealing-and-redeal banner blocks. Each block is nil when
-- the corresponding event isn't currently visible to the player; the
-- table scene branches on presence to render or not.

-- The active redeal prompt, surfaced while the session is in
-- `awaiting_redeal_decision`. Forced offers also land here so the scene
-- can show a non-dismissible banner before the auto-redeal fires.
local function build_redeal_prompt_block(session)
    local offer = session:redeal_offer()
    if not offer then
        return nil
    end
    return {
        kind = offer.kind,
        seat = offer.seat,
        forced = offer.forced or false,
    }
end

-- The latest misdeal-event row, taken from `Session:misdeal_log()`.
-- Cleared when the next deal starts (the session resets the log on
-- `start_next_deal`).
local function build_misdeal_banner_block(session)
    local log = session:misdeal_log()
    if not log or #log == 0 then
        return nil
    end
    local entry = log[#log]
    return {
        handling = entry.handling,
        dealer = entry.dealer,
        penalty = entry.penalty or 0,
    }
end

-- The all-pass banner: present when the deal ended on all-pass under
-- one of the three handlings, OR while a raspassy_play deal is in
-- progress. The scene reads `mode` to pick the localised body text.
local function build_all_pass_banner_block(session)
    if session:raspassy_active() then
        return { mode = "raspassy" }
    end
    local payload = session:deal_done()
    if not payload then
        return nil
    end
    if payload.reason == "all_pass" then
        return { mode = "redeal" }
    end
    if payload.reason == "all_pass_pass_out" then
        return { mode = "pass_out" }
    end
    if payload.reason == "raspassy_scored" then
        return { mode = "raspassy" }
    end
    return nil
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
    local sits_out = session:sits_out()
    local sides = session:partnership_sides()

    local legal_set = legal_card_set(session)
    local hands_in = session:hands()
    local hands = {}
    for i = 1, player_count do
        local raw_cards = hands_in[i] or {}
        local is_turn = (i == turn)
        local is_self = is_turn or (turn == nil and i == 1 and i ~= sits_out)
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
            sits_out = (i == sits_out),
            side = sides and sides[i] or nil,
        }
    end

    local talon_cards = session:talon_cards() or {}
    local talon = {
        face_down = session:talon_face_down(),
        cards = copy_list(talon_cards),
        count = #talon_cards,
        -- Phase 3.6: per-seat visibility hint for
        -- `talon.hidden_on_minimum_100`. The UI combines this with
        -- the active viewer seat to decide whether to render the
        -- talon face-down or face-up; the declarer always sees their
        -- own talon. When false (default), the talon visibility
        -- follows `face_down` for everyone.
        hidden_to_defenders = session:talon_hidden_rule_active(),
    }

    local stock_block
    local stock_cards = session:stock()
    if stock_cards and #stock_cards > 0 then
        local trump_indicator = session:trump_indicator()
        stock_block = {
            count = #stock_cards,
            trump_indicator = trump_indicator,
            phase = session:tricks_phase(),
        }
    elseif session:trump_indicator() then
        stock_block = {
            count = 0,
            trump_indicator = session:trump_indicator(),
            phase = session:tricks_phase(),
        }
    end

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
            sits_out = (i == sits_out),
            side = sides and sides[i] or nil,
        }
    end

    local partnership
    if sides then
        local side_totals = { 0, 0 }
        local seen = { false, false }
        for i = 1, player_count do
            local s = sides[i]
            if not seen[s] then
                side_totals[s] = running[i] or 0
                seen[s] = true
            end
        end
        partnership = {
            sides = copy_list(sides),
            totals = side_totals,
        }
    end

    local raspassy_active = session:raspassy_active()
    -- Hide bid/leader/trump indicators while raspassy is in play —
    -- raspassy lacks a contract and a trump, and the scene's normal
    -- chrome (current-bid pill, trump suit indicator) would show stale
    -- values from the abandoned auction otherwise.
    local current_bid = raspassy_active and nil or session:current_bid()
    local leader = raspassy_active and nil or session:current_leader()
    local trump = raspassy_active and nil or session:trump()

    return {
        phase = session:current_phase(),
        turn_player = turn,
        dealer = dealer,
        current_bid = current_bid,
        leader = leader,
        trump = trump,
        scoreboard = scoreboard,
        hands = hands,
        talon = talon,
        stock = stock_block,
        winner = winner,
        final_scores = final and copy_list(final) or nil,
        player_count = player_count,
        sits_out = sits_out,
        partnership = partnership,
        auction = build_auction_block(session),
        talon_phase = build_talon_phase_block(session),
        current_trick = build_current_trick_block(session),
        marriage_offer = build_marriage_offer_block(session),
        deal_done = build_deal_done_block(session),
        redeal_prompt = build_redeal_prompt_block(session),
        misdeal_banner = build_misdeal_banner_block(session),
        all_pass_banner = build_all_pass_banner_block(session),
        raspassy_active = raspassy_active,
        bad_talon_prompt = build_bad_talon_prompt_block(session),
        buyback_banner = build_buyback_banner_block(session),
        rebuy_prompt = build_rebuy_prompt_block(session),
    }
end

return M
