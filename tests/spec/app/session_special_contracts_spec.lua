-- Phase 3.6 special-contracts integration coverage. Drives the session
-- end-to-end through scripted deals where the auction terminates with
-- a structured named bid (mizère / slam / open hand) and asserts:
--
--   * marriage declarations are blocked under mizère;
--   * the active named contract is recorded and surfaced;
--   * scoring routes through `score_named_contract`, applying
--     declarer +/-value with defenders at zero;
--   * the deal-done payload carries `named_contract` for the
--     view-model.
--
-- Engine math is exhaustively pinned in tests/spec/core/scoring_spec —
-- these tests focus on session-level wiring + success criteria
-- (mizère = 0 tricks; slam = all 8; open hand = ≥ opening_min captured).

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

local function specials_config(specials_overrides)
    local blob = json.decode(rule_config.to_json(rule_config.canonical_russian))
    blob.bidding.named_contracts = "on"
    specials_overrides = specials_overrides or {}
    for k, v in pairs(specials_overrides) do
        blob.specials[k] = v
    end
    return rule_config.new(blob)
end

-- Declarer (seat 2) takes every trick: holds aces+10s. Mirrors the
-- overcapture pattern in session_endgame_variants_spec.lua.
local function slam_hands_declarer_sweeps()
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

local function slam_sequence_declarer_sweeps()
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

-- Declarer (seat 2) loses every trick: holds 9s and Js (lowest cards
-- under canonical rank A>10>K>Q>J>9). Seats 1 and 3 carry the heavy
-- cards. Used for both mizère success (declarer takes 0 tricks) and
-- mizère failure tests.
local function mizere_hands_declarer_loses()
    return {
        {
            c("hearts", "A"),
            c("diamonds", "A"),
            c("clubs", "A"),
            c("spades", "A"),
            c("hearts", "K"),
            c("diamonds", "K"),
            c("clubs", "K"),
            c("spades", "K"),
        },
        {
            c("hearts", "9"),
            c("diamonds", "9"),
            c("clubs", "9"),
            c("spades", "9"),
            c("hearts", "J"),
            c("diamonds", "J"),
            c("clubs", "J"),
            c("spades", "J"),
        },
        {
            c("hearts", "10"),
            c("diamonds", "10"),
            c("clubs", "10"),
            c("spades", "10"),
            c("hearts", "Q"),
            c("diamonds", "Q"),
            c("clubs", "Q"),
            c("spades", "Q"),
        },
    }
end

-- Sequence: seat 1 (the previous trick winner / forehand) leads each
-- trick with an A; declarer (seat 2) follows with their lowest card
-- (J) and never wins. Seat 1 wins all 8 tricks.
local function mizere_sequence_seat1_sweeps()
    return {
        { { 1, c("hearts", "A") }, { 2, c("hearts", "9") }, { 3, c("hearts", "10") } },
        { { 1, c("diamonds", "A") }, { 2, c("diamonds", "9") }, { 3, c("diamonds", "10") } },
        { { 1, c("clubs", "A") }, { 2, c("clubs", "9") }, { 3, c("clubs", "10") } },
        { { 1, c("spades", "A") }, { 2, c("spades", "9") }, { 3, c("spades", "10") } },
        { { 1, c("hearts", "K") }, { 2, c("hearts", "J") }, { 3, c("hearts", "Q") } },
        { { 1, c("diamonds", "K") }, { 2, c("diamonds", "J") }, { 3, c("diamonds", "Q") } },
        { { 1, c("clubs", "K") }, { 2, c("clubs", "J") }, { 3, c("clubs", "Q") } },
        { { 1, c("spades", "K") }, { 2, c("spades", "J") }, { 3, c("spades", "Q") } },
    }
end

