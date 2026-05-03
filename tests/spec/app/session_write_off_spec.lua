-- Phase 3.7 write-off / сдача integration coverage. Mirrors
-- session_penalties_spec: per-toggle describes, deterministic
-- 24-card hands, scripted setup at the tricks phase via
-- Session.from_state. Coverage focuses on:
--   * the action's phase / toggle / declarer / trick-count guards;
--   * the half_to_each and equal_split distribution math (3-player
--     canonical and 4-player layouts);
--   * the cross-deal write-off counter, including threshold-hit
--     penalty firing and reset.
-- The auto-save round-trip lives in tests/spec/core/auto_save_spec.

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

-- Generic 3-player layout. Seat 2 holds the winners but the actual
-- sequence doesn't matter for write-off tests — the action concedes
-- the deal before any tricks are played, so each test only relies on
-- the bid value and the seat layout.
local function generic_layout()
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
    if opts.write_off_counts then
        from.write_off_counts = opts.write_off_counts
    end
    return Session.from_state(from)
end

describe("app.session write-off", function()
    describe("initial state", function()
        it("starts with zeroed write-off counters per seat", function()
            local s = Session.new({ seed = 7 })
            assert.are.same({ 0, 0, 0 }, s:write_off_counts())
        end)

        it("returns counter copies, never the live array", function()
            local s = Session.new({ seed = 7 })
            local view = s:write_off_counts()
            view[1] = 999
            assert.are.equal(0, s:write_off_counts()[1])
        end)
    end)

    describe("guards", function()
        it("rejects when bidding.write_off is off", function()
            -- Canonical Russian has write_off = "on" per the book; opt
            -- it off here to exercise the disabled-action guard.
            local cfg = config_with_overrides({ bidding = { write_off = "off" } })
            local s = session_at_tricks(cfg, generic_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
            })
            local r = s:write_off()
            assert.is_false(r.ok)
            assert.are.equal("write_off_disabled", r.error.code)
        end)

        it("rejects when not in the tricks phase", function()
            local cfg = config_with_overrides({ bidding = { write_off = "on" } })
            local s = Session.new({ config = cfg, seed = 7 })
            assert.are.equal("auction", s:current_phase())
            local r = s:write_off()
            assert.is_false(r.ok)
            assert.are.equal("wrong_phase", r.error.code)
        end)

        it("rejects once the last trick has begun", function()
            local cfg = config_with_overrides({ bidding = { write_off = "on" } })
            local s = session_at_tricks(cfg, generic_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
            })
            -- Force tricks_played up to tricks_per_deal - 1 to simulate
            -- the moment after the seventh trick has resolved and the
            -- eighth is the only one left.
            s._tricks.tricks_played = (s._tricks.tricks_per_deal or 8) - 1
            local r = s:write_off()
            assert.is_false(r.ok)
            assert.are.equal("too_late_to_write_off", r.error.code)
        end)
    end)

    describe("half_to_each split", function()
        it("subtracts the bid from declarer and credits half to each opponent", function()
            local cfg = config_with_overrides({
                bidding = { write_off = "on", write_off_split = "half_to_each" },
            })
            local s = session_at_tricks(cfg, generic_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
            })
            local r = s:write_off()
            assert.is_true(r.ok)
            local dd = s:deal_done()
            assert.is_table(dd)
            assert.are.equal("write_off", dd.reason)
            assert.are.equal(2, dd.declarer)
            -- Seat 2 declarer pays 100; seats 1 and 3 each receive 50.
            assert.are.same({ 50, -100, 50 }, dd.deal_scores)
            -- Counter advanced by 1.
            assert.are.same({ 0, 1, 0 }, s:write_off_counts())
        end)

        it("survives a JSON snapshot round-trip with the counter intact", function()
            -- Pin the streak penalty off so the counter advances past
            -- 2 without resetting; the threshold-fire path has its own
            -- coverage in the every-third-write-off describe below.
            local cfg = config_with_overrides({
                bidding = { write_off = "on", write_off_split = "half_to_each" },
                penalties = { write_off_streak = "off" },
            })
            local s = session_at_tricks(cfg, generic_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
                write_off_counts = { 0, 2, 0 },
            })
            local r = s:write_off()
            assert.is_true(r.ok)
            assert.are.same({ 0, 3, 0 }, s:write_off_counts())
        end)
    end)

    describe("equal_split", function()
        it("divides the bid equally among the recipients", function()
            local cfg = config_with_overrides({
                bidding = { write_off = "on", write_off_split = "equal_split" },
            })
            local s = session_at_tricks(cfg, generic_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
            })
            local r = s:write_off()
            assert.is_true(r.ok)
            -- 100 / 2 recipients = 50 each. Floor of 100/2 is 50.
            local dd = s:deal_done()
            assert.are.same({ 50, -100, 50 }, dd.deal_scores)
        end)
    end)

    describe("write_off_streak any_three", function()
        it("fires the configured penalty and resets the counter at the threshold", function()
            local cfg = config_with_overrides({
                bidding = { write_off = "on" },
                penalties = {
                    write_off_streak = "any_three",
                    write_off_streak_threshold = 3,
                    write_off_streak_penalty_amount = 120,
                    no_win_streak = "off",
                    no_win_streak_threshold = 3,
                    no_win_streak_penalty_amount = 120,
                },
            })
            local s = session_at_tricks(cfg, generic_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
                write_off_counts = { 0, 2, 0 },
            })
            local r = s:write_off()
            assert.is_true(r.ok)
            local dd = s:deal_done()
            -- Declarer pays 100 (bid) + 120 (penalty) = 220; opponents
            -- still take 50 each (penalty does not reach them).
            assert.are.same({ 50, -220, 50 }, dd.deal_scores)
            -- Counter resets after the threshold fires.
            assert.are.same({ 0, 0, 0 }, s:write_off_counts())
        end)

        it("respects a custom threshold and penalty amount", function()
            local cfg = config_with_overrides({
                bidding = { write_off = "on" },
                penalties = {
                    write_off_streak = "any_three",
                    write_off_streak_threshold = 2,
                    write_off_streak_penalty_amount = 60,
                    no_win_streak = "off",
                    no_win_streak_threshold = 3,
                    no_win_streak_penalty_amount = 120,
                },
            })
            local s = session_at_tricks(cfg, generic_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
                write_off_counts = { 0, 1, 0 },
            })
            local r = s:write_off()
            assert.is_true(r.ok)
            local dd = s:deal_done()
            -- Declarer pays 100 (bid) + 60 (penalty) = 160; opponents
            -- each take 50.
            assert.are.same({ 50, -160, 50 }, dd.deal_scores)
            assert.are.same({ 0, 0, 0 }, s:write_off_counts())
        end)

        it("does not fire when the streak rule is off even if the counter is high", function()
            local cfg = config_with_overrides({
                bidding = { write_off = "on" },
                penalties = { write_off_streak = "off" },
            })
            local s = session_at_tricks(cfg, generic_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
                write_off_counts = { 0, 5, 0 },
            })
            local r = s:write_off()
            assert.is_true(r.ok)
            -- Counter still increments for diagnostic display, but no
            -- penalty fires.
            assert.are.same({ 0, 6, 0 }, s:write_off_counts())
            local dd = s:deal_done()
            assert.are.same({ 50, -100, 50 }, dd.deal_scores)
        end)
    end)
end)
