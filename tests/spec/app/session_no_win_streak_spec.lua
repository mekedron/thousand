-- Phase 3.7 no-win-streak penalty integration coverage. Mirrors
-- session_penalties_spec / session_write_off_spec: per-toggle
-- describes, deterministic 24-card hands, and an 8-trick play
-- sequence. The book defines the rule (lines 39–47): a seat that
-- fails to win for `no_win_streak_threshold` deals takes the
-- configured penalty and the counter resets. "Won the deal" =
-- declarer made contract OR defender captured positive deal_scores.
--
-- The engine math for individual penalties is pinned in
-- tests/spec/core/scoring_spec; this file focuses on the cross-deal
-- counter wiring through Session.score_deal_and_advance.

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

-- Same layout used in session_penalties_spec. Seat 2 holds Aces +
-- 10s (sweeps); seats 1 and 3 take zero tricks under the canonical
-- "seat 2 leads each trick" sequence.
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
    if opts.no_win_streak_counts then
        from.no_win_streak_counts = opts.no_win_streak_counts
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

describe("app.session no-win-streak penalty", function()
    describe("initial state", function()
        it("starts with zeroed no-win counters per seat", function()
            local s = Session.new({ seed = 7 })
            assert.are.same({ 0, 0, 0 }, s:no_win_streak_counts())
        end)

        it("returns counter copies, never the live array", function()
            local s = Session.new({ seed = 7 })
            local view = s:no_win_streak_counts()
            view[1] = 999
            assert.are.equal(0, s:no_win_streak_counts()[1])
        end)
    end)

    describe("'won the deal' semantics", function()
        it(
            "treats declarer-makes-contract as a win for declarer; defender with positive deal_scores wins",
            function()
                -- Declarer = seat 2 sweeps for 120; seat 2 makes the
                -- 100 contract → seat 2 wins. Seat 3 captured 0
                -- tricks → 0 deal points → seat 3 did NOT win. Seat 1
                -- also captured 0 tricks → did NOT win.
                local cfg = config_with_overrides({
                    penalties = { no_win_streak = "consecutive_three" },
                })
                local s = session_at_tricks(cfg, sweep_layout(), {
                    dealer = 1,
                    declarer = 2,
                    bid = 100,
                })
                play_sequence(s, seat2_sweeps_sequence())
                -- After the deal: seats 1 and 3 each gain 1 in their
                -- no-win counter; seat 2 stays at 0.
                assert.are.same({ 1, 0, 1 }, s:no_win_streak_counts())
            end
        )
    end)

    describe("consecutive_three", function()
        it("increments per non-win, resets a seat that wins", function()
            local cfg = config_with_overrides({
                penalties = { no_win_streak = "consecutive_three" },
            })
            -- Seed seat 1 to 2; play a deal where seat 1 doesn't win
            -- (declarer = seat 2 sweeps). Seat 1's counter advances
            -- but doesn't yet hit threshold = 3.
            local s = session_at_tricks(cfg, sweep_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
                no_win_streak_counts = { 2, 0, 1 },
            })
            play_sequence(s, seat2_sweeps_sequence())
            -- Seat 1: 2 + 1 = 3 → threshold hit → resets to 0,
            -- penalty fires.
            -- Seat 2: makes contract → counter unchanged at 0.
            -- Seat 3: 1 + 1 = 2 → no threshold hit, no reset.
            assert.are.same({ 0, 0, 2 }, s:no_win_streak_counts())
            local dd = s:deal_done()
            assert.is_table(dd)
            assert.are.equal(-120, dd.no_win_streak_penalty[1])
            assert.are.equal(0, dd.no_win_streak_penalty[2])
            assert.are.equal(0, dd.no_win_streak_penalty[3])
        end)
    end)

    describe("any_three", function()
        it("does NOT reset on a winning deal — only the threshold-fire clears it", function()
            -- Seed seat 1 to 1, then declare seat 1 and have them
            -- make contract on this deal. Under any_three the
            -- counter should NOT reset.
            local cfg = config_with_overrides({
                penalties = { no_win_streak = "any_three" },
            })
            -- Seat 1 declares 100 and "wins" via captured tricks.
            -- Easiest path: seat 1 sweeps. Use sweep_layout but with
            -- declarer = 1 and a dealing-order where seat 1 leads.
            local s = session_at_tricks(cfg, {
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
                    c("hearts", "Q"),
                    c("hearts", "K"),
                    c("diamonds", "Q"),
                    c("diamonds", "K"),
                    c("clubs", "Q"),
                    c("clubs", "K"),
                    c("spades", "Q"),
                    c("spades", "K"),
                },
            }, {
                dealer = 3,
                declarer = 1,
                bid = 100,
                no_win_streak_counts = { 1, 0, 0 },
            })
            -- Seat 1 leads each trick and sweeps.
            play_sequence(s, {
                { { 1, c("hearts", "A") }, { 2, c("hearts", "9") }, { 3, c("hearts", "Q") } },
                { { 1, c("hearts", "10") }, { 2, c("hearts", "J") }, { 3, c("hearts", "K") } },
                {
                    { 1, c("diamonds", "A") },
                    { 2, c("diamonds", "9") },
                    { 3, c("diamonds", "Q") },
                },
                {
                    { 1, c("diamonds", "10") },
                    { 2, c("diamonds", "J") },
                    { 3, c("diamonds", "K") },
                },
                { { 1, c("clubs", "A") }, { 2, c("clubs", "9") }, { 3, c("clubs", "Q") } },
                { { 1, c("clubs", "10") }, { 2, c("clubs", "J") }, { 3, c("clubs", "K") } },
                { { 1, c("spades", "A") }, { 2, c("spades", "9") }, { 3, c("spades", "Q") } },
                { { 1, c("spades", "10") }, { 2, c("spades", "J") }, { 3, c("spades", "K") } },
            })
            -- Seat 1 made contract → won the deal. Under any_three the
            -- counter does NOT reset on a win; it stays at 1.
            assert.are.equal(1, s:no_win_streak_counts()[1])
        end)
    end)

    describe("custom threshold and amount", function()
        it("fires at threshold = 2 with amount = 60", function()
            local cfg = config_with_overrides({
                penalties = {
                    no_win_streak = "any_three",
                    no_win_streak_threshold = 2,
                    no_win_streak_penalty_amount = 60,
                },
            })
            -- Seat 3 already at 1; one more non-win trips the
            -- threshold = 2.
            local s = session_at_tricks(cfg, sweep_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
                no_win_streak_counts = { 0, 0, 1 },
            })
            play_sequence(s, seat2_sweeps_sequence())
            local dd = s:deal_done()
            assert.are.equal(-60, dd.no_win_streak_penalty[3])
            assert.are.equal(0, s:no_win_streak_counts()[3])
        end)
    end)

    describe("auto-save round trip", function()
        it("persists a non-zero counter across serialize/deserialize", function()
            local cfg = config_with_overrides({
                penalties = { no_win_streak = "any_three" },
            })
            local s = session_at_tricks(cfg, sweep_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
                no_win_streak_counts = { 0, 0, 1 },
            })
            play_sequence(s, seat2_sweeps_sequence())
            local before = s:no_win_streak_counts()
            -- Take a JSON snapshot and re-load.
            local auto_save = require("core.auto_save")
            local blob = auto_save.serialize(s)
            local round = auto_save.deserialize(blob)
            local s2 = Session.from_state(round)
            assert.are.same(before, s2:no_win_streak_counts())
        end)
    end)
end)