-- Build a session in the tricks phase with a structured named bid as
-- the talon's `final_bid`. Mirrors session_endgame_variants_spec's
-- `session_at_tricks` helper but plumbs the named-contract record so
-- the marriage block, open-hand visibility flag, and named-contract
-- scoring path all see the active state.
local function session_at_tricks_named(test_config, hands, opts)
    opts = opts or {}
    local dealer = opts.dealer or 1
    local pc = test_config.players.count
    local declarer = opts.declarer or ((dealer % pc) + 1)
    local leader = opts.leader or declarer
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
    auction = auction_module.bid(auction, forehand, opts.bid).auction
    for seat = 1, pc do
        if seat ~= forehand and auction.status == "in_progress" then
            local r = auction_module.pass(auction, seat)
            if r.ok then
                auction = r.auction
            end
        end
    end

    local marriages = marriages_module.new(test_config).marriages
    local tricks = tricks_module.new(test_config, hands, leader, {
        dealer = dealer,
        declarer = declarer,
    }).tricks

    local active_named = {
        kind = opts.bid.contract,
        value = opts.bid.value,
    }

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
            final_bid = opts.bid,
            status = "done",
            hands = hands,
        },
        running_totals = running_totals,
        barrel_state = opts.barrel_state,
        deal_index = opts.deal_index or 1,
        effective_target = opts.effective_target,
        active_named_contract = active_named,
    })
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

