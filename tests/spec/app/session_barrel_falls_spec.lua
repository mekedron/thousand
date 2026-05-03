-- Phase 3.7 barrel-fall counter integration coverage. The book
-- (line 79) frames "Reset to zero" as one of two events: a dump
-- truck (±555 reset, already covered) AND "if a player sat on the
-- barrel 3 times and then fell off it." The toggle
-- `barrel.fall_count_resets_to_zero` activates the latter; the
-- third-fall threshold is hard-coded at 3 per the book.
--
-- Engine math is in tests/spec/core/scoring_spec; this file pins the
-- Session-level wiring (counter init / writeback / persistence /
-- deal_done payload).

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

-- Seat 2 sweeps. Seat 1 = 9s+Js; seat 3 = Ks+Qs; seat 2 = As+10s.
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

-- Construct a tricks-phase session with the requested running
-- totals AND barrel state. The barrel state is what makes
-- advance_game treat seat 1 as on-barrel during the deal.
local function session_at_tricks_on_barrel(opts)
    opts = opts or {}
    local cfg = opts.config
    local dealer = opts.dealer or 1
    local pc = cfg.players.count
    local declarer = opts.declarer or 2
    local bid = opts.bid or 100
    local hands = sweep_layout()

    local holdings = {}
    for seat = 1, pc do
        local suits = marriages_module.detect(hands[seat])
        local total = 0
        for _, suit in ipairs(suits) do
            total = total + (cfg.marriages.values[suit] or 0)
        end
        holdings[seat] = { marriage_total = total }
    end

    local auction = auction_module.new(cfg, dealer, {
        holdings = holdings,
        running_totals = opts.running_totals or { 880, 0, 0 },
    }).auction
    local forehand = (dealer % pc) + 1
    auction = auction_module.bid(auction, forehand, bid).auction
    for seat = 1, pc do
        if seat ~= forehand and auction.status == "in_progress" then
            local r = auction_module.pass(auction, seat)
            if r.ok then
                auction = r.auction
            end
        end
    end

    local marriages = marriages_module.new(cfg).marriages
    local tricks = tricks_module.new(cfg, hands, declarer, {
        dealer = dealer,
        declarer = declarer,
    }).tricks

    return Session.from_state({
        config = cfg,
        seed = opts.seed or 1,
        dealer = dealer,
        hands = hands,
        auction = auction,
        marriages = marriages,
        tricks = tricks,
        talon = {
            declarer = declarer,
            final_bid = bid,
            status = "done",
            hands = hands,
        },
        running_totals = opts.running_totals or { 880, 0, 0 },
        barrel_state = opts.barrel_state or {
            { on_barrel = true, mounted_on_deal = 1, deals_remaining = 1 },
            { on_barrel = false },
            { on_barrel = false },
        },
        deal_index = opts.deal_index or 4,
        barrel_fall_counts = opts.barrel_fall_counts,
    })
end

local function play_sequence(s, sequence)
    for _, trick in ipairs(sequence) do
        for _, p in ipairs(trick) do
            local r = s:play(p[1], p[2])
            assert(r.ok, r.error and r.error.code or "?")
        end
    end
end

describe("app.session barrel-fall counter", function()
    describe("initial state", function()
        it("starts with zeroed barrel-fall counters per seat", function()
            local s = Session.new({ seed = 7 })
            assert.are.same({ 0, 0, 0 }, s:barrel_fall_counts())
        end)

        it("returns counter copies, never the live array", function()
            local s = Session.new({ seed = 7 })
            local view = s:barrel_fall_counts()
            view[1] = 999
            assert.are.equal(0, s:barrel_fall_counts()[1])
        end)
    end)

    describe("counter increments on a barrel fall-off", function()
        it("under fall_count_resets_to_zero = 'off' (toggle inactive)", function()
            local cfg = config_with_overrides({})
            -- Seat 1 is on barrel (mounted_on_deal=1, deals_remaining=1).
            -- Seat 2 sweeps for 120 → seat 1 gets 0 → falls off.
            local s = session_at_tricks_on_barrel({ config = cfg })
            play_sequence(s, seat2_sweeps_sequence())
            assert.are.same({ 1, 0, 0 }, s:barrel_fall_counts())
            -- Standard fall-off behaviour: running total 760 (= 880 - 120).
            assert.are.equal(760, s._running_totals[1])
        end)

        it("under fall_count_resets_to_zero = 'on' for the first fall", function()
            local cfg = config_with_overrides({
                barrel = { fall_count_resets_to_zero = "on" },
            })
            local s = session_at_tricks_on_barrel({ config = cfg })
            play_sequence(s, seat2_sweeps_sequence())
            assert.are.same({ 1, 0, 0 }, s:barrel_fall_counts())
            assert.are.equal(760, s._running_totals[1])
            local dd = s:deal_done()
            assert.is_table(dd)
            assert.is_true(dd.barrel_fall_events[1])
            assert.is_false(dd.barrel_fall_resets[1])
        end)
    end)

    describe("third-fall reset zeroes the running total and counter", function()
        it("when seat 1 falls for the third time", function()
            local cfg = config_with_overrides({
                barrel = { fall_count_resets_to_zero = "on" },
            })
            local s = session_at_tricks_on_barrel({
                config = cfg,
                barrel_fall_counts = { 2, 0, 0 },
            })
            play_sequence(s, seat2_sweeps_sequence())
            -- Third fall: running total → 0; counter → 0.
            assert.are.equal(0, s._running_totals[1])
            assert.are.same({ 0, 0, 0 }, s:barrel_fall_counts())
            local dd = s:deal_done()
            assert.is_true(dd.barrel_fall_resets[1])
        end)
    end)

    describe("multi-seat independence", function()
        it("each seat's counter advances only when that seat's unit falls", function()
            local cfg = config_with_overrides({
                barrel = { fall_count_resets_to_zero = "on" },
            })
            local s = session_at_tricks_on_barrel({
                config = cfg,
                barrel_fall_counts = { 1, 2, 0 },
            })
            play_sequence(s, seat2_sweeps_sequence())
            -- Only seat 1's unit falls; seats 2 and 3 unchanged.
            assert.are.equal(2, s:barrel_fall_counts()[1])
            assert.are.equal(2, s:barrel_fall_counts()[2])
            assert.are.equal(0, s:barrel_fall_counts()[3])
        end)
    end)

    describe("auto-save round trip", function()
        it("persists a non-zero counter across serialize/deserialize", function()
            local cfg = config_with_overrides({})
            local s = session_at_tricks_on_barrel({
                config = cfg,
                barrel_fall_counts = { 1, 0, 2 },
            })
            local auto_save = require("core.auto_save")
            local blob = auto_save.serialize(s)
            local round = auto_save.deserialize(blob)
            local s2 = Session.from_state(round)
            assert.are.same({ 1, 0, 2 }, s2:barrel_fall_counts())
        end)
    end)
end)
