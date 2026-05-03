-- Phase 4.1: bot driver loop.
--
-- A scene-driven engine that turns "it's a bot's turn" into a Session
-- mutator call. The driver:
--
--   1. Inspects `Session:current_phase()` (and sub-states) to decide
--      which chooser to ask.
--   2. Reads the responsible seat from `current_turn()` for turn-based
--      phases, falling back to the offer state for awaiting-* modals
--      where current_turn() returns nil.
--   3. Asks the chooser for an action descriptor `{ kind, ... }`,
--      schedules the apply for `delay` seconds in the future (capped
--      at `max_delay`) so the table scene can render a "thinking…"
--      banner.
--   4. On the next tick past the scheduled fire-time, dispatches the
--      descriptor to the matching `Session` mutator.
--
-- Pure decision lives in the choosers; the driver is the thin glue.
-- The default chooser registry is `app.bot.stubs` — Phase 4.3 and 4.5
-- replace per-chooser entries with real heuristics.
--
-- Algorithm-vs-LLM firewall: this module imports nothing from `ui.*`
-- or `app.llm.*`. Enforced by tests/spec/lint/firewall_spec.lua.

local contract = require("app.bot.contract")
local default_choosers = require("app.bot.stubs")

local M = {}

local DEFAULT_DELAY = 0.6
local DEFAULT_MAX_DELAY = 2.0

-- Default clock. Tests can pass `now_fn` directly through `M.new`,
-- or set the package-level `_clock_for_test` (mirrors the pattern
-- in app/templates.lua) when wiring is not test-aware.
M._clock_for_test = nil

local function default_now()
    if M._clock_for_test then
        return M._clock_for_test()
    end
    if love and love.timer and love.timer.getTime then
        return love.timer.getTime()
    end
    return 0
end

local Driver = {}
Driver.__index = Driver

local MODAL_PHASE_TO_CHOOSER = {
    awaiting_redeal_decision = "choose_redeal",
    awaiting_bad_talon_decision = "choose_bad_talon_redeal",
    awaiting_rebuy_decision = "choose_rebuy",
    awaiting_write_off_decision = "choose_write_off",
    awaiting_pre_first_trick_marriages = "choose_pre_first_trick_marriage",
    awaiting_forced_concession_decision = "choose_forced_bid_concession",
}

-- Given a session, decide which chooser the driver should call. Returns
-- nil for phases the driver does not yet drive (cut, raspassy_play,
-- done, contra windows). Phase 4.3+ extends this map.
local function pick_chooser(session)
    local phase = session:current_phase()
    local modal = MODAL_PHASE_TO_CHOOSER[phase]
    if modal then
        return modal
    end
    if phase == "auction" then
        return "choose_bid"
    end
    if phase == "talon" then
        local sub = session:talon_substate()
        if sub == "action" then
            return "choose_talon_action"
        end
        -- i18n-ok: substate enum tokens (engine-internal, never rendered)
        local pass_kinds = { pass = true, polish_pass = true, discard = true }
        if pass_kinds[sub] then
            return "choose_talon_pass"
        end
        if sub == "raise" then
            return "choose_raise"
        end
        return nil
    end
    if phase == "tricks" then
        -- Phase 4.1 wires straight to choose_card; the marriage routing
        -- lands with the Phase 4.3 marriage heuristic.
        return "choose_card"
    end
    if phase == "deal_done" then
        return "choose_next_deal"
    end
    return nil
end

-- The seat that owns the next decision. For most phases this matches
-- `current_turn()`, but the awaiting-* modals where current_turn() is
-- nil read the responsible seat off the offer state instead.
local function responsible_seat(session)
    local turn = session:current_turn()
    if turn then
        return turn
    end
    local phase = session:current_phase()
    if phase == "awaiting_redeal_decision" then
        local offer = session:redeal_offer()
        return offer and offer.seat or nil
    end
    if phase == "awaiting_bad_talon_decision" then
        local offer = session:bad_talon_offer_state()
        return offer and offer.declarer or nil
    end
    if phase == "awaiting_forced_concession_decision" then
        local offer = session:forced_concession_offer_state()
        return offer and offer.declarer or nil
    end
    return nil
end

-- Action-descriptor → Session mutator dispatch table. Each entry takes
-- (session, seat, action) and returns the mutator's result envelope.
-- Mirrors the action map documented in app/bot/contract.lua's header.
local function noop()
    return { ok = true, no_op = true }
end

