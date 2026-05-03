-- Phase 3.6 marriage-variants integration coverage. Drives the session
-- through scripted scenarios where each `marriages.*` house rule
-- changes engine flow.

local Session = require("app.session")
local rule_config = require("core.rule_config")
local card = require("core.card")
local json = require("app.json")
local marriages_module = require("core.marriages")
local auction_module = require("core.auction")
local tricks_module = require("core.tricks")

local function c(suit, rank)
    return card.new(suit, rank)
end

-- Existing variant tests do not set up a captured-trick history before
-- declaring a marriage, so the canonical `trick_required = "on"` rule
-- would gate every assertion. The helper turns the gate off by default;
-- tests that target `trick_required` set it explicitly via `overrides`.
local function config_with_marriage_overrides(overrides)
    local blob = json.decode(rule_config.to_json(rule_config.canonical_russian))
    blob.marriages.trick_required = "off"
    overrides = overrides or {}
    for k, v in pairs(overrides) do
        blob.marriages[k] = v
    end
    return rule_config.new(blob)
end

-- A deterministic 24-card 3-player layout used by the multi-play
-- tests (drowned, half-marriage capture). Seat 2 is the declarer at
-- dealer = 1, holds the K-Q of hearts, and leads.
--   seat 1: diamonds A,K,Q,9,J;  clubs 9;     spades 9,J
--   seat 2: hearts  K,Q,10;      clubs K,Q,J; diamonds 10; spades 10
--   seat 3: hearts  A,9,J;       clubs A,10;  spades A,K,Q
-- Total 24 distinct cards covering every suit × rank pair.
local function full_deal_layout()
    return {
        {
            c("diamonds", "A"),
            c("diamonds", "K"),
            c("diamonds", "Q"),
            c("diamonds", "9"),
            c("diamonds", "J"),
            c("clubs", "9"),
            c("spades", "9"),
            c("spades", "J"),
        },
        {
            c("hearts", "K"),
            c("hearts", "Q"),
            c("hearts", "10"),
            c("clubs", "K"),
            c("clubs", "Q"),
            c("clubs", "J"),
            c("diamonds", "10"),
            c("spades", "10"),
        },
        {
            c("hearts", "A"),
            c("hearts", "9"),
            c("hearts", "J"),
            c("clubs", "A"),
            c("clubs", "10"),
            c("spades", "A"),
            c("spades", "K"),
            c("spades", "Q"),
        },
    }
end

-- Build a session positioned mid-tricks with the given hands and a
-- contracted declarer at seat `declarer`.
local function session_at_tricks(test_config, hands, opts)
    opts = opts or {}
    local dealer = opts.dealer or 1
    local declarer = opts.declarer or ((dealer % test_config.players.count) + 1)
    local pc = test_config.players.count
    local running_totals = opts.running_totals or {}
    for i = 1, pc do
        running_totals[i] = running_totals[i] or 0
    end

    local holdings = {}
    for seat = 1, pc do
        local suits = marriages_module.detect(hands[seat])
        local total = 0
        for _, suit in ipairs(suits) do
            total = total + (test_config.marriages.values[suit] or 0)
        end
        holdings[seat] = { marriage_total = total }
    end

    local auction = auction_module.new(test_config, dealer, {
        holdings = holdings,
        running_totals = running_totals,
    }).auction
    local forehand = (dealer % pc) + 1
    auction = auction_module.bid(auction, forehand, opts.bid or 100).auction
    for seat = 1, pc do
        if seat ~= forehand and auction.status == "in_progress" then
            local r = auction_module.pass(auction, seat)
            if r.ok then
                auction = r.auction
            end
        end
    end

    local marriages = marriages_module.new(test_config).marriages
    local tricks = tricks_module.new(test_config, hands, declarer, {
        dealer = dealer,
    }).tricks

    return Session.from_state({
        config = test_config,
        seed = opts.seed or 1,
        dealer = dealer,
        hands = hands,
        auction = auction,
        marriages = marriages,
        tricks = tricks,
        talon = {
            declarer = declarer,
            final_bid = opts.bid or 100,
            status = "done",
            hands = hands,
        },
        running_totals = running_totals,
        deal_index = 1,
    })
