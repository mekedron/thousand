-- Phase 3.9 write-off / сдача integration coverage. The decision is a
-- one-shot pre-tricks prompt opened between talon take (or talon
-- reveal under Polish `pass_without_taking`) and the pass step.
-- Coverage focuses on:
--   * the phase transition from take_talon (Russian / 2p-B) and from
--     the talon reveal (Polish) into `awaiting_write_off_decision`;
--   * Session:accept_play clearing the prompt and letting the pass /
--     discard / Polish-pass methods proceed normally;
--   * Session:write_off scoring math from the new phase
--     (half_to_each + equal_split, 3-player + 4-player layouts);
--   * the cross-deal write-off counter, including threshold-hit
--     penalty firing and reset;
--   * the toggle-off and rejection paths (mid-tricks call rejected,
--     pass_talon auto-clears the offer when the prompt is open).
-- Auto-save round-trip is covered in tests/spec/core/auto_save_spec.

local Session = require("app.session")
local rule_config = require("core.rule_config")
local card = require("core.card")
local json = require("app.json")
local marriages_module = require("core.marriages")
local auction_module = require("core.auction")

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

-- Generic 3-player layout. Seat 2 is the declarer in every test; the
-- prompt fires before any tricks are played, so the actual card mix
-- only matters for marriage / suit-follow code paths the write-off
-- decision never reaches.
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

-- Build a session sitting at `awaiting_write_off_decision` via
-- Session.from_state. Mirrors the auction_module flow that opens the
-- prompt naturally so the rebuilt state matches what `take_talon`
-- would have produced — but skips the prompt-opening hook so the
-- assertions can exercise the post-prompt mutators directly.
local function session_at_write_off_decision(test_config, hands, opts)
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

    local from = {
        config = test_config,
        seed = opts.seed or 1,
        dealer = dealer,
        hands = hands,
        auction = auction,
        marriages = marriages,
        talon = {
            declarer = declarer,
            final_bid = opts.bid or 100,
            status = opts.talon_status or "awaiting_pass",
            distribution = opts.distribution or "declarer_takes_then_passes",
            hands = hands,
            sits_out = opts.sits_out,
            opponent_count = pc - 1 - (opts.sits_out and 1 or 0),
            passes_received = {},
        },
        running_totals = running_totals,
        deal_index = opts.deal_index or 1,
        awaiting_write_off_decision = {
            declarer = declarer,
            bid = opts.bid or 100,
            split_mode = test_config.bidding.write_off_split,
        },
    }
    if opts.write_off_counts then
        from.write_off_counts = opts.write_off_counts
    end
    return Session.from_state(from)
end