describe("app.session special contracts", function()
    describe("mizère", function()
        it("scores +120 when declarer takes zero tricks", function()
            local cfg = specials_config({ mizere = "on" })
            local s = session_at_tricks_named(cfg, mizere_hands_declarer_loses(), {
                dealer = 3, -- forehand = seat 1; seat 1 leads / wins everything
                declarer = 2,
                leader = 1,
                bid = { kind = "named", contract = "mizere", value = 120 },
            })
            assert.are.equal("mizere", s:active_named_contract().kind)
            play_sequence(s, mizere_sequence_seat1_sweeps())
            local payload = s:deal_done()
            assert.is_table(payload)
            assert.are.equal("scored", payload.reason)
            assert.is_true(payload.made_contract)
            assert.are.equal("mizere", payload.named_contract.kind)
            assert.are.equal(120, payload.named_contract.value)
            assert.are.equal(120, s:running_totals()[2])
            assert.are.equal(0, s:running_totals()[1])
            assert.are.equal(0, s:running_totals()[3])
        end)

        it("scores -120 when declarer takes any trick", function()
            -- Same hands, but force declarer to win one trick by leading
            -- their highest J at the right moment under the must-follow
            -- rule. Easier path: swap one card so declarer can capture.
            -- We construct a layout where declarer wins exactly one
            -- trick: seat 2 (declarer) holds the K of hearts to beat
            -- seat 3's Q; seats 1 and 3 capture the rest.
            local hands = {
                {
                    c("hearts", "9"),
                    c("diamonds", "A"),
                    c("clubs", "A"),
                    c("spades", "A"),
                    c("hearts", "J"),
                    c("diamonds", "K"),
                    c("clubs", "K"),
                    c("spades", "K"),
                },
                {
                    c("hearts", "K"), -- declarer's only winner
                    c("diamonds", "9"),
                    c("clubs", "9"),
                    c("spades", "9"),
                    c("hearts", "10"), -- declarer leads this first to win the trick
                    c("diamonds", "J"),
                    c("clubs", "J"),
                    c("spades", "J"),
                },
                {
                    c("hearts", "Q"),
                    c("diamonds", "10"),
                    c("clubs", "10"),
                    c("spades", "10"),
                    c("hearts", "A"),
                    c("diamonds", "Q"),
                    c("clubs", "Q"),
                    c("spades", "Q"),
                },
            }
            local cfg = specials_config({ mizere = "on" })
            local s = session_at_tricks_named(cfg, hands, {
                dealer = 1,
                declarer = 2,
                leader = 2,
                bid = { kind = "named", contract = "mizere", value = 120 },
            })
            -- Declarer leads h10; seat 3 plays hA; seat 1 plays h9 →
            -- seat 3 wins. Now seat 3 leads next.
            assert.is_true(s:play(2, c("hearts", "10")).ok)
            assert.is_true(s:play(3, c("hearts", "A")).ok)
            assert.is_true(s:play(1, c("hearts", "9")).ok)
            -- Seat 3 leads hQ (only hearts left). Must-follow: seat 1
            -- has hJ, seat 2 has hK. Must-beat fires for seat 1 (hJ
            -- > hQ? J=2, Q=3, so no — J is lower than Q under canonical
            -- rank). Seat 1 plays hJ; seat 2 plays hK (beats hQ) →
            -- declarer wins this trick.
            assert.is_true(s:play(3, c("hearts", "Q")).ok)
            assert.is_true(s:play(1, c("hearts", "J")).ok)
            assert.is_true(s:play(2, c("hearts", "K")).ok)
            -- Declarer (seat 2) now leads. We don't care about the
            -- remaining tricks for the failure assertion — declarer
            -- has already taken trick 2, breaking mizère. Play out
            -- whatever the engine accepts to reach deal_done.
            -- Declarer leads d9.
            assert.is_true(s:play(2, c("diamonds", "9")).ok)
            assert.is_true(s:play(3, c("diamonds", "10")).ok)
            assert.is_true(s:play(1, c("diamonds", "A")).ok)
            -- Seat 1 leads. Play through remaining 5 tricks letting
            -- seats 1 and 3 capture them.
            assert.is_true(s:play(1, c("clubs", "A")).ok)
            assert.is_true(s:play(2, c("clubs", "9")).ok)
            assert.is_true(s:play(3, c("clubs", "10")).ok)
            assert.is_true(s:play(1, c("spades", "A")).ok)
            assert.is_true(s:play(2, c("spades", "9")).ok)
            assert.is_true(s:play(3, c("spades", "10")).ok)
            assert.is_true(s:play(1, c("diamonds", "K")).ok)
            assert.is_true(s:play(2, c("diamonds", "J")).ok)
            assert.is_true(s:play(3, c("diamonds", "Q")).ok)
            assert.is_true(s:play(1, c("clubs", "K")).ok)
            assert.is_true(s:play(2, c("clubs", "J")).ok)
            assert.is_true(s:play(3, c("clubs", "Q")).ok)
            assert.is_true(s:play(1, c("spades", "K")).ok)
            assert.is_true(s:play(2, c("spades", "J")).ok)
            assert.is_true(s:play(3, c("spades", "Q")).ok)
            local payload = s:deal_done()
            assert.is_table(payload)
            assert.is_false(payload.made_contract)
            assert.are.equal(-120, s:running_totals()[2])
            assert.are.equal(0, s:running_totals()[1])
            assert.are.equal(0, s:running_totals()[3])
        end)

        it("blocks declare_marriage with marriages_disabled_in_mizere", function()
            -- Set up a deal where declarer has a marriage and is on
            -- lead; under mizère the declaration must be rejected.
            local hands = {
                {
                    c("clubs", "A"),
                    c("clubs", "K"),
                    c("clubs", "Q"),
                    c("clubs", "J"),
                    c("clubs", "10"),
                    c("clubs", "9"),
                    c("diamonds", "A"),
                    c("diamonds", "K"),
                },
                {
                    c("hearts", "K"),
                    c("hearts", "Q"), -- declarer holds a hearts marriage
                    c("hearts", "9"),
                    c("hearts", "J"),
                    c("hearts", "10"),
                    c("hearts", "A"),
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                },
                {
                    c("spades", "A"),
                    c("spades", "K"),
                    c("spades", "Q"),
                    c("spades", "J"),
                    c("spades", "10"),
                    c("spades", "9"),
                    c("diamonds", "Q"),
                    c("diamonds", "10"),
                },
            }
            local cfg = specials_config({ mizere = "on" })
            local s = session_at_tricks_named(cfg, hands, {
                dealer = 1,
                declarer = 2,
                leader = 2,
                bid = { kind = "named", contract = "mizere", value = 120 },
            })
            local res = s:declare_marriage(2, "hearts")
            assert.is_false(res.ok)
            assert.are.equal("marriages_disabled_in_mizere", res.error.code)
        end)
    end)

    describe("slam", function()
        it("scores +240 when declarer takes all 8 tricks", function()
            local cfg = specials_config({ slam_contract = "on" })
            local s = session_at_tricks_named(cfg, slam_hands_declarer_sweeps(), {
                dealer = 1,
                declarer = 2,
                leader = 2,
                bid = { kind = "named", contract = "slam", value = 240 },
            })
            assert.are.equal("slam", s:active_named_contract().kind)
            play_sequence(s, slam_sequence_declarer_sweeps())
            local payload = s:deal_done()
            assert.is_table(payload)
            assert.is_true(payload.made_contract)
            assert.are.equal("slam", payload.named_contract.kind)
            assert.are.equal(240, payload.named_contract.value)
            assert.are.equal(240, s:running_totals()[2])
            assert.are.equal(0, s:running_totals()[1])
            assert.are.equal(0, s:running_totals()[3])
        end)

        it("scores -240 when declarer takes fewer than all 8 tricks", function()
            -- Use the mizère-loser hands so declarer takes 0 tricks; a
            -- 0-trick result also fails the slam contract.
            local cfg = specials_config({ slam_contract = "on" })
            local s = session_at_tricks_named(cfg, mizere_hands_declarer_loses(), {
                dealer = 3,
                declarer = 2,
                leader = 1,
                bid = { kind = "named", contract = "slam", value = 240 },
            })
            play_sequence(s, mizere_sequence_seat1_sweeps())
            local payload = s:deal_done()
            assert.is_false(payload.made_contract)
            assert.are.equal(-240, s:running_totals()[2])
        end)

        it("respects a custom slam_contract_value sibling", function()
            local cfg = specials_config({ slam_contract = "on", slam_contract_value = 300 })
            local s = session_at_tricks_named(cfg, slam_hands_declarer_sweeps(), {
                dealer = 1,
                declarer = 2,
                leader = 2,
                bid = {
                    kind = "named",
                    contract = "slam",
                    value = cfg.specials.slam_contract_value,
                },
            })
            assert.are.equal(300, s:slam_contract_value())
            play_sequence(s, slam_sequence_declarer_sweeps())
            assert.are.equal(300, s:running_totals()[2])
        end)
    end)

    describe("open hand", function()
        it("scores +200 (doubled) when declarer captures opening_min points", function()
            local cfg = specials_config({ open_hand = "on" })
            local s = session_at_tricks_named(cfg, slam_hands_declarer_sweeps(), {
                dealer = 1,
                declarer = 2,
                leader = 2,
                bid = { kind = "named", contract = "open_hand", value = 200 },
            })
            assert.are.equal("open_hand", s:active_named_contract().kind)
            play_sequence(s, slam_sequence_declarer_sweeps())
            local payload = s:deal_done()
            assert.is_true(payload.made_contract)
            assert.are.equal(200, s:running_totals()[2])
        end)

        it("scores -200 when declarer captures fewer than opening_min points", function()
            local cfg = specials_config({ open_hand = "on" })
            local s = session_at_tricks_named(cfg, mizere_hands_declarer_loses(), {
                dealer = 3,
                declarer = 2,
                leader = 1,
                bid = { kind = "named", contract = "open_hand", value = 200 },
            })
            play_sequence(s, mizere_sequence_seat1_sweeps())
            local payload = s:deal_done()
            assert.is_false(payload.made_contract)
            assert.are.equal(-200, s:running_totals()[2])
        end)
    end)

    describe("mizère + slam mutators", function()
        it("Session:slam_contract_value reads from specials.slam_contract_value", function()
            local cfg = specials_config({ slam_contract = "on", slam_contract_value = 320 })
            local s = Session.new({ config = cfg, seed = 1 })
            assert.are.equal(320, s:slam_contract_value())
        end)

        it("Session:mizere_contract_value reads from specials.mizere_contract_value", function()
            local cfg = specials_config({ mizere = "on", mizere_contract_value = 100 })
            local s = Session.new({ config = cfg, seed = 1 })
            assert.are.equal(100, s:mizere_contract_value())
        end)

        it("Session:active_named_contract returns nil before any named bid", function()
            local cfg = specials_config({ mizere = "on" })
            local s = Session.new({ config = cfg, seed = 1 })
            assert.is_nil(s:active_named_contract())
        end)
    end)
end)
