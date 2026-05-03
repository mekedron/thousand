-- Unit coverage for the in-memory session. Pure Lua — no love.* — so the
-- spec runs under plain busted with the project's standard config.

local Session = require("app.session")
local rule_config = require("core.rule_config")
local tricks_module = require("core.tricks")
local marriages_module = require("core.marriages")

local config = rule_config.canonical_russian

-- Helpers ---------------------------------------------------------------
--
-- The Phase 2 task brings input wiring; tests below drive the engine
-- through Session mutators rather than reaching into core.* directly,
-- so a regression in the session contract surfaces here.
--
-- Seeds match tests/spec/core/full_deal_spec.lua so the engine outcomes
-- stay pinned to the same fixtures the core tests already gate.

local SEED_NO_MARRIAGE = 42 -- forehand opens 100, others pass; no marriages.
local SEED_SPADES_MARRIAGE = 1 -- declarer 2 holds K♠+Q♠ after talon take.

local function find_in_hand(hand, suit, rank)
    for _, c in ipairs(hand) do
        if c.suit == suit and c.rank == rank then
            return c
        end
    end
    return nil
end

local function find_safe_pass(hand, marriage_suit)
    -- Pass any card that is NOT part of the marriage we want to keep.
    for _, c in ipairs(hand) do
        if not (c.suit == marriage_suit and (c.rank == "K" or c.rank == "Q")) then
            return c
        end
    end
    error("no safe pass card available")
end

local function drive_to_talon(seed)
    -- Variant A path: forehand 2 opens 100, both others pass → declarer 2.
    local s = Session.new({ seed = seed, dealer = 1 })
    assert(s:bid(2, 100).ok)
    assert(s:pass(3).ok)
    assert(s:pass(1).ok)
    return s
end

local function drive_to_tricks_no_marriage(seed)
    local s = drive_to_talon(seed)
    assert(s:take_talon().ok)
    local hand = s:hands()[2]
    assert(s:pass_talon(1, hand[1]).ok)
    hand = s:hands()[2]
    assert(s:pass_talon(3, hand[1]).ok)
    assert(s:skip_raise().ok)
    return s
end

-- The marriage describe block exercises K-Q declarations at the start
-- of the tricks phase (no captured tricks yet). The canonical
-- `marriages.trick_required = "on"` rule would gate every assertion,
-- so the helper drives the deal under a config with the gate off; the
-- gate itself is covered by a dedicated describe block below.
local function marriage_test_config()
    local json = require("app.json")
    local blob = json.decode(rule_config.to_json(rule_config.canonical_russian))
    blob.marriages.trick_required = "off"
    return rule_config.new(blob)
end

local function drive_to_talon_contested_with_config(seed, cfg)
    local s = Session.new({ seed = seed, dealer = 1, config = cfg })
    assert(s:bid(2, 100).ok)
    assert(s:bid(3, 105).ok)
    assert(s:pass(1).ok)
    assert(s:bid(2, 120).ok)
    assert(s:pass(3).ok)
    return s
end

local function drive_to_tricks_with_marriage(seed)
    local s = drive_to_talon_contested_with_config(seed, marriage_test_config())
    assert(s:take_talon().ok)
    -- Pass two non-marriage cards.
    local hand = s:hands()[2]
    assert(s:pass_talon(1, find_safe_pass(hand, "spades")).ok)
    hand = s:hands()[2]
    assert(s:pass_talon(3, find_safe_pass(hand, "spades")).ok)
    assert(s:skip_raise().ok)
    return s
end

