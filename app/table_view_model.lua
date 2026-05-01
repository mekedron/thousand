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
-- Pure Lua, no love.* — same layer as app/i18n.lua and app/session.lua.

local M = {}

local function copy_list(list)
    local copy = {}
    for i = 1, #list do
        copy[i] = list[i]
    end
    return copy
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

    local hands_in = session:hands()
    local hands = {}
    for i = 1, player_count do
        local cards = hands_in[i] or {}
        hands[i] = {
            player = i,
            -- Seat 1 always represents the local human in hot-seat mode;
            -- seats 2 and 3 are opponents and rendered face-down so the
            -- privacy overlay (a later task) can layer on top without
            -- having to undo a face-up render here. The "self"/"other"
            -- enum below is internal, not user-visible.
            perspective = (i == 1) and "self" or "other", -- i18n-ok
            cards = copy_list(cards),
            count = #cards,
            is_dealer = (i == dealer),
            is_turn = (i == turn),
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
    }
end

return M
