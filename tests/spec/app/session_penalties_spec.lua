-- Phase 3.6 penalty house-rule integration coverage. Mirrors
-- session_scoring_variants_spec / session_trick_play_variants_spec:
-- per-toggle describes, deterministic 24-card hands, and an 8-trick
-- play sequence. The engine math is exhaustively pinned in
-- tests/spec/core/scoring_spec — these tests focus on the wiring
-- between session, the per-game bolt / cross counters, the
-- record_penalty_violation API, and the deal_done payload.

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

-- Seat 2 holds all winners (Aces + 10s) and captures every trick.
-- Seat 1 holds Js + 9s; seat 3 holds Ks + Qs. Under the default
-- "seat 2 leads each trick" sequence, seats 1 and 3 take zero
-- tricks — the canonical bolt-test setup.
local function bolt_layout()
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

-- Sequence where seat 2 wins every trick and leads next, so seats 1
-- and 3 take zero tricks. Seat 2 captures all 120 deck points. Used
-- when declarer = seat 2 (declarer leads first).
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

-- Sequence where seat 1 leads each trick (the declarer-loses path).
-- Seat 2 still wins every trick because they hold every Ace and 10;
-- seat 2 leads from trick 2 onward. Use when declarer = seat 1.
local function seat1_leads_then_seat2_sweeps_sequence()
    return {
        { { 1, c("hearts", "9") }, { 2, c("hearts", "A") }, { 3, c("hearts", "Q") } },
        { { 2, c("hearts", "10") }, { 3, c("hearts", "K") }, { 1, c("hearts", "J") } },
        { { 2, c("diamonds", "A") }, { 3, c("diamonds", "K") }, { 1, c("diamonds", "9") } },
        { { 2, c("diamonds", "10") }, { 3, c("diamonds", "Q") }, { 1, c("diamonds", "J") } },
        { { 2, c("clubs", "A") }, { 3, c("clubs", "K") }, { 1, c("clubs", "9") } },
        { { 2, c("clubs", "10") }, { 3, c("clubs", "Q") }, { 1, c("clubs", "J") } },
        { { 2, c("spades", "A") }, { 3, c("spades", "K") }, { 1, c("spades", "9") } },
        { { 2, c("spades", "10") }, { 3, c("spades", "Q") }, { 1, c("spades", "J") } },
    }
end

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
    if opts.zero_tricks_bolts then
        from.zero_tricks_bolts = opts.zero_tricks_bolts
    end
    if opts.cross_count then
        from.cross_count = opts.cross_count
    end
    if opts.in_golden_deal then
        from.in_golden_deal = true
    end
    return Session.from_state(from)
end

local function play_sequence(s, sequence)
    for ti, trick in ipairs(sequence) do
        for _, p in ipairs(trick) do
            local r = s:play(p[1], p[2])
            assert(
                r.ok,
                "trick "
                    .. ti
                    .. ": seat "
                    .. p[1]
                    .. " "
                    .. p[2].suit
                    .. " "
                    .. p[2].rank
                    .. " -> "
                    .. (r.error and r.error.code or "?")
            )
        end
    end
end