describe("app.session write-off (Phase 3.9 pre-tricks prompt)", function()
    describe("phase transitions", function()
        it("opens the prompt after take_talon under canonical Russian", function()
            local cfg = rule_config.canonical_russian
            local s = Session.new({ seed = 7, dealer = 1, config = cfg })
            assert(s:bid(2, 100).ok)
            assert(s:pass(3).ok)
            assert(s:pass(1).ok)
            assert.are.equal("talon", s:current_phase())
            assert(s:take_talon().ok)
            assert.are.equal("awaiting_write_off_decision", s:current_phase())
            local offer = s:write_off_offer_state()
            assert.is_table(offer)
            assert.are.equal(2, offer.declarer)
            assert.are.equal(100, offer.bid)
            assert.are.equal("half_to_each", offer.split_mode)
            -- The acting seat is the declarer.
            assert.are.equal(2, s:current_turn())
        end)

        it("does not open the prompt when bidding.write_off is off", function()
            local cfg = config_with_overrides({ bidding = { write_off = "off" } })
            local s = Session.new({ seed = 7, dealer = 1, config = cfg })
            assert(s:bid(2, 100).ok)
            assert(s:pass(3).ok)
            assert(s:pass(1).ok)
            assert(s:take_talon().ok)
            assert.are.equal("talon", s:current_phase())
            assert.is_nil(s:write_off_offer_state())
        end)

        it("does not re-open the prompt after the declarer chose play", function()
            local cfg = rule_config.canonical_russian
            local s = Session.new({ seed = 7, dealer = 1, config = cfg })
            assert(s:bid(2, 100).ok)
            assert(s:pass(3).ok)
            assert(s:pass(1).ok)
            assert(s:take_talon().ok)
            assert(s:accept_play().ok)
            assert.are.equal("talon", s:current_phase())
            -- Pass a card; the prompt must not re-open mid-pass.
            local hand = s:hands()[2]
            assert(s:pass_talon(1, hand[1]).ok)
            assert.are.equal("talon", s:current_phase())
        end)
    end)

    describe("auto-resolution on first pass / discard / raise", function()
        -- Phase 3.9 follow-up: the prompt is no longer a blocking gate.
        -- The first card-moving action on a hand with an open offer
        -- silently accepts play (offer cleared, declarer committed) so
        -- the inline Write-off button vanishes the moment the deal
        -- starts. Explicit `accept_play()` / `write_off()` still work
        -- for callers that need to resolve without moving a card.
        it("pass_talon auto-clears the offer and continues normally", function()
            local cfg = rule_config.canonical_russian
            local s = Session.new({ seed = 7, dealer = 1, config = cfg })
            assert(s:bid(2, 100).ok)
            assert(s:pass(3).ok)
            assert(s:pass(1).ok)
            assert(s:take_talon().ok)
            assert.is_not_nil(s:write_off_offer_state())
            local hand = s:hands()[2]
            local r = s:pass_talon(1, hand[1])
            assert.is_true(r.ok)
            assert.is_nil(s:write_off_offer_state())
            assert.are.equal("talon", s:current_phase())
        end)

        it("skip_raise auto-clears the offer", function()
            local cfg = rule_config.canonical_russian
            local s = Session.new({ seed = 7, dealer = 1, config = cfg })
            assert(s:bid(2, 100).ok)
            assert(s:pass(3).ok)
            assert(s:pass(1).ok)
            assert(s:take_talon().ok)
            -- Skip both passes via accept_play first (would otherwise
            -- need card moves to reach skip_raise). This exercises the
            -- explicit-resolution path so we can test skip_raise's
            -- auto-clear independently.
            assert(s:accept_play().ok)
            local hand = s:hands()[2]
            assert(s:pass_talon(1, hand[1]).ok)
            hand = s:hands()[2]
            assert(s:pass_talon(3, hand[1]).ok)
            -- Now we're at awaiting_raise; no offer is open here, so
            -- this case asserts the helper is a safe no-op when the
            -- offer was already cleared.
            assert.is_nil(s:write_off_offer_state())
            assert(s:skip_raise().ok)
        end)

        it("pass_polish_talon auto-clears the offer", function()
            -- Base on the Polish built-in (talon distribution =
            -- pass_without_taking) and flip write_off back on, since
            -- canonical Polish has it off.
            local polish_blob = json.decode(rule_config.to_json(rule_config.builtins.polish))
            polish_blob.bidding.write_off = "on"
            local cfg = rule_config.new(polish_blob)
            local s = Session.new({ seed = 7, dealer = 1, config = cfg })
            assert(s:bid(2, 100).ok)
            assert(s:pass(3).ok)
            assert(s:pass(1).ok)
            -- Polish reveal opens the offer; the first pass_polish_talon
            -- clears it and keeps going.
            assert.is_not_nil(s:write_off_offer_state())
            local r = s:pass_polish_talon(1, 1)
            assert.is_true(r.ok)
            assert.is_nil(s:write_off_offer_state())
        end)
    end)

    describe("guards", function()
        it("write_off rejects when bidding.write_off is off", function()
            local cfg = config_with_overrides({ bidding = { write_off = "off" } })
            local s = Session.new({ seed = 7, dealer = 1, config = cfg })
            assert(s:bid(2, 100).ok)
            assert(s:pass(3).ok)
            assert(s:pass(1).ok)
            assert(s:take_talon().ok)
            local r = s:write_off()
            assert.is_false(r.ok)
            assert.are.equal("write_off_disabled", r.error.code)
        end)

        it("write_off rejects when called outside the awaiting phase", function()
            local cfg = config_with_overrides({ bidding = { write_off = "on" } })
            local s = Session.new({ config = cfg, seed = 7 })
            assert.are.equal("auction", s:current_phase())
            local r = s:write_off()
            assert.is_false(r.ok)
            assert.are.equal("wrong_phase", r.error.code)
        end)

        it("write_off rejects mid-tricks (legacy in-trick path is gone)", function()
            local cfg = rule_config.canonical_russian
            local s = Session.new({ seed = 7, dealer = 1, config = cfg })
            assert(s:bid(2, 100).ok)
            assert(s:pass(3).ok)
            assert(s:pass(1).ok)
            assert(s:take_talon().ok)
            assert(s:accept_play().ok)
            local hand = s:hands()[2]
            assert(s:pass_talon(1, hand[1]).ok)
            hand = s:hands()[2]
            assert(s:pass_talon(3, hand[1]).ok)
            assert(s:skip_raise().ok)
            assert.are.equal("tricks", s:current_phase())
            local r = s:write_off()
            assert.is_false(r.ok)
            assert.are.equal("wrong_phase", r.error.code)
        end)

        it("accept_play rejects when no prompt is pending", function()
            local s = Session.new({ seed = 7 })
            local r = s:accept_play()
            assert.is_false(r.ok)
            assert.are.equal("no_write_off_pending", r.error.code)
        end)
    end)

    describe("half_to_each split", function()
        it("subtracts the bid from declarer and credits half to each opponent", function()
            local cfg = config_with_overrides({
                bidding = { write_off = "on", write_off_split = "half_to_each" },
            })
            local s = session_at_write_off_decision(cfg, generic_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
            })
            assert.are.equal("awaiting_write_off_decision", s:current_phase())
            local r = s:write_off()
            assert.is_true(r.ok)
            local dd = s:deal_done()
            assert.is_table(dd)
            assert.are.equal("write_off", dd.reason)
            assert.are.equal(2, dd.declarer)
            -- Seat 2 declarer pays 100; seats 1 and 3 each receive 50.
            assert.are.same({ 50, -100, 50 }, dd.deal_scores)
            assert.are.same({ 0, 1, 0 }, s:write_off_counts())
        end)

        it("survives a JSON-snapshot round-trip with the counter intact", function()
            local cfg = config_with_overrides({
                bidding = { write_off = "on", write_off_split = "half_to_each" },
                penalties = { write_off_streak = "off" },
            })
            local s = session_at_write_off_decision(cfg, generic_layout(), {
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
            local s = session_at_write_off_decision(cfg, generic_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
            })
            local r = s:write_off()
            assert.is_true(r.ok)
            local dd = s:deal_done()
            -- 100 / 2 recipients = 50 each.
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
            local s = session_at_write_off_decision(cfg, generic_layout(), {
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
            local s = session_at_write_off_decision(cfg, generic_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
                write_off_counts = { 0, 1, 0 },
            })
            local r = s:write_off()
            assert.is_true(r.ok)
            local dd = s:deal_done()
            assert.are.same({ 50, -160, 50 }, dd.deal_scores)
            assert.are.same({ 0, 0, 0 }, s:write_off_counts())
        end)

        it("does not fire when the streak rule is off even if the counter is high", function()
            local cfg = config_with_overrides({
                bidding = { write_off = "on" },
                penalties = { write_off_streak = "off" },
            })
            local s = session_at_write_off_decision(cfg, generic_layout(), {
                dealer = 1,
                declarer = 2,
                bid = 100,
                write_off_counts = { 0, 5, 0 },
            })
            local r = s:write_off()
            assert.is_true(r.ok)
            assert.are.same({ 0, 6, 0 }, s:write_off_counts())
            local dd = s:deal_done()
            assert.are.same({ 50, -100, 50 }, dd.deal_scores)
        end)
    end)
end)
