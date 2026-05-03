-- End-to-end scripted deal: deck → dealing → auction → talon →
-- marriages → tricks → scoring → advance_game.
--
-- Two variants exercise the core pipeline:
--
--   * Variant A — minimum auction (forehand opens 100, others pass),
--     no marriages, no trump. Player 2 declares without trump and
--     loses the contract.
--   * Variant B — contested auction up to the pre-talon cap of 120,
--     declarer holds a spades marriage, declares it on the lead of
--     trick 2 (after declaring on lead by playing K♠ on trick 1; the
--     trump kicks in from trick 2 per the trump-flip-from-next-trick
--     rule). Declarer fails the 120 contract because spades = 40
--     bonus is not enough to cover the gap.
--
-- Both variants are deterministic via `core.deck.shuffle(seed)`. The
-- final running totals are pinned snapshots, captured by running the
-- pipeline once and copying the actual numbers in. They will only
-- change if the engine itself changes — which is the point.

local deck_module = require("core.deck")
local dealing = require("core.dealing")
local auction_module = require("core.auction")
local talon_module = require("core.talon")
local marriages_module = require("core.marriages")
local tricks_module = require("core.tricks")
local scoring = require("core.scoring")
local rule_config = require("core.rule_config")
local json = require("app.json")

-- The full-deal scripted scenario declares its spades marriage at the
-- start of the tricks phase (before any trick has been captured), so
-- it runs under a config with the canonical `marriages.trick_required
-- = "on"` gate switched off. The gate itself is exercised by
-- tests/spec/core/marriages_spec.lua and the session-level marriage
-- variants spec.
local function trickless_canonical()
    local blob = json.decode(rule_config.to_json(rule_config.canonical_russian))
    blob.marriages.trick_required = "off"
    return rule_config.new(blob)
end

local config = trickless_canonical()

local function build_deck(seed)
    return deck_module.shuffle(deck_module.build(), seed)
end

local function find_in_hand(hand, suit, rank)
    for _, c in ipairs(hand) do
        if c.suit == suit and c.rank == rank then
            return c
        end
    end
    return nil
end

local function captured_sum(state)
    return state.captured_points[1] + state.captured_points[2] + state.captured_points[3]
end