end

describe("app.session marriage variants", function()
    describe("trump_activation_timing = immediate", function()
        it("flips trump on the trick the K is led", function()
            local cfg = config_with_marriage_overrides({ trump_activation_timing = "immediate" })
            local s = session_at_tricks(cfg, full_deal_layout())
            assert.is_true(s:declare_marriage(2, "hearts").ok)
            assert.are.equal("hearts", s:trump())
        end)

        it("defers trump under default next_trick", function()
            local cfg = config_with_marriage_overrides({ trump_activation_timing = "next_trick" })
            local s = session_at_tricks(cfg, full_deal_layout())
            assert.is_true(s:declare_marriage(2, "hearts").ok)
            -- Trump on the active trick is still nil; the new trump
            -- is pending until the trick resolves.
            assert.is_nil(s:trump())
        end)
    end)

    describe("one_trump_per_deal = on", function()
        it("keeps trump unchanged on the second declaration", function()
            local cfg = config_with_marriage_overrides({
                one_trump_per_deal = "on",
                trump_activation_timing = "immediate",
            })
            local s = session_at_tricks(cfg, full_deal_layout())
            assert.is_true(s:declare_marriage(2, "hearts").ok)
            assert.are.equal("hearts", s:trump())
            -- The session must not flip trump on the second
            -- declaration — but only seat 2 holds clubs K+Q, and
            -- seat 2 already declared hearts. Trick must resolve
            -- before seat 2 can attempt the second declaration; for
            -- this unit test we directly call declare on the same
            -- (still empty) trick.
            assert.is_true(s:declare_marriage(2, "clubs").ok)
            assert.are.equal("hearts", s:trump())
            -- Bonus still posts (40 for spades... wait, we declared
            -- clubs which is 60).
            assert.are.equal(100 + 60, s:_marriages_state_for_test().bonuses[2])
        end)
    end)

    describe("ace_marriage", function()
        local function aces_layout()
            -- 24-card layout: seat 2 holds all four Aces.
            return {
                {
                    c("hearts", "K"),
                    c("hearts", "Q"),
                    c("hearts", "J"),
                    c("diamonds", "K"),
                    c("diamonds", "Q"),
                    c("diamonds", "J"),
                    c("clubs", "9"),
                    c("spades", "9"),
                },
                {
                    c("hearts", "A"),
                    c("diamonds", "A"),
                    c("clubs", "A"),
                    c("spades", "A"),
                    c("hearts", "10"),
                    c("diamonds", "10"),
                    c("clubs", "10"),
                    c("spades", "10"),
                },
                {
                    c("hearts", "9"),
                    c("diamonds", "9"),
                    c("clubs", "K"),
                    c("clubs", "Q"),
                    c("clubs", "J"),
                    c("spades", "K"),
                    c("spades", "Q"),
                    c("spades", "J"),
                },
            }
        end

        it("rejects declare_ace_marriage when ace_marriage is off", function()
            local cfg = config_with_marriage_overrides({ ace_marriage = "off" })
            local s = session_at_tricks(cfg, aces_layout())
            local r = s:declare_ace_marriage(2)
            assert.is_false(r.ok)
            assert.are.equal("ace_marriage_disabled", r.error.code)
        end)

        it("awards ace_marriage_value under 'on'", function()
            local cfg = config_with_marriage_overrides({
                ace_marriage = "on",
                ace_marriage_value = 250,
            })
            local s = session_at_tricks(cfg, aces_layout())
            assert.is_true(s:declare_ace_marriage(2).ok)
            assert.are.equal(250, s:_marriages_state_for_test().bonuses[2])
            assert.is_nil(s:trump())
            assert.is_nil(s:pending_ace_trump_seat())
        end)

        it("flips trump on the first Ace led under 'sets_trump'", function()
            local cfg = config_with_marriage_overrides({ ace_marriage = "sets_trump" })
            local s = session_at_tricks(cfg, aces_layout())
            assert.is_true(s:declare_ace_marriage(2).ok)
            assert.are.equal(2, s:pending_ace_trump_seat())
            assert.is_true(s:play(2, c("diamonds", "A")).ok)
            assert.is_nil(s:pending_ace_trump_seat())
            assert.are.equal("diamonds", s:trump())
        end)
    end)

    describe("marriage_announcement_timing", function()
        it("hand_announcement awards bonus without leading the K or Q", function()
            local cfg = config_with_marriage_overrides({
                marriage_announcement_timing = "hand_announcement",
            })
            local s = session_at_tricks(cfg, full_deal_layout())
            assert.is_true(s:announce_marriage(2, "hearts").ok)
            assert.are.equal(100, s:_marriages_state_for_test().bonuses[2])
        end)

        it("pre_first_trick blocks declare_marriage", function()
            local cfg = config_with_marriage_overrides({
                marriage_announcement_timing = "pre_first_trick",
            })
            local s = session_at_tricks(cfg, full_deal_layout())
            -- Pre-first-trick window opens automatically; declare via
            -- the standard path is rejected.
            local r = s:declare_marriage(2, "hearts")
            assert.is_false(r.ok)
            assert.are.equal("marriage_announcement_phase_closed", r.error.code)
        end)

        it("pre_first_trick exposes the announcement queue", function()
            local cfg = config_with_marriage_overrides({
                marriage_announcement_timing = "pre_first_trick",
            })
            local s = session_at_tricks(cfg, full_deal_layout())
            local state = s:pre_first_trick_announcement_state()
            assert.is_not_nil(state)
            -- full_deal_layout puts a K-Q in every seat (seat 1
            -- diamonds, seat 2 hearts/clubs, seat 3 spades). The
            -- queue order starts at the leader (seat 2) clockwise.
            assert.are.same({ 2, 3, 1 }, state.pending_seats)
            assert.are.equal(2, state.seat)
            assert.is_true(s:announce_marriage(2, "hearts").ok)
            assert.are.equal(3, s:pre_first_trick_announcement_state().seat)
            assert.is_true(s:skip_pre_first_trick_marriage(3).ok)
            assert.are.equal(1, s:pre_first_trick_announcement_state().seat)
            assert.is_true(s:skip_pre_first_trick_marriage(1).ok)
            assert.is_nil(s:pre_first_trick_announcement_state())
            assert.are.equal("tricks", s:current_phase())
        end)

        it("pre_first_trick supports skip", function()
            local cfg = config_with_marriage_overrides({
                marriage_announcement_timing = "pre_first_trick",
            })
            local s = session_at_tricks(cfg, full_deal_layout())
            assert.is_not_nil(s:pre_first_trick_announcement_state())
            assert.is_true(s:skip_pre_first_trick_marriage(2).ok)
            assert.is_true(s:skip_pre_first_trick_marriage(3).ok)
            assert.is_true(s:skip_pre_first_trick_marriage(1).ok)
            assert.is_nil(s:pre_first_trick_announcement_state())
            assert.are.equal(0, s:_marriages_state_for_test().bonuses[2])
        end)
    end)

    describe("trick_required = on", function()
        it("rejects a K-Q declaration before the seat has captured a trick", function()
            local cfg = config_with_marriage_overrides({
                trick_required = "on",
                trump_activation_timing = "immediate",
            })
            local s = session_at_tricks(cfg, full_deal_layout())
            local r = s:declare_marriage(2, "hearts")
            assert.is_false(r.ok)
            assert.are.equal("trick_required_not_met", r.error.code)
        end)

        it("accepts a K-Q declaration once the seat has captured a trick", function()
            local cfg = config_with_marriage_overrides({
                trick_required = "on",
                trump_activation_timing = "immediate",
            })
            -- Seat 3 captures trick 1 (hearts.A beats hearts.10), then
            -- leads trick 2 holding spades K and Q. Spades marriage
            -- now passes the trick gate.
            local s = session_at_tricks(cfg, full_deal_layout())
            assert.is_true(s:play(2, c("hearts", "10")).ok)
            assert.is_true(s:play(3, c("hearts", "A")).ok)
            assert.is_true(s:play(1, c("diamonds", "9")).ok)
            local r = s:declare_marriage(3, "spades")
            assert.is_true(r.ok)
        end)

        it("rejects every seat in the pre_first_trick window", function()
            local cfg = config_with_marriage_overrides({
                trick_required = "on",
                marriage_announcement_timing = "pre_first_trick",
            })
            -- Seat 2 holds the hearts K-Q; in the pre_first_trick
            -- window every seat has zero captured tricks, so the
            -- announcement returns trick_required_not_met. The seat
            -- can still skip its turn in the queue.
            local s = session_at_tricks(cfg, full_deal_layout())
            local r = s:announce_marriage(2, "hearts")
            assert.is_false(r.ok)
            assert.are.equal("trick_required_not_met", r.error.code)
        end)
    end)

    describe("drowned_marriage = retroactive_cancel", function()
        it("cancels the bonus when an opponent captures the K", function()
            local cfg = config_with_marriage_overrides({
                drowned_marriage = "retroactive_cancel",
                trump_activation_timing = "immediate",
            })
            local s = session_at_tricks(cfg, full_deal_layout())
            assert.is_true(s:declare_marriage(2, "hearts").ok)
            -- Seat 2 leads K of hearts, seat 3 captures with A,
            -- seat 1 has no hearts so discards a diamond.
            assert.is_true(s:play(2, c("hearts", "K")).ok)
            assert.is_true(s:play(3, c("hearts", "A")).ok)
            assert.is_true(s:play(1, c("diamonds", "9")).ok)
            -- Seat 3 (non-declarer) captured the K of hearts; the
            -- marriage bonus is reversed.
            assert.are.equal(0, s:_marriages_state_for_test().bonuses[2])
            local log = s:drowned_marriage_log()
            assert.is_true(#log >= 1)
            assert.are.equal("hearts", log[1].suit)
        end)
    end)

    describe("half_marriage_capture_bonus = on", function()
        it("awards the bonus when a non-declarer captures both K and Q", function()
            local cfg = config_with_marriage_overrides({
                half_marriage_capture_bonus = "on",
                half_marriage_capture_bonus_value = 25,
            })
            -- Use a deck where seat 3 captures both K and Q of clubs.
            -- 24-card layout:
            --   seat 1: diamonds 10,A,K,Q,9; spades 9,K,Q
            --   seat 2: clubs K,Q,J,9;       hearts 9,J,Q,10
            --   seat 3: clubs A,10;          hearts A,K;
            --                                 spades A,J,10; diamonds J
            local hands = {
                {
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                    c("diamonds", "K"),
                    c("diamonds", "Q"),
                    c("diamonds", "9"),
                    c("spades", "9"),
                    c("spades", "K"),
                    c("spades", "Q"),
                },
                {
                    c("clubs", "K"),
                    c("clubs", "Q"),
                    c("clubs", "J"),
                    c("clubs", "9"),
                    c("hearts", "9"),
                    c("hearts", "J"),
                    c("hearts", "Q"),
                    c("hearts", "10"),
                },
                {
                    c("clubs", "A"),
                    c("clubs", "10"),
                    c("hearts", "A"),
                    c("hearts", "K"),
                    c("spades", "A"),
                    c("spades", "J"),
                    c("spades", "10"),
                    c("diamonds", "J"),
                },
            }
            local s = session_at_tricks(cfg, hands)
            -- Trick 1: seat 2 leads clubs Q. seat 3 plays clubs A.
            -- seat 1 has no clubs; no trump declared yet, must_trump
            -- can't fire — discard freely.
            assert.is_true(s:play(2, c("clubs", "Q")).ok)
            assert.is_true(s:play(3, c("clubs", "A")).ok)
            assert.is_true(s:play(1, c("diamonds", "9")).ok)
            -- Trick 2: seat 3 leads clubs 10. seat 1 has no clubs,
            -- discards. seat 2 plays clubs K (forced follow). seat 3
            -- captures both K and Q of clubs across these tricks.
            assert.is_true(s:play(3, c("clubs", "10")).ok)
            assert.is_true(s:play(1, c("spades", "9")).ok)
            assert.is_true(s:play(2, c("clubs", "K")).ok)
            local bonuses = s:_half_marriage_capture_bonuses_for_test()
            assert.are.equal(25, bonuses[3])
        end)
    end)
end)
