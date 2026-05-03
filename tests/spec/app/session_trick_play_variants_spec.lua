-- Phase 3.6 trick-play variants integration coverage. Drives the
-- session through scripted scenarios where each `tricks.*` house rule
-- changes engine flow or scoring. Mirrors the marriage_variants_spec
-- shape: per-toggle describes, deterministic 24-card hands, and a
-- session positioned mid-tricks with a contracted declarer.

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

local function config_with_trick_overrides(overrides)
    local blob = json.decode(rule_config.to_json(rule_config.canonical_russian))
    -- Trick-play tests declare marriages at the start of the tricks
    -- phase (no captured tricks yet); the canonical
    -- `marriages.trick_required = "on"` rule would gate them. The gate
    -- itself is covered by tests/spec/core/marriages_spec.lua.
    blob.marriages.trick_required = "off"
    overrides = overrides or {}
    for k, v in pairs(overrides) do
        blob.tricks[k] = v
    end
    return rule_config.new(blob)
end

-- 24-card 3-player layout. Seat 2 declarer at dealer = 1.
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
        declarer = declarer,
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

describe("app.session trick-play variants", function()
    describe("lead_trump_after_marriage = on", function()
        it("restricts the next lead to trump after declare_marriage", function()
            local cfg = config_with_trick_overrides({ lead_trump_after_marriage = "on" })
            local s = session_at_tricks(cfg, full_deal_layout())
            -- Seat 2 declares hearts marriage on lead. Under the standard
            -- next_trick activation, trump engages on the trick after
            -- this one. The lead-trump-after-marriage flag also engages
            -- on that next trick.
            assert.is_true(s:declare_marriage(2, "hearts").ok)
            -- Seat 2 leads K of hearts to start the trick.
            assert.is_true(s:play(2, c("hearts", "K")).ok)
            -- Seats 3 and 1 must follow / discard. Seat 3 has hearts.A
            -- (highest); plays it. Seat 1 has no hearts; discards
            -- diamonds.9.
            assert.is_true(s:play(3, c("hearts", "A")).ok)
            assert.is_true(s:play(1, c("diamonds", "9")).ok)
            -- Trick resolved; trump should now be hearts (next_trick
            -- timing) and seat 3 won (hearts.A). Seat 3 leads the next
            -- trick. lead_trump_after_marriage="on" + has hearts → only
            -- hearts cards are legal on this lead.
            assert.are.equal("hearts", s:trump())
            local lc = s:legal_cards(3)
            assert.is_true(#lc >= 1)
            for _, card_obj in ipairs(lc) do
                assert.are.equal("hearts", card_obj.suit)
            end
        end)
    end)

    describe("slam_against_penalty", function()
        it("subtracts the configured penalty from declarer's deal_score on zero tricks", function()
            -- Set up a layout where the declarer takes 0 tricks. Easiest:
            -- declarer at seat 1 with a forced bid; opponents seize all.
            -- Use a layout where seat 2 holds A,10 of every suit so they
            -- always win.
            local layout = {
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
            local cfg = config_with_trick_overrides({
                slam_against_penalty = "on",
                slam_against_penalty_value = 120,
            })
            -- Declarer = seat 1. They will take zero tricks because seat 2
            -- always overtakes.
            local s = session_at_tricks(cfg, layout, { declarer = 1 })
            -- Plays: seat 1 leads each trick (winner of each trick is
            -- seat 2 because A > everything). Sequence each trick:
            -- p1 → p2 → p3, p2 wins.
            local sequence = {
                {
                    { 1, c("hearts", "9") },
                    { 2, c("hearts", "A") },
                    { 3, c("hearts", "Q") },
                },
                {
                    { 2, c("hearts", "10") },
                    { 3, c("hearts", "K") },
                    { 1, c("hearts", "J") },
                },
                {
                    { 2, c("diamonds", "A") },
                    { 3, c("diamonds", "K") },
                    { 1, c("diamonds", "9") },
                },
                {
                    { 2, c("diamonds", "10") },
                    { 3, c("diamonds", "Q") },
                    { 1, c("diamonds", "J") },
                },
                {
                    { 2, c("clubs", "A") },
                    { 3, c("clubs", "K") },
                    { 1, c("clubs", "9") },
                },
                {
                    { 2, c("clubs", "10") },
                    { 3, c("clubs", "Q") },
                    { 1, c("clubs", "J") },
                },
                {
                    { 2, c("spades", "A") },
                    { 3, c("spades", "K") },
                    { 1, c("spades", "9") },
                },
                {
                    { 2, c("spades", "10") },
                    { 3, c("spades", "Q") },
                    { 1, c("spades", "J") },
                },
            }
            for _, trick in ipairs(sequence) do
                for _, play in ipairs(trick) do
                    local r = s:play(play[1], play[2])
                    if not r.ok then
                        error(
                            "play failed: seat "
                                .. play[1]
                                .. " "
                                .. play[2].suit
                                .. " "
                                .. play[2].rank
                                .. " -> "
                                .. (r.error and r.error.code or "?")
                        )
                    end
                end
            end
            local dd = s:deal_done()
            assert.is_table(dd)
            -- Declarer captured 0 points; -120 penalty applied.
            assert.are.equal(0 - 120, dd.deal_scores[1])
        end)
    end)
end)
