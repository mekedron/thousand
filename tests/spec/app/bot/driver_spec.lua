-- Phase 4.1: bot driver loop. Verifies (a) phase + sub-state routing
-- to the correct chooser, (b) action-descriptor → Session mutator
-- dispatch, (c) the latency cap that drives the "thinking…" indicator,
-- (d) human-seat ticks are no-ops, and (e) reset() clears pending
-- decisions on scene re-entry.

local driver = require("app.bot.driver")

-- Fake session: every accessor returns whatever the test put in `state`,
-- and every mutator records its name and args without changing state.
-- Mirrors the Session surface the driver actually calls — tests pin
-- the driver against the contract, not against a real RuleConfig.
local function make_fake_session(state)
    state = state or {}
    local calls = {}
    local s = { _calls = calls }
    s.current_phase = function()
        return state.phase
    end
    s.current_turn = function()
        return state.turn
    end
    s.redeal_offer = function()
        return state.redeal_offer
    end
    s.bad_talon_offer_state = function()
        return state.bad_talon_offer
    end
    s.rebuy_offer_state = function()
        return state.rebuy_offer
    end
    s.forced_concession_offer_state = function()
        return state.forced_concession_offer
    end
    s.talon_substate = function()
        return state.talon_substate
    end
    s.hands = function()
        return state.hands or { {}, {}, {} }
    end
    s.legal_cards = function(_, seat)
        return (state.legal_cards or {})[seat] or {}
    end
    s.available_marriages = function(_, seat)
        return (state.available_marriages or {})[seat] or {}
    end
    s.talon_cards = function()
        return state.talon_cards or {}
    end
    s.current_bid = function()
        return state.current_bid
    end
    s.current_trick = function()
        return state.current_trick
    end
    s.trump = function()
        return state.trump
    end
    s.config = function()
        return state.config or { players = { count = 3 } }
    end
    local mutators = {
        "bid",
        "pass",
        "play",
        "take_talon",
        "pass_talon",
        "pass_polish_talon",
        "discard_talon",
        "raise",
        "skip_raise",
        "concede_deal",
        "buyback_hand",
        "accept_redeal",
        "decline_redeal",
        "accept_bad_talon_redeal",
        "decline_bad_talon_redeal",
        "claim_rebuy",
        "decline_rebuy",
        "declare_marriage",
        "announce_marriage",
        "skip_pre_first_trick_marriage",
        "accept_play",
        "write_off",
        "concede_forced_bid",
        "decline_forced_bid",
        "start_next_deal",
        "declare_blind",
        "bid_re_entry",
        "bid_named_contract",
        "declare_contra",
        "declare_redouble",
        "cut_deck",
    }
    for _, m in ipairs(mutators) do
        s[m] = function(_, ...)
            calls[#calls + 1] = { method = m, args = { ... } }
            return { ok = true }
        end
    end
    return s
end

local function fake_clock(start)
    local now = start or 0
    return {
        now = function()
            return now
        end,
        advance = function(dt)
            now = now + dt
        end,
    }
end

describe("app.bot.driver", function()
    describe("M.new", function()
        it("returns a driver with default options", function()
            local d = driver.new({})
            assert.is_function(d.tick)
            assert.is_function(d.is_thinking)
            assert.is_function(d.thinking_seat)
            assert.is_function(d.reset)
        end)

        it("starts idle (not thinking, no thinking_seat)", function()
            local d = driver.new({})
            assert.is_false(d:is_thinking())
            assert.is_nil(d:thinking_seat())
        end)
    end)

    describe(":tick", function()
        it("is a no-op on a human seat", function()
            local s = make_fake_session({ phase = "auction", turn = 1 })
            local clock = fake_clock(0)
            local d = driver.new({
                choosers = {
                    choose_bid = function()
                        return { kind = "pass" }
                    end,
                },
                now_fn = clock.now,
            })
            d:tick(s, { "human", "human", "human" })
            assert.is_false(d:is_thinking())
            assert.are.equal(0, #s._calls)
        end)

        it("is a no-op when no seat is responsible", function()
            local s = make_fake_session({ phase = "done", turn = nil })
            local clock = fake_clock(0)
            local d = driver.new({ now_fn = clock.now })
            d:tick(s, { "bot", "bot", "bot" })
            assert.is_false(d:is_thinking())
            assert.are.equal(0, #s._calls)
        end)

        it("is a no-op for phases without a chooser (raspassy_play)", function()
            local s = make_fake_session({ phase = "raspassy_play", turn = 2 })
            local clock = fake_clock(0)
            local d = driver.new({ now_fn = clock.now })
            d:tick(s, { "human", "bot", "bot" })
            assert.is_false(d:is_thinking())
            assert.are.equal(0, #s._calls)
        end)

        it("schedules a pending decision on the first bot tick (does not apply yet)", function()
            local s = make_fake_session({ phase = "auction", turn = 2 })
            local clock = fake_clock(0)
            local d = driver.new({
                choosers = {
                    choose_bid = function()
                        return { kind = "pass" }
                    end,
                },
                now_fn = clock.now,
                delay = 0.5,
            })
            d:tick(s, { "human", "bot", "bot" })
            assert.is_true(d:is_thinking())
            assert.are.equal(2, d:thinking_seat())
            assert.are.equal(0, #s._calls)
        end)

        it("does not double-schedule on repeated ticks before fire time", function()
            local s = make_fake_session({ phase = "auction", turn = 2 })
            local clock = fake_clock(0)
            local d = driver.new({
                choosers = {
                    choose_bid = function()
                        return { kind = "pass" }
                    end,
                },
                now_fn = clock.now,
                delay = 0.5,
            })
            d:tick(s, { "human", "bot", "bot" })
            d:tick(s, { "human", "bot", "bot" })
            d:tick(s, { "human", "bot", "bot" })
            assert.is_true(d:is_thinking())
            assert.are.equal(0, #s._calls)
        end)

        it("applies the pending decision once the clock crosses fire_at", function()
            local s = make_fake_session({ phase = "auction", turn = 2 })
            local clock = fake_clock(0)
            local d = driver.new({
                choosers = {
                    choose_bid = function()
                        return { kind = "pass" }
                    end,
                },
                now_fn = clock.now,
                delay = 0.5,
            })
            d:tick(s, { "human", "bot", "bot" })
            clock.advance(0.6)
            d:tick(s, { "human", "bot", "bot" })
            assert.is_false(d:is_thinking())
            assert.are.equal(1, #s._calls)
            assert.are.equal("pass", s._calls[1].method)
            assert.are.equal(2, s._calls[1].args[1])
        end)

        it("clamps delay to max_delay", function()
            local s = make_fake_session({ phase = "auction", turn = 2 })
            local clock = fake_clock(100)
            local d = driver.new({
                choosers = {
                    choose_bid = function()
                        return { kind = "pass" }
                    end,
                },
                now_fn = clock.now,
                delay = 5.0,
                max_delay = 1.0,
            })
            d:tick(s, { "human", "bot", "bot" })
            clock.advance(1.0)
            d:tick(s, { "human", "bot", "bot" })
            assert.is_false(d:is_thinking())
            assert.are.equal(1, #s._calls)
        end)
    end)

    describe(":reset", function()
        it("clears any pending decision", function()
            local s = make_fake_session({ phase = "auction", turn = 2 })
            local clock = fake_clock(0)
            local d = driver.new({
                choosers = {
                    choose_bid = function()
                        return { kind = "pass" }
                    end,
                },
                now_fn = clock.now,
                delay = 0.5,
            })
            d:tick(s, { "human", "bot", "bot" })
            assert.is_true(d:is_thinking())
            d:reset()
            assert.is_false(d:is_thinking())
            assert.is_nil(d:thinking_seat())
        end)
    end)

    describe("phase routing", function()
        local function run_routing(state, seat_kinds, choosers)
            local s = make_fake_session(state)
            local clock = fake_clock(0)
            local invoked
            local registry = {}
            for name, _ in pairs(choosers) do
                registry[name] = function(view, seat)
                    invoked = { name = name, seat = seat, view = view }
                    return choosers[name]
                end
            end
            local d = driver.new({
                choosers = registry,
                now_fn = clock.now,
                delay = 0,
            })
            d:tick(s, seat_kinds)
            return s, invoked, d
        end

        it("auction → choose_bid", function()
            local _, invoked = run_routing(
                { phase = "auction", turn = 2 },
                { "human", "bot", "bot" },
                { choose_bid = { kind = "pass" } }
            )
            assert.are.equal("choose_bid", invoked.name)
            assert.are.equal(2, invoked.seat)
        end)

        it("awaiting_redeal_decision → choose_redeal (seat from offer)", function()
            local _, invoked = run_routing({
                phase = "awaiting_redeal_decision",
                turn = nil,
                redeal_offer = { kind = "weak_hand_redeal", seat = 3, forced = false },
            }, { "human", "human", "bot" }, {
                choose_redeal = { kind = "decline_redeal" },
            })
            assert.are.equal("choose_redeal", invoked.name)
            assert.are.equal(3, invoked.seat)
        end)

        it("awaiting_bad_talon_decision → choose_bad_talon_redeal", function()
            local _, invoked = run_routing({
                phase = "awaiting_bad_talon_decision",
                turn = nil,
                bad_talon_offer = { declarer = 2, points = 4 },
            }, { "human", "bot", "human" }, {
                choose_bad_talon_redeal = { kind = "decline_bad_talon_redeal" },
            })
            assert.are.equal("choose_bad_talon_redeal", invoked.name)
            assert.are.equal(2, invoked.seat)
        end)

        it("awaiting_rebuy_decision → choose_rebuy (seat from current_turn)", function()
            local _, invoked = run_routing({
                phase = "awaiting_rebuy_decision",
                turn = 3,
                rebuy_offer = { seat = 3, contract = 240 },
            }, { "human", "human", "bot" }, {
                choose_rebuy = { kind = "decline_rebuy" },
            })
            assert.are.equal("choose_rebuy", invoked.name)
            assert.are.equal(3, invoked.seat)
        end)

        it("awaiting_write_off_decision → choose_write_off", function()
            local _, invoked = run_routing({
                phase = "awaiting_write_off_decision",
                turn = 2,
            }, { "human", "bot", "human" }, {
                choose_write_off = { kind = "accept_play" },
            })
            assert.are.equal("choose_write_off", invoked.name)
            assert.are.equal(2, invoked.seat)
        end)

        it("awaiting_pre_first_trick_marriages → choose_pre_first_trick_marriage", function()
            local _, invoked = run_routing({
                phase = "awaiting_pre_first_trick_marriages",
                turn = 2,
            }, { "human", "bot", "human" }, {
                choose_pre_first_trick_marriage = { kind = "skip_announce_marriage" },
            })
            assert.are.equal("choose_pre_first_trick_marriage", invoked.name)
        end)

        it("awaiting_forced_concession_decision → choose_forced_bid_concession", function()
            local _, invoked = run_routing({
                phase = "awaiting_forced_concession_decision",
                turn = nil,
                forced_concession_offer = { declarer = 2, bid = 100 },
            }, { "human", "bot", "human" }, {
                choose_forced_bid_concession = { kind = "decline_forced_bid" },
            })
            assert.are.equal("choose_forced_bid_concession", invoked.name)
            assert.are.equal(2, invoked.seat)
        end)

        it("talon (action substate) → choose_talon_action", function()
            local _, invoked = run_routing({
                phase = "talon",
                turn = 2,
                talon_substate = "action",
            }, { "human", "bot", "human" }, {
                choose_talon_action = { kind = "take_talon" },
            })
            assert.are.equal("choose_talon_action", invoked.name)
        end)

        it("talon (pass substate) → choose_talon_pass", function()
            local _, invoked = run_routing({
                phase = "talon",
                turn = 2,
                talon_substate = "pass",
            }, { "human", "bot", "human" }, {
                choose_talon_pass = { kind = "pass_talon", target = 1, card = "x" },
            })
            assert.are.equal("choose_talon_pass", invoked.name)
        end)

        it("talon (polish_pass substate) → choose_talon_pass", function()
            local _, invoked = run_routing({
                phase = "talon",
                turn = 2,
                talon_substate = "polish_pass",
            }, { "human", "bot", "human" }, {
                choose_talon_pass = { kind = "pass_polish_talon", target = 1, talon_index = 1 },
            })
            assert.are.equal("choose_talon_pass", invoked.name)
        end)

        it("talon (discard substate) → choose_talon_pass", function()
            local _, invoked = run_routing({
                phase = "talon",
                turn = 2,
                talon_substate = "discard",
            }, { "human", "bot", "human" }, {
                choose_talon_pass = { kind = "discard_talon", card = "x" },
            })
            assert.are.equal("choose_talon_pass", invoked.name)
        end)

        it("talon (raise substate) → choose_raise", function()
            local _, invoked = run_routing({
                phase = "talon",
                turn = 2,
                talon_substate = "raise",
            }, { "human", "bot", "human" }, {
                choose_raise = { kind = "skip_raise" },
            })
            assert.are.equal("choose_raise", invoked.name)
        end)

        it("tricks → choose_card (no marriage opportunity)", function()
            local _, invoked = run_routing({
                phase = "tricks",
                turn = 2,
                legal_cards = { [2] = { { suit = "hearts", rank = "9" } } },
            }, { "human", "bot", "human" }, {
                choose_card = { kind = "play", card = { suit = "hearts", rank = "9" } },
            })
            assert.are.equal("choose_card", invoked.name)
        end)

        it("tricks + on-lead marriage opportunity → choose_marriage", function()
            local _, invoked = run_routing({
                phase = "tricks",
                turn = 2,
                current_trick = { plays = {} },
                available_marriages = { [2] = { "hearts" } },
                config = {
                    players = { count = 3 },
                    marriages = { marriage_announcement_timing = "on_lead" },
                },
            }, { "human", "bot", "human" }, {
                choose_marriage = { kind = "skip_declare_marriage" },
            })
            assert.are.equal("choose_marriage", invoked.name)
            assert.are.equal(2, invoked.seat)
        end)

        it("tricks + non-empty trick → choose_card (predicate guards)", function()
            local _, invoked = run_routing({
                phase = "tricks",
                turn = 2,
                current_trick = { plays = { { card = "x" } } },
                available_marriages = { [2] = { "hearts" } },
                config = {
                    players = { count = 3 },
                    marriages = { marriage_announcement_timing = "on_lead" },
                },
                legal_cards = { [2] = { { suit = "hearts", rank = "9" } } },
            }, { "human", "bot", "human" }, {
                choose_card = { kind = "play", card = { suit = "hearts", rank = "9" } },
            })
            assert.are.equal("choose_card", invoked.name)
        end)

        it("tricks + pre_first_trick timing → choose_card (no in-trick declare)", function()
            local _, invoked = run_routing({
                phase = "tricks",
                turn = 2,
                current_trick = { plays = {} },
                available_marriages = { [2] = { "hearts" } },
                config = {
                    players = { count = 3 },
                    marriages = { marriage_announcement_timing = "pre_first_trick" },
                },
                legal_cards = { [2] = { { suit = "hearts", rank = "9" } } },
            }, { "human", "bot", "human" }, {
                choose_card = { kind = "play", card = { suit = "hearts", rank = "9" } },
            })
            assert.are.equal("choose_card", invoked.name)
        end)

        it("deal_done → choose_next_deal", function()
            local _, invoked = run_routing({
                phase = "deal_done",
                turn = 2,
            }, { "human", "bot", "human" }, {
                choose_next_deal = { kind = "start_next_deal" },
            })
            assert.are.equal("choose_next_deal", invoked.name)
        end)

        it("cut → choose_cut_deck (seat from current_turn)", function()
            local _, invoked = run_routing({
                phase = "cut",
                turn = 2,
            }, { "human", "bot", "human" }, {
                choose_cut_deck = { kind = "cut_deck" },
            })
            assert.are.equal("choose_cut_deck", invoked.name)
            assert.are.equal(2, invoked.seat)
        end)
    end)

    describe("action → mutator dispatch", function()
        local function dispatch(action, state)
            state = state or { phase = "auction", turn = 2 }
            local s = make_fake_session(state)
            local clock = fake_clock(0)
            local d = driver.new({
                choosers = setmetatable({}, {
                    __index = function()
                        return function()
                            return action
                        end
                    end,
                }),
                now_fn = clock.now,
                delay = 0,
            })
            d:tick(s, { "human", "bot", "bot" })
            clock.advance(0.001)
            d:tick(s, { "human", "bot", "bot" })
            return s._calls
        end

        it("bid → session:bid(seat, amount)", function()
            local calls = dispatch({ kind = "bid", amount = 100 })
            assert.are.equal("bid", calls[1].method)
            assert.are.equal(2, calls[1].args[1])
            assert.are.equal(100, calls[1].args[2])
        end)

        it("pass → session:pass(seat)", function()
            local calls = dispatch({ kind = "pass" })
            assert.are.equal("pass", calls[1].method)
            assert.are.equal(2, calls[1].args[1])
        end)

        it("declare_blind → session:declare_blind(seat)", function()
            local calls = dispatch({ kind = "declare_blind" })
            assert.are.equal("declare_blind", calls[1].method)
            assert.are.equal(2, calls[1].args[1])
        end)

        it("play → session:play(seat, card)", function()
            local card = { suit = "hearts", rank = "A" }
            local calls = dispatch({ kind = "play", card = card }, {
                phase = "tricks",
                turn = 2,
            })
            assert.are.equal("play", calls[1].method)
            assert.are.equal(2, calls[1].args[1])
            assert.are.equal(card, calls[1].args[2])
        end)

        it("pass_talon → session:pass_talon(target, card)", function()
            local card = { suit = "hearts", rank = "A" }
            local calls = dispatch(
                { kind = "pass_talon", target = 1, card = card },
                { phase = "talon", turn = 2, talon_substate = "pass" }
            )
            assert.are.equal("pass_talon", calls[1].method)
            assert.are.equal(1, calls[1].args[1])
            assert.are.equal(card, calls[1].args[2])
        end)

        it("pass_polish_talon → session:pass_polish_talon(target, talon_index)", function()
            local calls = dispatch(
                { kind = "pass_polish_talon", target = 3, talon_index = 1 },
                { phase = "talon", turn = 2, talon_substate = "polish_pass" }
            )
            assert.are.equal("pass_polish_talon", calls[1].method)
            assert.are.equal(3, calls[1].args[1])
            assert.are.equal(1, calls[1].args[2])
        end)

        it("discard_talon → session:discard_talon(card)", function()
            local card = { suit = "hearts", rank = "9" }
            local calls = dispatch(
                { kind = "discard_talon", card = card },
                { phase = "talon", turn = 2, talon_substate = "discard" }
            )
            assert.are.equal("discard_talon", calls[1].method)
            assert.are.equal(card, calls[1].args[1])
        end)

        it("raise → session:raise(amount)", function()
            local calls = dispatch(
                { kind = "raise", amount = 110 },
                { phase = "talon", turn = 2, talon_substate = "raise" }
            )
            assert.are.equal("raise", calls[1].method)
            assert.are.equal(110, calls[1].args[1])
        end)

        it("skip_raise → session:skip_raise()", function()
            local calls = dispatch(
                { kind = "skip_raise" },
                { phase = "talon", turn = 2, talon_substate = "raise" }
            )
            assert.are.equal("skip_raise", calls[1].method)
        end)

        it("take_talon → session:take_talon()", function()
            local calls = dispatch(
                { kind = "take_talon" },
                { phase = "talon", turn = 2, talon_substate = "action" }
            )
            assert.are.equal("take_talon", calls[1].method)
        end)

        it("concede_deal → session:concede_deal()", function()
            local calls = dispatch(
                { kind = "concede_deal" },
                { phase = "talon", turn = 2, talon_substate = "action" }
            )
            assert.are.equal("concede_deal", calls[1].method)
        end)

        it("buyback_hand → session:buyback_hand()", function()
            local calls = dispatch(
                { kind = "buyback_hand" },
                { phase = "talon", turn = 2, talon_substate = "action" }
            )
            assert.are.equal("buyback_hand", calls[1].method)
        end)

        it("decline_redeal → session:decline_redeal()", function()
            local calls = dispatch({ kind = "decline_redeal" }, {
                phase = "awaiting_redeal_decision",
                redeal_offer = { kind = "weak_hand_redeal", seat = 2, forced = false },
            })
            assert.are.equal("decline_redeal", calls[1].method)
        end)

        it("accept_redeal → session:accept_redeal()", function()
            local calls = dispatch({ kind = "accept_redeal" }, {
                phase = "awaiting_redeal_decision",
                redeal_offer = { kind = "weak_hand_redeal", seat = 2, forced = false },
            })
            assert.are.equal("accept_redeal", calls[1].method)
        end)

        it("decline_bad_talon_redeal → session:decline_bad_talon_redeal()", function()
            local calls = dispatch({ kind = "decline_bad_talon_redeal" }, {
                phase = "awaiting_bad_talon_decision",
                bad_talon_offer = { declarer = 2 },
            })
            assert.are.equal("decline_bad_talon_redeal", calls[1].method)
        end)

        it("decline_rebuy → session:decline_rebuy(seat)", function()
            local calls = dispatch({ kind = "decline_rebuy" }, {
                phase = "awaiting_rebuy_decision",
                turn = 2,
                rebuy_offer = { seat = 2 },
            })
            assert.are.equal("decline_rebuy", calls[1].method)
            assert.are.equal(2, calls[1].args[1])
        end)

        it("accept_play → session:accept_play()", function()
            local calls = dispatch({ kind = "accept_play" }, {
                phase = "awaiting_write_off_decision",
                turn = 2,
            })
            assert.are.equal("accept_play", calls[1].method)
        end)

        it("write_off → session:write_off()", function()
            local calls = dispatch({ kind = "write_off" }, {
                phase = "awaiting_write_off_decision",
                turn = 2,
            })
            assert.are.equal("write_off", calls[1].method)
        end)

        it("decline_forced_bid → session:decline_forced_bid()", function()
            local calls = dispatch({ kind = "decline_forced_bid" }, {
                phase = "awaiting_forced_concession_decision",
                forced_concession_offer = { declarer = 2 },
            })
            assert.are.equal("decline_forced_bid", calls[1].method)
        end)

        it("skip_announce_marriage → session:skip_pre_first_trick_marriage(seat)", function()
            local calls = dispatch({ kind = "skip_announce_marriage" }, {
                phase = "awaiting_pre_first_trick_marriages",
                turn = 2,
            })
            assert.are.equal("skip_pre_first_trick_marriage", calls[1].method)
            assert.are.equal(2, calls[1].args[1])
        end)

        it("start_next_deal → session:start_next_deal()", function()
            local calls = dispatch({ kind = "start_next_deal" }, {
                phase = "deal_done",
                turn = 2,
            })
            assert.are.equal("start_next_deal", calls[1].method)
        end)

        it("skip_contra → no-op (driver swallows the descriptor)", function()
            local calls = dispatch({ kind = "skip_contra" }, {
                phase = "auction",
                turn = 2,
            })
            assert.are.equal(0, #calls)
        end)

        it("declare_marriage → session:declare_marriage(seat, suit)", function()
            local calls = dispatch({ kind = "declare_marriage", suit = "hearts" }, {
                phase = "tricks",
                turn = 2,
                current_trick = { plays = {} },
                available_marriages = { [2] = { "hearts" } },
                config = {
                    players = { count = 3 },
                    marriages = { marriage_announcement_timing = "on_lead" },
                },
            })
            assert.are.equal("declare_marriage", calls[1].method)
            assert.are.equal(2, calls[1].args[1])
            assert.are.equal("hearts", calls[1].args[2])
        end)

        it("skip_declare_marriage → no-op (driver swallows the descriptor)", function()
            local calls = dispatch({ kind = "skip_declare_marriage" }, {
                phase = "tricks",
                turn = 2,
                current_trick = { plays = {} },
                available_marriages = { [2] = { "hearts" } },
                config = {
                    players = { count = 3 },
                    marriages = { marriage_announcement_timing = "on_lead" },
                },
            })
            assert.are.equal(0, #calls)
        end)

        it("cut_deck → session:cut_deck()", function()
            local calls = dispatch({ kind = "cut_deck" }, {
                phase = "cut",
                turn = 2,
            })
            assert.are.equal("cut_deck", calls[1].method)
            assert.are.equal(0, #calls[1].args)
        end)
    end)

    describe("marriage skip latch", function()
        local function make_marriage_state()
            return {
                phase = "tricks",
                turn = 2,
                current_trick = { plays = {} },
                available_marriages = { [2] = { "hearts" } },
                config = {
                    players = { count = 3 },
                    marriages = { marriage_announcement_timing = "on_lead" },
                },
                legal_cards = { [2] = { { suit = "hearts", rank = "9" } } },
            }
        end

        local function make_routing_driver(_state, clock)
            local invoked = {}
            local d = driver.new({
                choosers = {
                    choose_marriage = function(_, seat)
                        invoked[#invoked + 1] = { name = "choose_marriage", seat = seat }
                        return { kind = "skip_declare_marriage" }
                    end,
                    choose_card = function(_, seat)
                        invoked[#invoked + 1] = { name = "choose_card", seat = seat }
                        return { kind = "play", card = { suit = "hearts", rank = "9" } }
                    end,
                },
                now_fn = clock.now,
                delay = 0.5,
            })
            return d, invoked
        end

        it("does not loop back into choose_marriage after a skip applies", function()
            local s = make_fake_session(make_marriage_state())
            local clock = fake_clock(0)
            local d, invoked = make_routing_driver(s, clock)
            -- Tick 1: routes to choose_marriage; chooser returns skip; pending scheduled.
            d:tick(s, { "human", "bot", "human" })
            assert.are.equal(1, #invoked)
            assert.are.equal("choose_marriage", invoked[1].name)
            -- Fire pending — applies skip_declare_marriage (noop) and sets the latch.
            clock.advance(1.0)
            d:tick(s, { "human", "bot", "human" })
            assert.are.equal(0, #s._calls) -- skip is noop on the engine
            -- Tick 3: latch protects; routes to choose_card despite the still-
            -- available marriage.
            d:tick(s, { "human", "bot", "human" })
            assert.are.equal(2, #invoked)
            assert.are.equal("choose_card", invoked[2].name)
        end)

        it("clears the latch on a successful declare_marriage apply", function()
            -- Defensive branch: even if a stale latch is set when a
            -- declare_marriage descriptor fires, the latch must clear so
            -- the next on-lead opportunity (e.g. the second K+Q pair) is
            -- not silently suppressed.
            local s = make_fake_session(make_marriage_state())
            local clock = fake_clock(0)
            local d = driver.new({ now_fn = clock.now })
            d._marriage_skipped = { seat = 2 }
            d._pending = {
                seat = 2,
                action = { kind = "declare_marriage", suit = "hearts" },
                chooser_name = "choose_marriage",
                fire_at = 0,
            }
            d:tick(s, { "human", "bot", "human" })
            assert.is_nil(d._marriage_skipped)
            assert.are.equal("declare_marriage", s._calls[1].method)
            assert.are.equal("hearts", s._calls[1].args[2])
        end)

        it("clears the latch when the trick has plays (player advanced)", function()
            local state = make_marriage_state()
            -- Trick already has plays — predicate returns false, latch is
            -- pruned by maintain.
            state.current_trick = { plays = { { card = "x" } } }
            local s = make_fake_session(state)
            local clock = fake_clock(0)
            local d, invoked = make_routing_driver(s, clock)
            d._marriage_skipped = { seat = 2 }
            d:tick(s, { "human", "bot", "human" })
            assert.is_nil(d._marriage_skipped)
            assert.are.equal("choose_card", invoked[1].name)
        end)

        it("clears the latch when the responsible seat changes", function()
            local state = make_marriage_state()
            state.turn = 3
            state.available_marriages = { [3] = { "hearts" } }
            state.legal_cards = { [3] = { { suit = "hearts", rank = "9" } } }
            local s = make_fake_session(state)
            local clock = fake_clock(0)
            local d = driver.new({
                choosers = {
                    choose_marriage = function()
                        return { kind = "skip_declare_marriage" }
                    end,
                    choose_card = function()
                        return { kind = "play", card = { suit = "hearts", rank = "9" } }
                    end,
                },
                now_fn = clock.now,
                delay = 0,
            })
            d._marriage_skipped = { seat = 2 }
            d:tick(s, { "human", "human", "bot" })
            assert.is_nil(d._marriage_skipped)
        end)

        it("reset() clears the latch", function()
            local clock = fake_clock(0)
            local d = driver.new({ now_fn = clock.now })
            d._marriage_skipped = { seat = 2 }
            d:reset()
            assert.is_nil(d._marriage_skipped)
        end)
    end)

    describe("error handling", function()
        it("errors when the chooser is missing for a routed phase", function()
            local s = make_fake_session({ phase = "auction", turn = 2 })
            local clock = fake_clock(0)
            local d = driver.new({ choosers = {}, now_fn = clock.now })
            assert.error_matches(function()
                d:tick(s, { "human", "bot", "bot" })
            end, "missing chooser")
        end)

        it("errors when the action descriptor has an unknown kind", function()
            local s = make_fake_session({ phase = "auction", turn = 2 })
            local clock = fake_clock(0)
            local d = driver.new({
                choosers = {
                    choose_bid = function()
                        return { kind = "totally_unknown" }
                    end,
                },
                now_fn = clock.now,
                delay = 0,
            })
            d:tick(s, { "human", "bot", "bot" })
            clock.advance(0.001)
            assert.error_matches(function()
                d:tick(s, { "human", "bot", "bot" })
            end, "unknown action kind")
        end)
    end)
end)
