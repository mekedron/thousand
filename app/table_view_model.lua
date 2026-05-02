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

-- Phase 3.6 bidding-house-rules helpers ---------------------------------

-- Whether forehand is gated from passing on round 1 by `forced_opening`.
local function is_forehand_pass_disabled(session, auction)
    if session:config().bidding.forced_opening ~= "on" then
        return false
    end
    if #auction.history > 0 then
        return false
    end
    if auction.turn ~= auction.forehand then
        return false
    end
    return true
end

-- Banner data when the dealer was assigned the minimum-100 contract via
-- `forced_dealer_bid`. Visible until the next deal starts.
local function build_dealer_forced_banner(auction)
    if not auction.dealer_forced then
        return nil
    end
    return {
        dealer_seat = auction.dealer,
        amount = auction.final_bid,
    }
end

-- Pre-reveal blind-bid offer for the seat on turn. Gated on the toggle
-- being on, the seat not having acted yet this auction, and the seat
-- not having dismissed its privacy curtain.
local function build_blind_bid_offer(session, auction)
    local config = session:config()
    if config.bidding.blind_bid == "off" then
        return nil
    end
    if auction.status ~= "in_progress" then
        return nil
    end
    local seat = auction.turn
    if seat == nil then
        return nil
    end
    for i = 1, #auction.history do
        if auction.history[i].player == seat then
            return nil
        end
    end
    if session:has_revealed_hand(seat) then
        return nil
    end
    return {
        seat = seat,
        multiplier_preview = config.bidding.blind_bid_success_multiplier or 2,
    }
end

