-- Phase 4.1: bot player interface contract.
--
-- This module is the public anchor for the algorithmic-bot subsystem.
-- It owns the chooser registry and a convenience helper for wrapping a
-- session in the read-only view that every chooser operates on.
-- Concrete chooser implementations land in Phase 4.3 (baseline-legal
-- play) and Phase 4.5 (Phase 3.6 toggle behaviour).
--
-- Public API:
--
--   * make_view(session) — wrap a session in a SessionView so a
--     chooser cannot reach engine mutators. Delegates to
--     app.bot.session_view.
--   * CHOOSERS — array of contract entries describing every chooser
--     the interface promises: { name, phase, returns }. The driver
--     loop (next 4.1 sub-task) keys off phase; tests key off name and
--     returns to detect contract drift.
--
-- Action descriptors. Every chooser is a pure function over
-- (view, seat) returning a plain Lua table:
--
--     { kind = "<engine_action>", ... }
--
-- where the additional fields match the corresponding Session
-- mutator's signature, e.g.:
--
--     { kind = "bid", amount = 100 }              -> Session:bid(seat, 100)
--     { kind = "pass" }                            -> Session:pass(seat)
--     { kind = "play", card = card_obj }           -> Session:play(seat, card)
--     { kind = "pass_talon", target = 2,           -> Session:pass_talon(target, card)
--       card = card_obj }
--     { kind = "declare_marriage", suit = "♥" }   -> Session:declare_marriage(seat, suit)
--     { kind = "start_next_deal" }                 -> Session:start_next_deal()
--
-- Returning a descriptor (rather than a closure or a mutator call)
-- keeps choosers pure and trivially unit-testable.
--
-- Algorithm-vs-LLM firewall: nothing under app/bot/ may import from
-- the LLM client or the UI layer. Enforced by
-- tests/spec/lint/firewall_spec.lua.

local session_view = require("app.bot.session_view")

local M = {}

function M.make_view(session)
    return session_view.new(session)
end

local function freeze(t)
    return setmetatable(t, {
        __newindex = function(_, key)
            error("CHOOSERS: frozen; cannot set '" .. tostring(key) .. "'", 2)
        end,
    })
end

local CHOOSERS = {
    {
        name = "choose_bad_talon_redeal",
        phase = "awaiting_bad_talon_decision",
        returns = {
            "accept_bad_talon_redeal",
            "decline_bad_talon_redeal",
        },
    },
    {
        name = "choose_bid",
        phase = "auction",
        returns = {
            "bid",
            "pass",
            "declare_blind",
            "bid_re_entry",
            "bid_named_contract",
        },
    },
    {
        name = "choose_card",
        phase = "tricks",
        returns = {
            "play",
        },
    },
    {
        name = "choose_contra",
        phase = "auction",
        returns = {
            "declare_contra",
            "declare_redouble",
            "skip_contra",
        },
    },
    {
        name = "choose_cut_deck",
        phase = "cut",
        returns = {
            "cut_deck",
        },
    },
    {
        name = "choose_forced_bid_concession",
        phase = "awaiting_forced_concession_decision",
        returns = {
            "concede_forced_bid",
            "decline_forced_bid",
        },
    },
    {
        name = "choose_marriage",
        phase = "tricks",
        returns = {
            "declare_marriage",
            "skip_declare_marriage",
        },
    },
    {
        name = "choose_next_deal",
        phase = "deal_done",
        returns = {
            "start_next_deal",
        },
    },
    {
        name = "choose_pre_first_trick_marriage",
        phase = "awaiting_pre_first_trick_marriages",
        returns = {
            "announce_marriage",
            "skip_announce_marriage",
        },
    },
    {
        name = "choose_raise",
        phase = "talon",
        returns = {
            "raise",
            "skip_raise",
        },
    },
    {
        name = "choose_rebuy",
        phase = "awaiting_rebuy_decision",
        returns = {
            "claim_rebuy",
            "decline_rebuy",
        },
    },
    {
        name = "choose_redeal",
        phase = "awaiting_redeal_decision",
        returns = {
            "accept_redeal",
            "decline_redeal",
        },
    },
    {
        name = "choose_talon_action",
        phase = "talon",
        returns = {
            "take_talon",
            "concede_deal",
            "buyback_hand",
        },
    },
    {
        name = "choose_talon_pass",
        phase = "talon",
        returns = {
            "pass_talon",
            "pass_polish_talon",
            "discard_talon",
        },
    },
    {
        name = "choose_write_off",
        phase = "awaiting_write_off_decision",
        returns = {
            "accept_play",
            "write_off",
        },
    },
}

for _, entry in ipairs(CHOOSERS) do
    freeze(entry.returns)
    freeze(entry)
end
freeze(CHOOSERS)

M.CHOOSERS = CHOOSERS

return M
