-- Phase 4.1: deterministic-legal chooser stubs the bot driver dispatches
-- to until Phase 4.3 (baseline-legal play) and Phase 4.5 (Phase 3.6
-- toggle behaviour) replace each chooser with a real heuristic.
--
-- Every stub is a pure function `(view, seat) → action_descriptor` and
-- returns the deterministic minimum legal action — pass at every offer,
-- play `view:legal_cards(seat)[1]`, take the talon when offered. The
-- aim is to make the engine-driver loop testable end-to-end before any
-- bot strategy lands; the stubs intentionally never bid, never declare
-- a marriage, and never accept a redeal.
--
-- Algorithm-vs-LLM firewall: this module imports nothing from `ui.*`
-- or `app.llm.*`. Enforced by tests/spec/lint/firewall_spec.lua.

local M = {}

local function first_opponent(declarer, player_count)
    for seat = 1, player_count do
        if seat ~= declarer then
            return seat
        end
    end
    return nil
end

function M.choose_bid(_view, _seat)
    return { kind = "pass" } -- i18n-ok: action enum
end

function M.choose_contra(_view, _seat)
    return { kind = "skip_contra" } -- i18n-ok: action enum
end

function M.choose_cut_deck(_view, _seat)
    return { kind = "cut_deck" } -- i18n-ok: action enum
end

function M.choose_redeal(_view, _seat)
    return { kind = "decline_redeal" } -- i18n-ok: action enum
end

function M.choose_bad_talon_redeal(_view, _seat)
    return { kind = "decline_bad_talon_redeal" } -- i18n-ok: action enum
end

function M.choose_rebuy(_view, _seat)
    return { kind = "decline_rebuy" } -- i18n-ok: action enum
end

function M.choose_forced_bid_concession(_view, _seat)
    return { kind = "decline_forced_bid" } -- i18n-ok: action enum
end

function M.choose_write_off(_view, _seat)
    return { kind = "accept_play" } -- i18n-ok: action enum
end

function M.choose_marriage(_view, _seat)
    return { kind = "skip_declare_marriage" } -- i18n-ok: action enum
end

function M.choose_pre_first_trick_marriage(_view, _seat)
    return { kind = "skip_announce_marriage" } -- i18n-ok: action enum
end

function M.choose_card(view, seat)
    local legal = view:legal_cards(seat)
    return { kind = "play", card = legal[1] } -- i18n-ok: action enum
end

function M.choose_talon_action(_view, _seat)
    return { kind = "take_talon" } -- i18n-ok: action enum
end

function M.choose_raise(_view, _seat)
    return { kind = "skip_raise" } -- i18n-ok: action enum
end

function M.choose_next_deal(_view, _seat)
    return { kind = "start_next_deal" } -- i18n-ok: action enum
end

function M.choose_talon_pass(view, seat)
    local substate = view:talon_substate()
    local hand = view:hands()[seat] or {}
    local config = view:config()
    local target = first_opponent(seat, config.players.count)
    if substate == "polish_pass" then
        return {
            kind = "pass_polish_talon", -- i18n-ok: action enum
            target = target,
            talon_index = 1,
        }
    end
    if substate == "discard" then
        return {
            kind = "discard_talon", -- i18n-ok: action enum
            card = hand[1],
        }
    end
    return {
        kind = "pass_talon", -- i18n-ok: action enum
        target = target,
        card = hand[1],
    }
end

return M