-- Seats currently passed but still eligible to use their single
-- re-entry. Sits-out and locked seats are excluded.
local function build_passed_seats_with_re_entry(session, auction)
    if session:config().bidding.re_entry_after_pass ~= "on" then
        return nil
    end
    local seats = {}
    for seat = 1, auction.player_count do
        if
            auction.passed[seat]
            and not session:has_used_re_entry(seat)
            and not (auction.sits_out and seat == auction.sits_out)
            and not (auction.locked and auction.locked[seat])
        then
            seats[#seats + 1] = seat
        end
    end
    if #seats == 0 then
        return nil
    end
    return seats
end

-- Bid amounts greyed out by `no_contract_without_marriage` for the seat
-- on turn. Returns nil when the rule is off or every amount is legal.
local function build_disabled_bid_amounts(session, auction, allowed)
    local mode = session:config().bidding.no_contract_without_marriage
    if mode == "off" then
        return nil
    end
    local turn = auction.turn
    if turn == nil then
        return nil
    end
    local holdings = auction.holdings
    if not holdings or not holdings[turn] then
        return nil
    end
    local marriage_total = holdings[turn].marriage_total or 0
    local cap
    if mode == "no_120_without_marriage" then
        if marriage_total > 0 then
            return nil
        end
        cap = 119
    elseif mode == "capped_by_marriages" then
        cap = 120 + marriage_total
    end
    local disabled = {}
    local any = false
    for _, amount in ipairs(allowed) do
        if amount > cap then
            disabled[amount] = true
            any = true
        end
    end
    if not any then
        return nil
    end
    return disabled
end

-- Locked-to-100 amount for negative-score-restricted seats on turn.
local function build_locked_bid_amount(session, auction)
    if session:config().bidding.negative_score_restriction ~= "on" then
        return nil
    end
    local turn = auction.turn
    if turn == nil then
        return nil
    end
    if not auction.locked or not auction.locked[turn] then
        return nil
    end
    return session:config().bidding.opening_min
end

-- Special-contract bid buttons (mizère, slam, open hand) — one per
-- enabled `specials.*` toggle when the umbrella `named_contracts` is
-- on.
local function build_named_contract_buttons(session, auction)
    local config = session:config()
    if config.bidding.named_contracts ~= "on" then
        return nil
    end
    if auction.status ~= "in_progress" then
        return nil
    end
    local buttons = {}
    if config.specials.mizere == "on" then
        buttons[#buttons + 1] = {
            id = "named_mizere", -- i18n-ok
            kind = "mizere",
            contract_value = 120,
        }
    end
    if config.specials.slam_contract == "on" then
        buttons[#buttons + 1] = {
            id = "named_slam", -- i18n-ok
            kind = "slam",
            contract_value = session:slam_contract_value(),
        }
    end
    if config.specials.open_hand == "on" then
        buttons[#buttons + 1] = {
            id = "named_open_hand", -- i18n-ok
            kind = "open_hand",
            contract_value = 200,
        }
    end
    if #buttons == 0 then
        return nil
    end
    return buttons
end

-- Active contra/redouble offer surfaced to the talon-take panel.
-- Returns the contra phase for defenders first, then the redouble
-- phase for the declarer once contra has been declared. Returns nil
-- once the window has closed.
local function build_contra_offer(session)
    if not session:contra_window_open() then
        return nil
    end
    if not session:contra_declared() then
        return {
            kind = "contra",
            seats = session:defender_seats(),
        }
    end
    if
        session:config().bidding.contra == "contra_and_redouble"
        and not session:redouble_declared()
    then
        local declarer = session._auction and session._auction.declarer
        if declarer == nil then
            return nil
        end
        return {
            kind = "redouble",
            seats = { declarer },
        }
    end
    return nil
end

-- Forced-bid concession offer surfaced to the talon-take panel during
-- the `awaiting_forced_concession_decision` phase.
local function build_concede_offer(session)
    local offer = session:forced_concession_offer_state()
    if not offer then
        return nil
    end
    return {
        split_preview = offer.split_mode,
    }
end

local function build_auction_block(session)
    local auction = session._auction
    if not auction then
        return nil
    end
    local current_phase_id = session:current_phase()
    local in_auction = current_phase_id == "auction" -- i18n-ok: phase enums
        and auction.status == "in_progress" -- i18n-ok: status enums
    local dealer_forced = auction.dealer_forced == true
    if not in_auction and not dealer_forced then
        return nil
    end

    local block = {}
    -- Banner is shown post-auction (dealer was forced into 100); it
    -- remains until the next deal so the table scene has a frame to
    -- render it before transitioning into talon.
    block.dealer_forced_banner = build_dealer_forced_banner(auction)

    if not in_auction then
        return block
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
    local config = session:config()
    local allowed = compute_allowed_bids(config, auction.current_bid)
    local locked_bid_amount = build_locked_bid_amount(session, auction)
    if locked_bid_amount then
        allowed = { locked_bid_amount }
    end
    local disabled_bid_amounts = build_disabled_bid_amounts(session, auction, allowed)
    local forehand_pass_disabled = is_forehand_pass_disabled(session, auction)
    block.history = history_copy
    block.current_bid = auction.current_bid
    block.leader = auction.current_leader
    block.on_turn = auction.turn
    block.can_pass = not forehand_pass_disabled
    block.forehand_pass_disabled = forehand_pass_disabled
    block.pass_disabled_reason = forehand_pass_disabled and "forced_opening" or nil
    block.allowed_bid_amounts = allowed
    block.disabled_bid_amounts = disabled_bid_amounts
    block.locked_bid_amount = locked_bid_amount
    block.blind_bid_offer = build_blind_bid_offer(session, auction)
    block.passed_seats_with_re_entry = build_passed_seats_with_re_entry(session, auction)
    block.named_contract_buttons = build_named_contract_buttons(session, auction)
    return block
end

local function build_talon_phase_block(session)
    local phase = session:current_phase()
    local talon_phase = "talon" -- i18n-ok: phase enum
    local bad_talon_phase = "awaiting_bad_talon_decision" -- i18n-ok: phase enum
    local rebuy_phase = "awaiting_rebuy_decision" -- i18n-ok: phase enum
    local concession_phase = "awaiting_forced_concession_decision" -- i18n-ok: phase enum
    -- Phase 3.6 forced-bid concession: the concession-decision phase
    -- has no live talon yet but the table-take panel still renders the
    -- concede button. Surface a minimal block so the UI can find its
    -- offer.
    if phase == concession_phase then
        local concede_offer = build_concede_offer(session)
        if concede_offer then
            return { concede_offer = concede_offer }
        end
        return nil
    end
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
        -- Phase 3.6 bidding-house-rules: contra/redouble window is
        -- open from auction-done through tricks-phase start; concede
        -- offer fires only in the awaiting-decision phase but is
        -- mirrored here for the talon-take panel's convenience.
        contra_offer = build_contra_offer(session),
        concede_offer = build_concede_offer(session),
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
    -- Phase 3.6 marriage_announcement_timing: the on_lead default is
    -- the only path that reaches the K/Q-tap modal. Hand-announcement
    -- and pre-first-trick variants surface their own affordances
    -- (see `hand_announcement_marriage_offer` and
    -- `pre_first_trick_marriage_offer`).
    if session:config().marriages.marriage_announcement_timing ~= "on_lead" then
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

-- Phase 3.6: surfaced when the active seat is on lead, the trick is
-- empty, the variant is `hand_announcement`, and the seat holds at
-- least one undeclared marriage.
local function build_hand_announcement_marriage_offer_block(session)
    if session:current_phase() ~= "tricks" then
        return nil
    end
    if session:config().marriages.marriage_announcement_timing ~= "hand_announcement" then
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
    return { seat = turn, suits = copy_list(suits) }
end

-- Phase 3.6: surfaced while the session is in
-- `awaiting_pre_first_trick_marriages` for the active seat.
local function build_pre_first_trick_marriage_offer_block(session)
    local state = session:pre_first_trick_announcement_state()
    if not state then
        return nil
    end
    return {
        seat = state.seat,
        pending_seats = copy_list(state.pending_seats),
        eligible_suits = copy_list(state.eligible_suits),
    }
end

-- Phase 3.6: surfaced when `ace_marriage` is enabled and the active
-- seat holds all four Aces.
local function build_ace_marriage_offer_block(session)
    if session:config().marriages.ace_marriage == "off" then
        return nil
    end
    local phase = session:current_phase()
    local pre_phase = "awaiting_pre_first_trick_marriages" -- i18n-ok: phase enum
    if phase ~= "tricks" and phase ~= pre_phase then
        return nil
    end
    local turn = session:current_turn()
    if not turn then
        return nil
    end
    local hands = session:hands()
    local hand = hands and hands[turn]
    if not hand then
        return nil
    end
    local seen = {}
    for _, c in ipairs(hand) do
        if c.rank == "A" then
            seen[c.suit] = true
        end
    end
    if not (seen.hearts and seen.diamonds and seen.clubs and seen.spades) then
        return nil
    end
    -- Suppress when an ace marriage has already been declared this
    -- deal.
    local marriages_state = session._marriages
    if marriages_state then
        for _, decl in ipairs(marriages_state.declarations) do
            if decl.kind == "ace_marriage" and not decl.cancelled then
                return nil
            end
        end
    end
    return { seat = turn }
end

-- Phase 3.6: latest drowned-marriage cancellation, surfaced as a
-- banner. nil when the log is empty.
local function build_drowned_marriage_banner_block(session)
    local log = session:drowned_marriage_log()
    if not log or #log == 0 then
        return nil
    end
    local entry = log[#log]
    return {
        suit = entry.suit,
        declarer = entry.declarer,
        value = entry.value,
        trick_index = entry.trick_index,
    }
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

local function nonzero_total(list)
    if list == nil then
        return 0
    end
    local total = 0
    for i = 1, #list do
        total = total + list[i]
    end
    return total
end

-- Phase 3.6: build the deal-done score breakdown from the per-seat
-- bonus arrays surfaced by Session:deal_done(). Each row materialises
-- only when its `total ~= 0`, so the table scene can iterate the list
-- without skip checks. Order mirrors the scoreboard reading order:
-- marriage bonuses first (already part of deal_scores), then capture
-- and ace marriages, then trick-play bonuses.
local function build_score_breakdown(payload)
    if not payload then
        return nil
    end
    local rows = {}
    local row_specs = {
        {
            kind = "marriage_bonus",
            label_key = "scene.table.scoreboard.marriage_row",
            list = payload.marriage_bonuses,
        },
        {
            kind = "half_marriage_capture",
            label_key = "scene.table.scoreboard.half_marriage_capture_row",
            list = payload.half_marriage_capture_bonuses,
        },
        {
            kind = "ace_marriage",
            label_key = "scene.table.scoreboard.ace_marriage_row",
            list = payload.ace_marriage_bonuses,
        },
        {
            kind = "last_trick",
            label_key = "scene.table.scoreboard.last_trick_row",
            list = payload.last_trick_bonus,
        },
        {
            kind = "slam_bonus",
            label_key = "scene.table.scoreboard.slam_bonus_row",
            list = payload.slam_bonus,
        },
        {
            kind = "slam_against",
            label_key = "scene.table.scoreboard.slam_against_row",
            list = payload.slam_against_penalty,
        },
    }
    for _, spec in ipairs(row_specs) do
        local total = nonzero_total(spec.list)
        if total ~= 0 then
            rows[#rows + 1] = {
                kind = spec.kind,
                label_key = spec.label_key,
                amounts_by_seat = copy_list(spec.list),
                total = total,
            }
        end
    end
    return rows
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
    block.score_breakdown = build_score_breakdown(payload)
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
        hand_announcement_marriage_offer = build_hand_announcement_marriage_offer_block(session),
        pre_first_trick_marriage_offer = build_pre_first_trick_marriage_offer_block(session),
        ace_marriage_offer = build_ace_marriage_offer_block(session),
        pending_ace_trump_seat = session:pending_ace_trump_seat(),
        drowned_marriage_banner = build_drowned_marriage_banner_block(session),
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
