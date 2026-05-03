-- Phase 3.7 dark-game stick doubling integration coverage. The book
-- (line 71) defines: "In a dark game, the received stick may be
-- doubled." The toggle `penalties.zero_tricks_dark_game_doubled`
-- gates this behaviour; activation requires
-- `penalties.zero_tricks ~= "off"` AND a blind opening that won the
-- auction.
--
-- This file pins the wiring through Session.score_deal_and_advance.
-- The base zero-tricks counter logic is covered by
-- session_penalties_spec; the engine-level math is in
-- tests/spec/core/scoring_spec.

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

local function config_with_overrides(overrides)
    local blob = json.decode(rule_config.to_json(rule_config.canonical_russian))
    overrides = overrides or {}
    for section, fields in pairs(overrides) do
        blob[section] = blob[section] or {}
        for k, v in pairs(fields) do
            blob[section][k] = v
        end
    end
    return rule_config.new(blob)
end

local function sweep_layout()
    return {
        {
            c("hearts", "9"),
            c("hearts", "J"),
            c("diamonds", "9"),
            c("diamonds", "J"),
            c("clubs", "9"),
            c("clubs", "J"),
            c("spades", "9"),
            c("spades", "J"),
        },
        {
            c("hearts", "A"),
            c("hearts", "10"),
            c("diamonds", "A"),
            c("diamonds", "10"),
            c("clubs", "A"),
            c("clubs", "10"),
            c("spades", "A"),
            c("spades", "10"),
        },
        {
            c("hearts", "Q"),
            c("hearts", "K"),
            c("diamonds", "Q"),
            c("diamonds", "K"),
            c("clubs", "Q"),
            c("clubs", "K"),
            c("spades", "Q"),
            c("spades", "K"),
        },
    }
end

local function seat2_sweeps_sequence()
    return {
        { { 2, c("hearts", "A") }, { 3, c("hearts", "Q") }, { 1, c("hearts", "9") } },
        { { 2, c("hearts", "10") }, { 3, c("hearts", "K") }, { 1, c("hearts", "J") } },
        { { 2, c("diamonds", "A") }, { 3, c("diamonds", "K") }, { 1, c("diamonds", "9") } },
        { { 2, c("diamonds", "10") }, { 3, c("diamonds", "Q") }, { 1, c("diamonds", "J") } },
        { { 2, c("clubs", "A") }, { 3, c("clubs", "K") }, { 1, c("clubs", "9") } },
        { { 2, c("clubs", "10") }, { 3, c("clubs", "Q") }, { 1, c("clubs", "J") } },
        { { 2, c("spades", "A") }, { 3, c("spades", "K") }, { 1, c("spades", "9") } },
        { { 2, c("spades", "10") }, { 3, c("spades", "Q") }, { 1, c("spades", "J") } },
    }
end

-- Build a session in tricks phase with the auction's blind_at_win
-- forced to the requested value. We bypass the auction module
-- (which would require driving the full bidding flow) by
-- instantiating an auction record directly with the desired final
-- state.
local function session_at_tricks(test_config, hands, opts)
    opts = opts or {}
    local dealer = opts.dealer or 1
    local pc = test_config.players.count
    local declarer = opts.declarer or ((dealer % pc) + 1)
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
    -- Force the blind_at_win flag to the requested value.
    if opts.blind_at_win == true then
        auction.blind_at_win = true
    elseif opts.blind_at_win == false then
        auction.blind_at_win = false
    end

    local marriages = marriages_module.new(test_config).marriages
    local tricks = tricks_module.new(test_config, hands, declarer, {
        dealer = dealer,
        declarer = declarer,
    }).tricks

    local from = {
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
        deal_index = opts.deal_index or 1,
    }
    return Session.from_state(from)
end

local function play_sequence(s, sequence)
    for _, trick in ipairs(sequence) do
        for _, p in ipairs(trick) do
            local r = s:play(p[1], p[2])
            assert(r.ok, r.error and r.error.code or "?")
        end
    end
end

describe("app.session zero_tricks dark-game doubling", function()
    describe("with the toggle on AND a blind winning bid", function()
        it("doubles the bolt — zero-trick seats earn 2 each", function()
            local cfg = config_with_overrides({
                penalties = {
                    zero_tricks = "any_three",
                    zero_tricks_dark_game_doubled = "on",
                },
            })
            local s = session_at_tricks(cfg, sweep_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
                blind_at_win = true,
            })
            play_sequence(s, seat2_sweeps_sequence())
            -- Seats 1 and 3 took zero tricks; under dark-game doubling
            -- each earns 2 instead of 1.
            assert.are.same({ 2, 0, 2 }, s:zero_tricks_bolts())
        end)
    end)

    describe("with the toggle on but NO blind winning bid", function()
        it("falls back to a single bolt per zero-trick seat", function()
            local cfg = config_with_overrides({
                penalties = {
                    zero_tricks = "any_three",
                    zero_tricks_dark_game_doubled = "on",
                },
            })
            local s = session_at_tricks(cfg, sweep_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
                blind_at_win = false,
            })
            play_sequence(s, seat2_sweeps_sequence())
            assert.are.same({ 1, 0, 1 }, s:zero_tricks_bolts())
        end)
    end)

    describe("with the toggle off and a blind winning bid", function()
        it("does NOT double — single bolt per zero-trick seat", function()
            local cfg = config_with_overrides({
                penalties = {
                    zero_tricks = "any_three",
                    zero_tricks_dark_game_doubled = "off",
                },
            })
            local s = session_at_tricks(cfg, sweep_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
                blind_at_win = true,
            })
            play_sequence(s, seat2_sweeps_sequence())
            assert.are.same({ 1, 0, 1 }, s:zero_tricks_bolts())
        end)
    end)

    describe("stacking with golden_deal_doubled", function()
        it("caps doubling at +2 per zero-trick deal even when both triggers fire", function()
            local cfg = config_with_overrides({
                penalties = {
                    zero_tricks = "any_three",
                    zero_tricks_golden_deal_doubled = "on",
                    zero_tricks_dark_game_doubled = "on",
                },
            })
            local s = session_at_tricks(cfg, sweep_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
                blind_at_win = true,
            })
            -- Force the deal into a golden-deal context so both
            -- doubling triggers are active.
            s._in_golden_deal = true
            play_sequence(s, seat2_sweeps_sequence())
            -- Book wording is "doubled" per condition, not
            -- multiplied — both trigger together still yields +2.
            assert.are.same({ 2, 0, 2 }, s:zero_tricks_bolts())
        end)
    end)
end)
