-- Property-style invariant tests for the core engine.
--
-- For 200 deterministically-seeded deals (seed = 1..200), the suite walks
-- the full pipeline (deck → dealing → auction → talon → tricks) and
-- asserts two invariants on the trick layer's public API:
--
--   * Walk-only-legal — every card returned by `tricks.legal_cards` is
--     accepted by `tricks.play`. This proves the gatekeeper and the
--     player agree about what is currently legal.
--   * Reject-illegal  — at every step where the hand contains a card
--     NOT in `legal_cards`, that card is rejected by `tricks.play`
--     with one of the four named violation codes. This proves no
--     locally-illegal move can bypass the gate.
--
-- Determinism is sourced from `core.deck.shuffle(seed)`, which uses an
-- LCG over the seed (core/deck.lua:58-85). The illegal-probe is
-- read-only — it never advances state — so the legal walk continues
-- regardless of which probe is picked.
--
-- Trump is set to hearts up-front so must_trump / must_overtrump are
-- in scope for every seed (the trick layer accepts set_trump while
-- the trick has no plays, even though canonical-Russian narrative
-- rules defer trump until the first marriage; the invariant test
-- exercises the API contract, not the game-flow narrative).

local deck_module = require("core.deck")
local dealing = require("core.dealing")
local auction_module = require("core.auction")
local talon_module = require("core.talon")
local tricks_module = require("core.tricks")
local rule_config = require("core.rule_config")

local config = rule_config.canonical_russian
local DEALS = 200
local TRUMP = "hearts"

local NAMED_VIOLATIONS = {
    must_follow_violation = true,
    must_beat_violation = true,
    must_trump_violation = true,
    must_overtrump_violation = true,
    card_not_in_hand = true,
}

local function build_deal(seed)
    local d = deck_module.shuffle(deck_module.build(), seed)
    local result = dealing.deal(d, config)
    assert.is_true(result.ok, "seed " .. seed .. ": deal failed")
    return result.hands, result.talon
end

-- Forehand opens 100, the other two pass. Dealer = 1 → forehand = 2 →
-- declarer = 2, final_bid = 100. This is the canonical minimum-cost
-- auction script and is independent of the deal contents.
local function run_auction()
    local result = auction_module.new(config, 1)
    assert.is_true(result.ok, "auction.new must succeed")
    local a = result.auction
    result = auction_module.bid(a, 2, 100)
    assert.is_true(result.ok, "auction.bid(forehand 100) must succeed")
    a = result.auction
    result = auction_module.pass(a, 3)
    assert.is_true(result.ok, "auction.pass(player 3) must succeed")
    a = result.auction
    result = auction_module.pass(a, 1)
    assert.is_true(result.ok, "auction.pass(player 1) must succeed")
    a = result.auction
    assert.are.equal("done", a.status)
    assert.are.equal(2, a.declarer)
    return a
end