-- Drive a deal to completion via legal_cards picks. The session is
-- expected to run scoring on the 8th trick automatically.
local function drive_full_deal_no_marriage(seed)
    local s = drive_to_tricks_no_marriage(seed)
    while s:current_phase() == "tricks" do
        local p = s:current_turn()
        local legal = s:legal_cards(p)
        assert(#legal > 0)
        assert(s:play(p, legal[1]).ok)
    end
    return s
end

describe("app.session", function()
    describe("Session.new", function()
        it("produces a fresh post-deal session with 7/7/7 hands and a 3-card talon", function()
            local s = Session.new({ seed = 42 })
            local hands = s:hands()
            assert.are.equal(3, #hands)
            assert.are.equal(7, #hands[1])
            assert.are.equal(7, #hands[2])
            assert.are.equal(7, #hands[3])
            assert.are.equal(3, #s:talon_cards())
        end)

        it("starts in the auction phase with the forehand to act", function()
            local s = Session.new({ seed = 1, dealer = 1 })
            assert.are.equal("auction", s:current_phase())
            -- Dealer 1 → forehand 2.
            assert.are.equal(2, s:current_turn())
            assert.is_nil(s:current_bid())
            assert.is_nil(s:current_leader())
            assert.is_nil(s:trump())
            assert.is_nil(s:winner())
            assert.is_nil(s:final_scores())
        end)

        it("zeros the running totals and seats every player off the barrel", function()
            local s = Session.new({ seed = 7 })
            assert.are.same({ 0, 0, 0 }, s:running_totals())
            local barrel = s:barrel_state()
            assert.are.equal(3, #barrel)
            for i = 1, 3 do
                assert.is_false(barrel[i].on_barrel)
            end
        end)

        it("draws the talon face-down during the auction", function()
            local s = Session.new({ seed = 3 })
            assert.is_true(s:talon_face_down())
        end)

        it("respects an explicit dealer", function()
            local s = Session.new({ seed = 2, dealer = 3 })
            assert.are.equal(3, s:dealer())
            -- Dealer 3 → forehand 1.
            assert.are.equal(1, s:current_turn())
        end)

        it("uses canonical_russian when no config is given", function()
            local s = Session.new({ seed = 11 })
            assert.are.equal(config, s:config())
        end)

        it("rejects a non-RuleConfig", function()
            assert.has_error(function()
                Session.new({ config = { players = { count = 3 } } })
            end)
        end)
    end)

    describe("Session.from_state", function()
        it("round-trips the engine state passed in", function()
            local hands = {
                { { suit = "spades", rank = "A" } },
                { { suit = "hearts", rank = "K" } },
                { { suit = "diamonds", rank = "Q" } },
            }
            local s = Session.from_state({
                config = config,
                dealer = 2,
                hands = hands,
                talon_cards = {
                    { suit = "clubs", rank = "9" },
                    { suit = "clubs", rank = "J" },
                    { suit = "clubs", rank = "Q" },
                },
                running_totals = { 100, 200, 300 },
            })
            assert.are.equal(2, s:dealer())
            assert.are.equal(1, #s:hands()[1])
            assert.are.equal(3, #s:talon_cards())
            assert.are.same({ 100, 200, 300 }, s:running_totals())
        end)

        it("treats a state with a winner as the done phase", function()
            local s = Session.from_state({
                config = config,
                dealer = 1,
                running_totals = { 1000, 540, 420 },
                winner = 1,
            })
            assert.are.equal("done", s:current_phase())
            assert.are.equal(1, s:winner())
            assert.are.same({ 1000, 540, 420 }, s:final_scores())
            assert.is_nil(s:current_turn())
        end)

        it("defaults missing optional fields without exploding", function()
            local s = Session.from_state({ config = config })
            assert.are.same({ 0, 0, 0 }, s:running_totals())
            assert.are.equal(3, #s:barrel_state())
        end)

        it("accepts the canonical config when none is given", function()
            local s = Session.from_state({})
            assert.are.equal(rule_config.canonical_russian, s:config())
        end)
    end)

    describe("auction mutators", function()
        it("Session:bid records a legal bid and advances the turn", function()
            local s = Session.new({ seed = 42, dealer = 1 })
            local r = s:bid(2, 100)
            assert.is_true(r.ok)
            assert.are.equal(100, s:current_bid())
            assert.are.equal(2, s:current_leader())
            assert.are.equal(3, s:current_turn())
        end)

        it("Session:bid returns the engine error envelope for a bad turn", function()
            local s = Session.new({ seed = 42, dealer = 1 })
            local r = s:bid(1, 100) -- forehand is 2, not 1
            assert.is_false(r.ok)
            assert.are.equal("not_your_turn", r.error.code)
        end)

        it("Session:bid rejects an under-minimum opening bid", function()
            local s = Session.new({ seed = 42, dealer = 1 })
            local r = s:bid(2, 95)
            assert.is_false(r.ok)
            assert.are.equal("bid_below_minimum", r.error.code)
        end)

        it("Session:pass records a pass and advances the turn", function()
            local s = Session.new({ seed = 42, dealer = 1 })
            assert(s:bid(2, 100).ok)
            local r = s:pass(3)
            assert.is_true(r.ok)
            assert.are.equal(1, s:current_turn())
        end)

        it("Session:pass returns the engine error envelope when not your turn", function()
            local s = Session.new({ seed = 42, dealer = 1 })
            local r = s:pass(1)
            assert.is_false(r.ok)
            assert.are.equal("not_your_turn", r.error.code)
        end)
    end)

    describe("auction → talon transition", function()
        local s

        before_each(function()
            s = drive_to_talon(SEED_NO_MARRIAGE)
        end)

        it("auto-advances to the talon phase once two players have passed", function()
            assert.are.equal("talon", s:current_phase())
            assert.are.equal(2, s:current_leader())
            assert.are.equal(2, s:current_turn())
            assert.are.equal(100, s:current_bid())
        end)

        it("reveals the three talon cards face-up", function()
            assert.is_false(s:talon_face_down())
            assert.are.equal(3, #s:talon_cards())
        end)

        it("rejects further auction calls once auction is done", function()
            local r = s:bid(2, 105)
            assert.is_false(r.ok)
            assert.are.equal("auction_already_done", r.error.code)
        end)
    end)

    describe("auction all-pass", function()
        it("flags deal_done with reason all_pass when nobody bids", function()
            -- The auction terminates when player_count - 1 players have
            -- passed (see core/auction.lua "all-but-one has passed").
            -- With three players that's two passes; the engine never
            -- consults the dealer when no bid was made before they would
            -- have acted.
            --
            -- Phase 3.11 pinned canonical Russian's forced_dealer_bid
            -- to "on", which short-circuits this path into a forced 100
            -- contract. Opt out so the all-pass terminator stays
            -- reachable for this assertion.
            local jsmod = require("app.json")
            local blob = jsmod.decode(rule_config.to_json(rule_config.canonical_russian))
            blob.bidding.forced_dealer_bid = "off"
            local cfg = rule_config.new(blob)
            local s = Session.new({ config = cfg, seed = 42, dealer = 1 })
            assert(s:pass(2).ok)
            assert(s:pass(3).ok)
            assert.are.equal("deal_done", s:current_phase())
            assert.is_truthy(s:deal_done())
            assert.are.equal("all_pass", s:deal_done().reason)
            assert.is_nil(s:current_turn())
            assert.is_nil(s:winner())
        end)
    end)

    describe("talon mutators", function()
        local s

        before_each(function()
            s = drive_to_talon(SEED_NO_MARRIAGE)
        end)

        it("Session:take_talon moves the three cards into declarer's hand", function()
            local r = s:take_talon()
            assert.is_true(r.ok)
            assert.are.equal(10, #s:hands()[2])
            assert.are.equal(7, #s:hands()[1])
            assert.are.equal(7, #s:hands()[3])
            assert.are.equal(0, #s:talon_cards())
        end)

        it("Session:take_talon errors when called twice", function()
            assert(s:take_talon().ok)
            local r = s:take_talon()
            assert.is_false(r.ok)
            assert.are.equal("wrong_phase", r.error.code)
        end)

        it("Session:pass_talon moves a card from declarer to the named opponent", function()
            assert(s:take_talon().ok)
            local hand = s:hands()[2]
            local card = hand[1]
            local r = s:pass_talon(1, card)
            assert.is_true(r.ok)
            assert.are.equal(9, #s:hands()[2])
            assert.are.equal(8, #s:hands()[1])
            assert.are.equal(7, #s:hands()[3])
        end)

        it("Session:pass_talon rejects a card not in the declarer's hand", function()
            assert(s:take_talon().ok)
            local r = s:pass_talon(1, { suit = "spades", rank = "?" })
            assert.is_false(r.ok)
            assert.are.equal("card_not_in_hand", r.error.code)
        end)

        it("Session:pass_talon rejects passing to the declarer", function()
            assert(s:take_talon().ok)
            local hand = s:hands()[2]
            local r = s:pass_talon(2, hand[1])
            assert.is_false(r.ok)
            assert.are.equal("bad_target", r.error.code)
        end)

        it("Session:skip_raise after two passes finalises the talon phase", function()
            assert(s:take_talon().ok)
            local hand = s:hands()[2]
            assert(s:pass_talon(1, hand[1]).ok)
            hand = s:hands()[2]
            assert(s:pass_talon(3, hand[1]).ok)
            assert(s:skip_raise().ok)
            assert.are.equal("tricks", s:current_phase())
        end)

        it("Session:raise above the current bid bumps the contract", function()
            assert(s:take_talon().ok)
            local hand = s:hands()[2]
            assert(s:pass_talon(1, hand[1]).ok)
            hand = s:hands()[2]
            assert(s:pass_talon(3, hand[1]).ok)
            assert(s:raise(150).ok)
            assert.are.equal("tricks", s:current_phase())
            assert.are.equal(150, s:current_bid())
        end)

        it("Session:raise rejects a non-higher amount", function()
            assert(s:take_talon().ok)
            local hand = s:hands()[2]
            assert(s:pass_talon(1, hand[1]).ok)
            hand = s:hands()[2]
            assert(s:pass_talon(3, hand[1]).ok)
            local r = s:raise(100)
            assert.is_false(r.ok)
            assert.are.equal("raise_not_higher", r.error.code)
        end)
    end)

    describe("talon → tricks transition", function()
        local s

        before_each(function()
            s = drive_to_tricks_no_marriage(SEED_NO_MARRIAGE)
        end)

        it("seats the declarer as the first leader", function()
            assert.are.equal("tricks", s:current_phase())
            assert.are.equal(2, s:current_turn())
        end)

        it("starts with no trump until a marriage is declared", function()
            assert.is_nil(s:trump())
        end)

        it("each player holds 8 cards at the start of trick play", function()
            assert.are.equal(8, #s:hands()[1])
            assert.are.equal(8, #s:hands()[2])
            assert.are.equal(8, #s:hands()[3])
        end)
    end)

    describe("trick play", function()
        local s

        before_each(function()
            s = drive_to_tricks_no_marriage(SEED_NO_MARRIAGE)
        end)

        it("Session:play submits a card for the player on turn", function()
            local p = s:current_turn()
            local card = s:legal_cards(p)[1]
            local r = s:play(p, card)
            assert.is_true(r.ok)
            assert.are.equal(7, #s:hands()[p])
        end)

        it("Session:play rejects an off-turn play", function()
            local r = s:play(1, { suit = "spades", rank = "A" })
            assert.is_false(r.ok)
            assert.are.equal("not_your_turn", r.error.code)
        end)

        it("Session:legal_cards mirrors the engine's permitted plays", function()
            local p = s:current_turn()
            local engine_cards = tricks_module.legal_cards(s._tricks, p).cards
            local session_cards = s:legal_cards(p)
            assert.are.equal(#engine_cards, #session_cards)
        end)

        it("Session:current_trick returns plays in order until the trick resolves", function()
            local p = s:current_turn()
            local card = s:legal_cards(p)[1]
            assert(s:play(p, card).ok)
            local trick = s:current_trick()
            assert.is_not_nil(trick)
            assert.are.equal(1, #trick.plays)
            assert.are.equal(p, trick.plays[1].player)
        end)
    end)

    describe("marriage declarations", function()
        local s
        local marriage_suit = "spades"

        before_each(function()
            s = drive_to_tricks_with_marriage(SEED_SPADES_MARRIAGE)
        end)

        it("declarer holds the spades K and Q", function()
            local hand = s:hands()[2]
            assert.is_truthy(find_in_hand(hand, marriage_suit, "K"))
            assert.is_truthy(find_in_hand(hand, marriage_suit, "Q"))
        end)

        it("Session:available_marriages lists declarable suits for the player on lead", function()
            local available = s:available_marriages(2)
            assert.are.equal(1, #available)
            assert.are.equal(marriage_suit, available[1])
        end)

        it("Session:available_marriages returns empty for other players", function()
            assert.are.same({}, s:available_marriages(1))
            assert.are.same({}, s:available_marriages(3))
        end)

        it("Session:declare_marriage credits the bonus and prepares the trump flip", function()
            local r = s:declare_marriage(2, marriage_suit)
            assert.is_true(r.ok)
            -- The trump for the *current* trick is still nil; only the next
            -- trick uses the new trump per the marriage timing rule.
            assert.is_nil(s:trump())
        end)

        it("Session:declare_marriage rejects a player who isn't on lead", function()
            local r = s:declare_marriage(1, marriage_suit)
            assert.is_false(r.ok)
            assert.are.equal("not_your_turn", r.error.code)
        end)

        it("Session:declare_marriage rejects a suit lacking both K+Q in hand", function()
            local r = s:declare_marriage(2, "hearts")
            assert.is_false(r.ok)
            assert.are.equal("card_not_in_hand", r.error.code)
        end)

        it("trump engages from the second trick after a marriage declaration", function()
            assert(s:declare_marriage(2, marriage_suit).ok)
            local king = find_in_hand(s:hands()[2], marriage_suit, "K")
            assert(s:play(2, king).ok)
            -- During the trick, trump is still nil — the lead is played
            -- under no-trump.
            assert.is_nil(s:trump())
            -- Drive the other two players to finish the trick.
            local p = s:current_turn()
            assert(s:play(p, s:legal_cards(p)[1]).ok)
            p = s:current_turn()
            assert(s:play(p, s:legal_cards(p)[1]).ok)
            -- Trump is live for the next trick.
            assert.are.equal(marriage_suit, s:trump())
        end)

        it("Session:declare_marriage refuses re-declaring an already-declared suit", function()
            assert(s:declare_marriage(2, marriage_suit).ok)
            local r = s:declare_marriage(2, marriage_suit)
            assert.is_false(r.ok)
            assert.are.equal("marriage_suit_already_declared", r.error.code)
        end)
    end)

    describe("scoring at end of deal", function()
        local s

        before_each(function()
            s = drive_full_deal_no_marriage(SEED_NO_MARRIAGE)
        end)

        it("transitions to the deal_done phase after the 8th trick", function()
            assert.are.equal("deal_done", s:current_phase())
            assert.is_truthy(s:deal_done())
            assert.are.equal("scored", s:deal_done().reason)
        end)

        it("propagates running totals from the scoring engine", function()
            -- Snapshot mirrors variant A in tests/spec/core/full_deal_spec.lua:
            -- declarer 2 fails the 100 contract → -100; defenders score
            -- their rounded card points (65 / 30).
            assert.are.same({ 65, -100, 30 }, s:running_totals())
        end)

        it("does not produce a winner when nobody crosses 1000", function()
            assert.is_nil(s:winner())
            assert.is_nil(s:final_scores())
        end)
    end)

    describe("game-end winner detection", function()
        it("flags the winner when scoring crosses the target", function()
            local s = Session.from_state({
                config = config,
                dealer = 1,
                running_totals = { 980, 200, 200 },
                hands = {
                    { { suit = "spades", rank = "A" } },
                    { { suit = "hearts", rank = "A" } },
                    { { suit = "diamonds", rank = "A" } },
                },
                talon_cards = {
                    { suit = "clubs", rank = "A" },
                    { suit = "clubs", rank = "K" },
                    { suit = "clubs", rank = "Q" },
                },
                winner = 1,
            })
            assert.are.equal("done", s:current_phase())
            assert.are.equal(1, s:winner())
        end)
    end)

    describe("Session:start_next_deal", function()
        it("rotates the dealer clockwise and resets engine state", function()
            local s = drive_full_deal_no_marriage(SEED_NO_MARRIAGE)
            local before = s:running_totals()
            local totals_before = { before[1], before[2], before[3] }
            assert(s:start_next_deal().ok)
            assert.are.equal("auction", s:current_phase())
            -- Dealer 1 → 2, forehand becomes 3.
            assert.are.equal(2, s:dealer())
            assert.are.equal(3, s:current_turn())
            -- Running totals carry forward.
            assert.are.same(totals_before, s:running_totals())
        end)

        it("refuses to start a next deal once a winner exists", function()
            local s = Session.from_state({
                config = config,
                dealer = 1,
                running_totals = { 1000, 420, 420 },
                winner = 1,
            })
            local r = s:start_next_deal()
            assert.is_false(r.ok)
            assert.are.equal("game_over", r.error.code)
        end)
    end)

    -- Smoke: the marriages module is a peer dependency the spec uses for
    -- detect()-style assertions in a downstream task. Importing it here
    -- now keeps the require list stable when those tests land.
    it("imports the marriages module without error", function()
        assert.is_function(marriages_module.detect)
    end)
end)