describe("core full-deal integration", function()
    it("variant A: forehand-opens-pass-pass auction, no marriages, no trump", function()
        local d = build_deck(42)

        -- Step 1: deal.
        local deal_result = dealing.deal(d, config)
        assert.is_true(deal_result.ok)
        local hands, talon_cards = deal_result.hands, deal_result.talon
        assert.are.equal(7, #hands[1])
        assert.are.equal(7, #hands[2])
        assert.are.equal(7, #hands[3])
        assert.are.equal(3, #talon_cards)

        -- Step 2: auction. Dealer = 1 → forehand = 2.
        local a = auction_module.new(config, 1).auction
        a = auction_module.bid(a, 2, 100).auction
        a = auction_module.pass(a, 3).auction
        a = auction_module.pass(a, 1).auction
        assert.are.equal("done", a.status)
        assert.are.equal(2, a.declarer)
        assert.are.equal(100, a.final_bid)

        -- Step 3: talon. Declarer takes (10 / 7 / 7), passes one card to
        -- each opponent (8 / 8 / 8), skips the post-talon raise.
        local t = talon_module.new(config, a, hands, talon_cards).talon
        t = talon_module.take(t).talon
        assert.are.equal("awaiting_pass", t.status)
        assert.are.equal(10, #t.hands[2])
        assert.are.equal(7, #t.hands[1])
        assert.are.equal(7, #t.hands[3])

        local pass1 = t.hands[2][1]
        t = talon_module.pass(t, 1, pass1).talon
        local pass2 = t.hands[2][1]
        t = talon_module.pass(t, 3, pass2).talon
        assert.are.equal("awaiting_raise", t.status)

        t = talon_module.skip_raise(t).talon
        assert.are.equal("done", t.status)
        for player = 1, 3 do
            assert.are.equal(8, #t.hands[player])
        end

        -- Step 4: marriages. None declared in this variant.
        local m = marriages_module.new(config).marriages
        assert.is_nil(m.trump)
        assert.are.same({ 0, 0, 0 }, m.bonuses)

        -- Step 5: tricks. Walk 8 tricks picking legal_cards[1].
        local s = tricks_module.new(config, t.hands, 2).tricks
        while s.status == "in_progress" do
            local p = s.next_to_play
            local choice = tricks_module.legal_cards(s, p).cards[1]
            s = tricks_module.play(s, p, choice).tricks
        end
        assert.are.equal("done", s.status)
        assert.are.equal(8, s.tricks_played)
        assert.are.equal(120, captured_sum(s))
        -- Snapshot from a one-time pipeline run; updates require a code
        -- change in core/, not a test fixup.
        assert.are.same({ 65, 24, 31 }, s.captured_points)
        assert.are.same({ 5, 1, 2 }, s.tricks_won)

        -- Step 6: score the deal. Declarer's deal_score = 25 (rounded
        -- from 24) + 0 marriage bonus = 25, well under the 100 bid →
        -- contract failed → declarer's delta = -100. Defenders add
        -- their rounded card points (65 and 30).
        local sd = scoring.score_deal(config, {
            declarer = 2,
            bid = 100,
            captured_points = s.captured_points,
            marriage_bonuses = m.bonuses,
            running_totals = { 0, 0, 0 },
        }).scoring
        assert.are.same({ 65, 25, 30 }, sd.card_points_rounded)
        assert.are.same({ 65, 25, 30 }, sd.deal_scores)
        assert.is_false(sd.made_contract)
        assert.are.same({ 65, -100, 30 }, sd.deltas)

        -- Step 7: advance the game. Nobody crosses the barrel threshold
        -- on deal 1 with these scores, so winner is nil and barrel
        -- state stays off-barrel for everyone.
        local g = scoring.advance_game(config, {
            declarer = 2,
            deal_index = 1,
            deltas = sd.deltas,
            running_totals_before = { 0, 0, 0 },
            barrel_state_before = scoring.initial_barrel_state(config),
        }).game
        assert.are.same({ 65, -100, 30 }, g.running_totals)
        assert.is_nil(g.winner)
        for player = 1, 3 do
            assert.is_false(g.barrel_state[player].on_barrel)
        end
    end)

    it("variant B: contested auction, declarer fails 120 with a spades marriage", function()
        -- seed=1 gives player 2 a spades K+Q after taking the talon.
        local d = build_deck(1)

        local deal_result = dealing.deal(d, config)
        assert.is_true(deal_result.ok)
        local hands, talon_cards = deal_result.hands, deal_result.talon

        -- Auction climbs to the pre-talon ceiling 120.
        --   forehand=2 opens 100 → 3 raises to 105 → 1 passes →
        --   2 raises to 120 → 3 passes → declarer=2, final_bid=120.
        local a = auction_module.new(config, 1).auction
        a = auction_module.bid(a, 2, 100).auction
        a = auction_module.bid(a, 3, 105).auction
        a = auction_module.pass(a, 1).auction
        a = auction_module.bid(a, 2, 120).auction
        a = auction_module.pass(a, 3).auction
        assert.are.equal("done", a.status)
        assert.are.equal(2, a.declarer)
        assert.are.equal(120, a.final_bid)

        local t = talon_module.new(config, a, hands, talon_cards).talon
        t = talon_module.take(t).talon

        -- Declarer holds a spades marriage in the 10-card hand.
        local detected = marriages_module.detect(t.hands[2])
        assert.are.equal(1, #detected)
        assert.are.equal("spades", detected[1])
        local marriage_suit = detected[1]

        -- Pass cards that are NOT K♠ / Q♠ so the marriage survives.
        local function safe_pass_card(hand)
            for _, c in ipairs(hand) do
                if not (c.suit == marriage_suit and (c.rank == "K" or c.rank == "Q")) then
                    return c
                end
            end
            error("no safe pass card available")
        end

        t = talon_module.pass(t, 1, safe_pass_card(t.hands[2])).talon
        t = talon_module.pass(t, 3, safe_pass_card(t.hands[2])).talon
        t = talon_module.skip_raise(t).talon
        assert.are.equal("done", t.status)
        assert.is_truthy(find_in_hand(t.hands[2], marriage_suit, "K"))
        assert.is_truthy(find_in_hand(t.hands[2], marriage_suit, "Q"))

        -- Declare the marriage on the lead. The bonus posts immediately;
        -- the trump only kicks in from the *next* trick — the lead trick
        -- is still played under no-trump.
        local m = marriages_module.new(config).marriages
        m = marriages_module.declare(m, 2, marriage_suit, t.hands[2]).marriages
        assert.are.equal(marriage_suit, m.trump)
        assert.are.same({ 0, 40, 0 }, m.bonuses)

        local s = tricks_module.new(config, t.hands, 2).tricks
        assert.is_nil(s.trump)

        -- Trick 1: declarer leads K♠. Other players play legal_cards[1].
        local king_of_marriage = find_in_hand(s.hands[2], marriage_suit, "K")
        s = tricks_module.play(s, 2, king_of_marriage).tricks
        s = tricks_module.play(s, 3, tricks_module.legal_cards(s, 3).cards[1]).tricks
        s = tricks_module.play(s, 1, tricks_module.legal_cards(s, 1).cards[1]).tricks
        assert.are.equal(1, s.tricks_played)

        -- Trump flips for trick 2 onward.
        s = tricks_module.set_trump(s, marriage_suit).tricks
        assert.are.equal(marriage_suit, s.trump)

        -- Walk remaining tricks via legal_cards[1].
        while s.status == "in_progress" do
            local p = s.next_to_play
            local choice = tricks_module.legal_cards(s, p).cards[1]
            s = tricks_module.play(s, p, choice).tricks
        end
        assert.are.equal("done", s.status)
        assert.are.equal(8, s.tricks_played)
        assert.are.equal(120, captured_sum(s))
        -- Snapshot from a one-time pipeline run.
        assert.are.same({ 13, 47, 60 }, s.captured_points)
        assert.are.same({ 1, 3, 4 }, s.tricks_won)

        local sd = scoring.score_deal(config, {
            declarer = 2,
            bid = 120,
            captured_points = s.captured_points,
            marriage_bonuses = m.bonuses,
            running_totals = { 0, 0, 0 },
        }).scoring
        -- 47 captured points round to 45; declarer's deal_score is
        -- 45 + 40 (spades bonus) = 85, below the 120 bid → contract
        -- failed → declarer's delta = -120.
        assert.are.same({ 15, 45, 60 }, sd.card_points_rounded)
        assert.are.same({ 15, 85, 60 }, sd.deal_scores)
        assert.is_false(sd.made_contract)
        assert.are.same({ 15, -120, 60 }, sd.deltas)

        local g = scoring.advance_game(config, {
            declarer = 2,
            deal_index = 1,
            deltas = sd.deltas,
            running_totals_before = { 0, 0, 0 },
            barrel_state_before = scoring.initial_barrel_state(config),
        }).game
        assert.are.same({ 15, -120, 60 }, g.running_totals)
        assert.is_nil(g.winner)
        for player = 1, 3 do
            assert.is_false(g.barrel_state[player].on_barrel)
        end
    end)
end)