-- Take talon, pass first declarer-hand card to player 1, then first
-- declarer-hand card to player 3, then skip_raise. Returns the 8/8/8
-- post-talon hands.
local function run_talon(auction, hands, talon_cards)
    local result = talon_module.new(config, auction, hands, talon_cards)
    assert.is_true(result.ok, "talon.new must succeed")
    local t = result.talon

    result = talon_module.take(t)
    assert.is_true(result.ok, "talon.take must succeed")
    t = result.talon
    assert.are.equal("awaiting_pass", t.status)
    assert.are.equal(10, #t.hands[t.declarer])

    -- Pass first card from declarer's hand to player 1.
    local card_to_pass = t.hands[t.declarer][1]
    result = talon_module.pass(t, 1, card_to_pass)
    assert.is_true(result.ok, "talon.pass to player 1 must succeed")
    t = result.talon

    -- Pass next first card from declarer's hand to player 3.
    card_to_pass = t.hands[t.declarer][1]
    result = talon_module.pass(t, 3, card_to_pass)
    assert.is_true(result.ok, "talon.pass to player 3 must succeed")
    t = result.talon
    assert.are.equal("awaiting_raise", t.status)

    result = talon_module.skip_raise(t)
    assert.is_true(result.ok, "talon.skip_raise must succeed")
    t = result.talon
    assert.are.equal("done", t.status)

    for player = 1, 3 do
        assert.are.equal(8, #t.hands[player])
    end
    return t.hands
end

-- Pick the first card in hand that is NOT in legal_cards. Returns nil
-- when every card in hand is legal — in that case the illegal probe is
-- skipped for that step.
local function find_illegal_card(hand, legal_cards)
    local legal_set = {}
    for i = 1, #legal_cards do
        local c = legal_cards[i]
        legal_set[c.suit .. ":" .. c.rank] = true
    end
    for i = 1, #hand do
        local c = hand[i]
        if not legal_set[c.suit .. ":" .. c.rank] then
            return c
        end
    end
    return nil
end

-- Build a tricks state from the post-talon hands with trump = hearts so
-- must_trump / must_overtrump are exercised.
local function fresh_tricks(hands, leader)
    local result = tricks_module.new(config, hands, leader)
    assert.is_true(result.ok, "tricks.new must succeed")
    local t = result.tricks
    result = tricks_module.set_trump(t, TRUMP)
    assert.is_true(result.ok, "tricks.set_trump must succeed")
    return result.tricks
end

describe("core invariants", function()
    it("every legal move is accepted across " .. DEALS .. " fuzzed deals", function()
        for seed = 1, DEALS do
            local hands, talon_cards = build_deal(seed)
            local auction = run_auction()
            local post_talon_hands = run_talon(auction, hands, talon_cards)
            local state = fresh_tricks(post_talon_hands, auction.declarer)

            while state.status == "in_progress" do
                local p = state.next_to_play
                local legal_result = tricks_module.legal_cards(state, p)
                assert.is_true(
                    legal_result.ok,
                    "seed " .. seed .. ": legal_cards must succeed mid-deal"
                )
                local cards = legal_result.cards
                assert.is_true(
                    #cards >= 1,
                    "seed " .. seed .. ": legal_cards must always offer at least one card"
                )

                local pick_index = ((seed + state.tricks_played) % #cards) + 1
                local choice = cards[pick_index]

                local play_result = tricks_module.play(state, p, choice)
                assert.is_true(
                    play_result.ok,
                    "seed "
                        .. seed
                        .. ": legal card "
                        .. choice.suit
                        .. " "
                        .. choice.rank
                        .. " was rejected by play()"
                        .. (play_result.error and (" (" .. play_result.error.code .. ")") or "")
                )
                state = play_result.tricks
            end

            assert.are.equal("done", state.status, "seed " .. seed .. ": deal must complete")
            assert.are.equal(8, state.tricks_played, "seed " .. seed .. ": exactly 8 tricks played")

            local sum = state.captured_points[1]
                + state.captured_points[2]
                + state.captured_points[3]
            assert.are.equal(120, sum, "seed " .. seed .. ": captured points sum to 120")
        end
    end)

    it("every illegal move is rejected with a named code (" .. DEALS .. " seeded deals)", function()
        local probe_count = 0

        for seed = 1, DEALS do
            local hands, talon_cards = build_deal(seed)
            local auction = run_auction()
            local post_talon_hands = run_talon(auction, hands, talon_cards)
            local state = fresh_tricks(post_talon_hands, auction.declarer)

            while state.status == "in_progress" do
                local p = state.next_to_play
                local legal_result = tricks_module.legal_cards(state, p)
                local cards = legal_result.cards

                local illegal = find_illegal_card(state.hands[p], cards)
                if illegal ~= nil then
                    local probe = tricks_module.play(state, p, illegal)
                    assert.is_false(
                        probe.ok,
                        "seed "
                            .. seed
                            .. ": illegal card "
                            .. illegal.suit
                            .. " "
                            .. illegal.rank
                            .. " was accepted by play()"
                    )
                    assert.is_table(probe.error)
                    assert.is_string(probe.error.code)
                    assert.is_true(
                        NAMED_VIOLATIONS[probe.error.code] == true,
                        "seed "
                            .. seed
                            .. ": illegal play returned unrecognised code '"
                            .. probe.error.code
                            .. "'"
                    )
                    probe_count = probe_count + 1
                end

                local pick_index = ((seed + state.tricks_played) % #cards) + 1
                local choice = cards[pick_index]
                local play_result = tricks_module.play(state, p, choice)
                assert.is_true(play_result.ok, "seed " .. seed .. ": legal walk must succeed")
                state = play_result.tricks
            end

            assert.are.equal("done", state.status)
        end

        -- Sanity: across 200 seeded deals with trump set, the probe
        -- should fire many times. A zero count would mean find_illegal
        -- was silently broken.
        assert.is_true(
            probe_count > 0,
            "expected at least one illegal-card probe across "
                .. DEALS
                .. " seeded deals; got "
                .. probe_count
        )
    end)
end)