describe("app.session penalty house rules", function()
    describe("initial state", function()
        it("starts with zeroed bolt and cross counters per seat", function()
            local s = Session.new({ seed = 7 })
            assert.are.same({ 0, 0, 0 }, s:zero_tricks_bolts())
            assert.are.same({ 0, 0, 0 }, s:cross_count())
        end)

        it("returns counter copies, never the live arrays", function()
            local s = Session.new({ seed = 7 })
            local view = s:zero_tricks_bolts()
            view[1] = 999
            assert.are.equal(0, s:zero_tricks_bolts()[1])
        end)
    end)

    describe("zero_tricks any_three", function()
        it("increments bolts for both zero-trick seats and resets the sweeper", function()
            local cfg = config_with_overrides({
                penalties = { zero_tricks = "any_three" },
            })
            local s = session_at_tricks(cfg, bolt_layout(), { dealer = 1, declarer = 2, bid = 100 })
            play_sequence(s, seat2_sweeps_sequence())

            local dd = s:deal_done()
            assert.is_table(dd)
            -- Seats 1 and 3 took zero tricks; seat 2 swept.
            assert.are.same({ 1, 0, 1 }, dd.zero_tricks_bolts)
            -- No threshold hit yet.
            assert.are.same({ 0, 0, 0 }, dd.zero_tricks_penalty)
            assert.are.same({ 1, 0, 1 }, s:zero_tricks_bolts())
        end)

        it("fires the penalty and resets the counter at the threshold", function()
            -- Seed seats 1 and 3 with 2 bolts each; the third
            -- zero-trick deal pushes both to threshold and fires
            -- the -120 deduction.
            local cfg = config_with_overrides({
                penalties = { zero_tricks = "any_three" },
            })
            local s = session_at_tricks(cfg, bolt_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
                zero_tricks_bolts = { 2, 0, 2 },
            })
            play_sequence(s, seat2_sweeps_sequence())

            local dd = s:deal_done()
            assert.are.same({ -120, 0, -120 }, dd.zero_tricks_penalty)
            assert.are.same({ 0, 0, 0 }, dd.zero_tricks_bolts)
            assert.are.same({ 0, 0, 0 }, s:zero_tricks_bolts())
        end)
    end)

    describe("zero_tricks consecutive_three", function()
        it("resets a seat that took at least one trick", function()
            -- Seed seat 1 with 2 bolts, then run a deal where seat
            -- 1 (Js+9s) still takes zero tricks but seat 3 wins
            -- once. Easier: use the same sweep where seats 1 and 3
            -- both stay at zero. Adjust by seeding seat 3 only and
            -- letting them stay zero (third bolt fires); seed seat
            -- 1 to verify they hit threshold the same way under
            -- consecutive_three.
            local cfg = config_with_overrides({
                penalties = { zero_tricks = "consecutive_three" },
            })
            local s = session_at_tricks(cfg, bolt_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
                zero_tricks_bolts = { 2, 1, 2 },
            })
            play_sequence(s, seat2_sweeps_sequence())

            local dd = s:deal_done()
            -- Seat 2 took at least one trick this deal, so its
            -- counter resets under consecutive_three (was 1, now 0).
            assert.are.equal(0, dd.zero_tricks_bolts[2])
            -- Seats 1 and 3 stayed at zero so their counters hit
            -- threshold and fire.
            assert.are.equal(-120, dd.zero_tricks_penalty[1])
            assert.are.equal(-120, dd.zero_tricks_penalty[3])
            assert.are.equal(0, dd.zero_tricks_bolts[1])
            assert.are.equal(0, dd.zero_tricks_bolts[3])
        end)
    end)

    describe("zero_tricks_declarer_exempt", function()
        it("never increments the declarer's bolt counter", function()
            -- Make seat 1 declarer (forehand bids 100, others pass)
            -- under a layout where seat 1 takes zero tricks.
            local cfg = config_with_overrides({
                penalties = {
                    zero_tricks = "any_three",
                    zero_tricks_declarer_exempt = "on",
                },
            })
            local s = session_at_tricks(cfg, bolt_layout(), { dealer = 3, declarer = 1, bid = 100 })
            play_sequence(s, seat1_leads_then_seat2_sweeps_sequence())

            local dd = s:deal_done()
            -- Seat 1 (declarer) took zero tricks but is exempt.
            -- Seat 3 took zero tricks and earned a bolt.
            assert.are.equal(0, dd.zero_tricks_bolts[1])
            assert.are.equal(1, dd.zero_tricks_bolts[3])
        end)
    end)

    describe("zero_tricks_golden_deal_doubled", function()
        it("adds two bolts per zero-trick seat in a golden deal", function()
            local cfg = config_with_overrides({
                penalties = {
                    zero_tricks = "any_three",
                    zero_tricks_golden_deal_doubled = "on",
                },
            })
            local s = session_at_tricks(cfg, bolt_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
                in_golden_deal = true,
            })
            play_sequence(s, seat2_sweeps_sequence())

            local dd = s:deal_done()
            assert.are.equal(2, dd.zero_tricks_bolts[1])
            assert.are.equal(2, dd.zero_tricks_bolts[3])
        end)
    end)

    describe("cross suppression", function()
        it(
            "suppresses the declarer's failed-bid deduction and increments the cross counter",
            function()
                local cfg = config_with_overrides({
                    penalties = { cross = "on" },
                })
                -- Forehand (seat 2 since dealer=1) bids 100 and fails:
                -- seat 2 actually wins everything in the bolt_layout, so
                -- to force a failure I need a different declarer or
                -- different fixture. Use declarer = seat 1 who takes 0
                -- tricks.
                local s =
                    session_at_tricks(cfg, bolt_layout(), { dealer = 3, declarer = 1, bid = 100 })
                play_sequence(s, seat1_leads_then_seat2_sweeps_sequence())

                local dd = s:deal_done()
                assert.is_false(dd.made_contract)
                -- Declarer's -bid suppressed.
                assert.are.equal(0, dd.cross_penalty[1])
                assert.are.equal(1, dd.cross_count[1])
                assert.are.equal(1, s:cross_count()[1])
            end
        )

        it("fires the threshold penalty and resets at two crosses", function()
            local cfg = config_with_overrides({
                penalties = { cross = "on" },
            })
            local s = session_at_tricks(cfg, bolt_layout(), {
                dealer = 3,
                declarer = 1,
                bid = 100,
                cross_count = { 1, 0, 0 },
            })
            play_sequence(s, seat1_leads_then_seat2_sweeps_sequence())

            local dd = s:deal_done()
            assert.is_false(dd.made_contract)
            assert.are.equal(-120, dd.cross_penalty[1])
            assert.are.equal(0, dd.cross_count[1])
            assert.are.equal(0, s:cross_count()[1])
        end)
    end)

    describe("Session:record_penalty_violation", function()
        it("rejects a bad seat", function()
            local s = Session.new({ seed = 7 })
            local r = s:record_penalty_violation(99, "talon_look")
            assert.is_false(r.ok)
            assert.are.equal("bad_seat", r.error.code)
        end)

        it("rejects an unknown kind", function()
            local s = Session.new({ seed = 7 })
            local r = s:record_penalty_violation(1, "shouting")
            assert.is_false(r.ok)
            assert.are.equal("bad_kind", r.error.code)
        end)

        it("computes the standard talon_look amount of 120", function()
            local s = Session.new({ seed = 7 })
            local r = s:record_penalty_violation(2, "talon_look")
            assert.is_true(r.ok)
            assert.are.equal(120, r.amount)
        end)

        it("computes the standard showing_hand amount of 20", function()
            local s = Session.new({ seed = 7 })
            local r = s:record_penalty_violation(2, "showing_hand")
            assert.is_true(r.ok)
            assert.are.equal(20, r.amount)
        end)

        it("uses the active bid for showing_hand strict", function()
            local cfg = config_with_overrides({
                penalties = { showing_hand = "strict" },
            })
            local s = session_at_tricks(cfg, bolt_layout(), { dealer = 1, declarer = 2, bid = 100 })
            local r = s:record_penalty_violation(3, "showing_hand")
            assert.is_true(r.ok)
            assert.are.equal(100, r.amount)
        end)

        it("threads recorded violations into deal_done.showing_hand_penalty", function()
            local cfg = config_with_overrides({
                penalties = { showing_hand = "strict" },
            })
            local s = session_at_tricks(cfg, bolt_layout(), { dealer = 1, declarer = 2, bid = 100 })
            assert.is_true(s:record_penalty_violation(3, "showing_hand").ok)
            play_sequence(s, seat2_sweeps_sequence())

            local dd = s:deal_done()
            assert.are.equal(-100, dd.showing_hand_penalty[3])
        end)

        it("awards the talon_look stricter amount to the opposing side", function()
            local cfg = config_with_overrides({
                penalties = { talon_look = "stricter" },
            })
            local s = session_at_tricks(cfg, bolt_layout(), { dealer = 1, declarer = 2, bid = 100 })
            -- A defender (seat 3) looked at the talon — amount = bid = 100.
            assert.is_true(s:record_penalty_violation(3, "talon_look").ok)
            play_sequence(s, seat2_sweeps_sequence())

            local dd = s:deal_done()
            -- Offender loses 100; declarer (opposing side) gains 100.
            assert.are.equal(-100, dd.talon_look_penalty[3])
            assert.are.equal(100, dd.talon_look_penalty[2])
        end)

        it("clears the recorded log between deals", function()
            local cfg = config_with_overrides({
                penalties = { showing_hand = "strict" },
            })
            local s = session_at_tricks(cfg, bolt_layout(), { dealer = 1, declarer = 2, bid = 100 })
            assert.is_true(s:record_penalty_violation(3, "showing_hand").ok)
            play_sequence(s, seat2_sweeps_sequence())
            -- Start the next deal — the recorded log resets.
            s:start_next_deal()
            assert.are.same({}, s._recorded_penalties)
        end)
    end)

    describe("counter persistence", function()
        it("round-trips through Session.from_state", function()
            local cfg = rule_config.canonical_russian
            local s = Session.from_state({
                config = cfg,
                seed = 1,
                dealer = 1,
                hands = bolt_layout(),
                running_totals = { 100, 200, 300 },
                zero_tricks_bolts = { 2, 0, 1 },
                cross_count = { 0, 1, 0 },
            })
            assert.are.same({ 2, 0, 1 }, s:zero_tricks_bolts())
            assert.are.same({ 0, 1, 0 }, s:cross_count())
        end)
    end)
end)