local DISPATCH = {
    bid = function(s, seat, a)
        return s:bid(seat, a.amount)
    end,
    pass = function(s, seat)
        return s:pass(seat)
    end,
    declare_blind = function(s, seat)
        return s:declare_blind(seat)
    end,
    bid_re_entry = function(s, seat, a)
        return s:bid_re_entry(seat, a.amount)
    end,
    bid_named_contract = function(s, seat, a)
        return s:bid_named_contract(seat, a.contract)
    end,
    declare_contra = function(s, seat)
        return s:declare_contra(seat)
    end,
    declare_redouble = function(s, seat)
        return s:declare_redouble(seat)
    end,
    skip_contra = noop,
    accept_redeal = function(s)
        return s:accept_redeal()
    end,
    decline_redeal = function(s)
        return s:decline_redeal()
    end,
    accept_bad_talon_redeal = function(s)
        return s:accept_bad_talon_redeal()
    end,
    decline_bad_talon_redeal = function(s)
        return s:decline_bad_talon_redeal()
    end,
    claim_rebuy = function(s, seat)
        return s:claim_rebuy(seat)
    end,
    decline_rebuy = function(s, seat)
        return s:decline_rebuy(seat)
    end,
    take_talon = function(s)
        return s:take_talon()
    end,
    concede_deal = function(s)
        return s:concede_deal()
    end,
    buyback_hand = function(s)
        return s:buyback_hand()
    end,
    pass_talon = function(s, _, a)
        return s:pass_talon(a.target, a.card)
    end,
    pass_polish_talon = function(s, _, a)
        return s:pass_polish_talon(a.target, a.talon_index)
    end,
    discard_talon = function(s, _, a)
        return s:discard_talon(a.card)
    end,
    raise = function(s, _, a)
        return s:raise(a.amount)
    end,
    skip_raise = function(s)
        return s:skip_raise()
    end,
    play = function(s, seat, a)
        return s:play(seat, a.card)
    end,
    declare_marriage = function(s, seat, a)
        return s:declare_marriage(seat, a.suit)
    end,
    announce_marriage = function(s, seat, a)
        return s:announce_marriage(seat, a.suit)
    end,
    skip_announce_marriage = function(s, seat)
        return s:skip_pre_first_trick_marriage(seat)
    end,
    accept_play = function(s)
        return s:accept_play()
    end,
    write_off = function(s)
        return s:write_off()
    end,
    concede_forced_bid = function(s)
        return s:concede_forced_bid()
    end,
    decline_forced_bid = function(s)
        return s:decline_forced_bid()
    end,
    start_next_deal = function(s)
        return s:start_next_deal()
    end,
}

function M.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Driver)
    self._choosers = opts.choosers or default_choosers
    self._delay = opts.delay or DEFAULT_DELAY
    self._max_delay = opts.max_delay or DEFAULT_MAX_DELAY
    self._now_fn = opts.now_fn or default_now
    self._pending = nil
    return self
end

local function apply_action(session, seat, action)
    local handler = DISPATCH[action.kind]
    if not handler then
        error("bot driver: unknown action kind '" .. tostring(action.kind) .. "'", 2)
    end
    return handler(session, seat, action)
end

function Driver:tick(session, seat_kinds)
    if self._pending then
        if self._now_fn() >= self._pending.fire_at then
            local pending = self._pending
            self._pending = nil
            apply_action(session, pending.seat, pending.action)
        end
        return
    end

    local seat = responsible_seat(session)
    if not seat then
        return
    end
    local kind = (seat_kinds and seat_kinds[seat]) or "human"
    if kind ~= "bot" then
        return
    end

    local chooser_name = pick_chooser(session)
    if not chooser_name then
        return
    end
    local chooser = self._choosers[chooser_name]
    if not chooser then
        error("bot driver: missing chooser '" .. chooser_name .. "'", 2)
    end

    local view = contract.make_view(session)
    local action = chooser(view, seat)
    if type(action) ~= "table" or action.kind == nil then
        error("bot driver: chooser '" .. chooser_name .. "' returned no descriptor", 2)
    end

    local effective_delay = math.min(self._delay, self._max_delay)
    self._pending = {
        seat = seat,
        action = action,
        chooser_name = chooser_name,
        fire_at = self._now_fn() + effective_delay,
    }
end

function Driver:is_thinking()
    return self._pending ~= nil
end

function Driver:thinking_seat()
    return self._pending and self._pending.seat or nil
end

function Driver:reset()
    self._pending = nil
end

return M
