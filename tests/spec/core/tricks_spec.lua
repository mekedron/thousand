local tricks = require("core.tricks")
local card = require("core.card")
local rule_config = require("core.rule_config")

local config = rule_config.canonical_russian

local function c(suit, rank)
    return card.new(suit, rank)
end

-- Build three valid 8-card hands. The 24 cards span every suit/rank pair so
-- the deck invariant holds across the deal. The split is deterministic.
local function default_hands()
    return {
        {
            c("hearts", "9"),
            c("hearts", "J"),
            c("hearts", "Q"),
            c("diamonds", "9"),
            c("diamonds", "J"),
            c("clubs", "9"),
            c("spades", "9"),
            c("spades", "J"),
        },
        {
            c("hearts", "K"),
            c("hearts", "10"),
            c("diamonds", "Q"),
            c("diamonds", "K"),
            c("clubs", "J"),
            c("clubs", "Q"),
            c("spades", "Q"),
            c("spades", "K"),
        },
        {
            c("hearts", "A"),
            c("diamonds", "10"),
            c("diamonds", "A"),
            c("clubs", "K"),
            c("clubs", "10"),
            c("clubs", "A"),
            c("spades", "10"),
            c("spades", "A"),
        },
    }
end

local function fresh_tricks(leader)
    local result = tricks.new(config, default_hands(), leader or 1)
    assert.is_true(result.ok, "fixture: tricks.new must succeed")
    return result.tricks
end

local function play_ok(state, player, played)
    local result = tricks.play(state, player, played)
    assert.is_true(
        result.ok,
        "fixture: play must succeed (got " .. (result.error and result.error.code or "?") .. ")"
    )
    return result.tricks
end

local function set_trump_ok(state, suit)
    local result = tricks.set_trump(state, suit)
    assert.is_true(
        result.ok,
        "fixture: set_trump must succeed (got "
            .. (result.error and result.error.code or "?")
            .. ")"
    )
    return result.tricks
end

local function find_in_hand(hand, suit, rank)
    for i = 1, #hand do
        if hand[i].suit == suit and hand[i].rank == rank then
            return hand[i]
        end
    end
    error("test fixture: no " .. rank .. " of " .. suit .. " in hand")
end

describe("core.tricks", function()
    describe("module shape", function()
        it("exposes the documented public surface", function()
            assert.is_function(tricks.new)
            assert.is_function(tricks.play)
            assert.is_function(tricks.set_trump)
            assert.is_function(tricks.legal_cards)
            assert.is_function(tricks.is_tricks)
            assert.is_number(tricks.SCHEMA_VERSION)
        end)
    end)

    describe("new()", function()
        it("rejects a non-RuleConfig", function()
            for _, bad in ipairs({ 42, "config", {}, true }) do
                local result = tricks.new(bad, default_hands(), 1)
                assert.is_false(result.ok)
                assert.are.equal("not_a_rule_config", result.error.code)
            end
            local nil_result = tricks.new(nil, default_hands(), 1)
            assert.is_false(nil_result.ok)
            assert.are.equal("not_a_rule_config", nil_result.error.code)
        end)

        it("rejects hands of the wrong outer length", function()
            local hands = default_hands()
            hands[3] = nil
            local result = tricks.new(config, hands, 1)
            assert.is_false(result.ok)
            assert.are.equal("bad_hands_shape", result.error.code)
        end)

        it("rejects hands of the wrong inner length", function()
            local hands = default_hands()
            hands[1][#hands[1]] = nil
            local result = tricks.new(config, hands, 1)
            assert.is_false(result.ok)
            assert.are.equal("bad_hands_shape", result.error.code)
            assert.are.equal(1, result.error.player)
        end)

        it("rejects hands with a non-card entry", function()
            local hands = default_hands()
            hands[2][1] = 42
            local result = tricks.new(config, hands, 1)
            assert.is_false(result.ok)
            assert.are.equal("bad_hands_shape", result.error.code)
        end)

        it("rejects a non-table hands argument", function()
            local result = tricks.new(config, "hands", 1)
            assert.is_false(result.ok)
            assert.are.equal("bad_hands_shape", result.error.code)
        end)

        it("rejects a leader outside the 1..3 range", function()
            for _, bad in ipairs({ 0, 4, 1.5, "1", true, {} }) do
                local result = tricks.new(config, default_hands(), bad)
                assert.is_false(result.ok)
                assert.are.equal("bad_leader", result.error.code)
            end
            local nil_result = tricks.new(config, default_hands(), nil)
            assert.is_false(nil_result.ok)
            assert.are.equal("bad_leader", nil_result.error.code)
        end)

        it("starts with no trump", function()
            local s = fresh_tricks()
            assert.is_nil(s.trump)
        end)

        it("starts in_progress with zero tricks played and zero captures", function()
            local s = fresh_tricks(2)
            assert.are.equal("in_progress", s.status)
            assert.are.equal(0, s.tricks_played)
            assert.are.equal(8, s.tricks_per_deal)
            assert.are.equal(2, s.next_to_play)
            for i = 1, config.players.count do
                assert.are.equal(0, s.captured_points[i])
                assert.are.equal(0, s.tricks_won[i])
            end
            assert.are.equal(0, #s.current_trick.plays)
            assert.are.equal(0, #s.completed_tricks)
            assert.are.equal(0, #s.history)
        end)

        it("tags the state so is_tricks recognises it", function()
            assert.is_true(tricks.is_tricks(fresh_tricks()))
        end)

        it("stamps the schema version", function()
            assert.are.equal(tricks.SCHEMA_VERSION, fresh_tricks().schema_version)
        end)

        it("retains the config for later reads", function()
            assert.are.equal(config, fresh_tricks().config)
        end)
    end)

    describe("is_tricks()", function()
        it("rejects non-tables", function()
            assert.is_false(tricks.is_tricks(nil))
            assert.is_false(tricks.is_tricks(42))
            assert.is_false(tricks.is_tricks("tricks"))
            assert.is_false(tricks.is_tricks(true))
        end)

        it("rejects plain tables without the type tag", function()
            assert.is_false(tricks.is_tricks({}))
            assert.is_false(tricks.is_tricks({ status = "in_progress" }))
        end)

        it("accepts a state produced by new()", function()
            assert.is_true(tricks.is_tricks(fresh_tricks()))
        end)
    end)

    describe("set_trump()", function()
        it("rejects when the input is not a tricks state", function()
            local result = tricks.set_trump({}, "hearts")
            assert.is_false(result.ok)
            assert.are.equal("not_a_tricks", result.error.code)
        end)

        it("accepts each of the four standard suits", function()
            for _, suit in ipairs({ "hearts", "diamonds", "clubs", "spades" }) do
                local s = set_trump_ok(fresh_tricks(), suit)
                assert.are.equal(suit, s.trump)
            end
        end)

        it("accepts nil to clear the trump", function()
            local s = set_trump_ok(fresh_tricks(), "hearts")
            local cleared = set_trump_ok(s, nil)
            assert.is_nil(cleared.trump)
        end)

        it("rejects an unknown suit", function()
            for _, bad in ipairs({ "trump", "h", "Hearts", "" }) do
                local result = tricks.set_trump(fresh_tricks(), bad)
                assert.is_false(result.ok)
                assert.are.equal("bad_suit", result.error.code)
            end
        end)

        it("rejects a non-string non-nil suit", function()
            for _, bad in ipairs({ 42, true, {} }) do
                local result = tricks.set_trump(fresh_tricks(), bad)
                assert.is_false(result.ok)
                assert.are.equal("bad_suit", result.error.code)
            end
        end)

        it("rejects setting trump while a trick is in progress", function()
            local s = fresh_tricks(1)
            s = play_ok(s, 1, c("hearts", "9"))
            local result = tricks.set_trump(s, "hearts")
            assert.is_false(result.ok)
            assert.are.equal("trick_in_progress", result.error.code)
        end)

        it("appends a set_trump entry to history", function()
            local s = set_trump_ok(fresh_tricks(), "diamonds")
            assert.are.equal(1, #s.history)
            assert.are.equal("set_trump", s.history[1].action)
            assert.are.equal("diamonds", s.history[1].suit)
        end)

        it("returns a fresh state without mutating the input", function()
            local before = fresh_tricks()
            local after = set_trump_ok(before, "spades")
            assert.are_not.equal(before, after)
            assert.is_nil(before.trump)
            assert.are.equal("spades", after.trump)
        end)
    end)

    describe("set_trump_in_trick() — Phase 3.6 immediate variant", function()
        it("accepts a trump change while a trick is in progress", function()
            local s = fresh_tricks(1)
            s = play_ok(s, 1, c("hearts", "9"))
            local result = tricks.set_trump_in_trick(s, "hearts")
            assert.is_true(result.ok)
            assert.are.equal("hearts", result.tricks.trump)
        end)

        it("re-ranks the trick under the new trump", function()
            -- Player 1 leads hearts 9, the table was no-trump so the trick
            -- would resolve by rank order. After the leader declares
            -- hearts as trump mid-trick, hearts becomes the trump suit
            -- and the led 9 of hearts now beats every non-hearts card.
            local s = fresh_tricks(1)
            s = play_ok(s, 1, c("hearts", "9"))
            s = tricks.set_trump_in_trick(s, "hearts").tricks
            -- Player 2 holds K/10 of hearts; pick the K to keep cleanly
            -- following suit.
            s = play_ok(s, 2, c("hearts", "K"))
            -- Player 3 must follow if possible — they hold hearts cards
            -- (Q/J or A). Use legal_cards to pick a legal one.
            local legal = tricks.legal_cards(s, 3).cards
            s = play_ok(s, 3, legal[1])
            -- The trick is now resolved under hearts trump; the winner
            -- is the highest hearts card. Confirm trump was honoured.
            assert.are.equal("hearts", s.trump)
        end)

        it("appends a set_trump_in_trick entry to history", function()
            local s = fresh_tricks(1)
            s = play_ok(s, 1, c("hearts", "9"))
            local result = tricks.set_trump_in_trick(s, "hearts")
            assert.is_true(result.ok)
            local history = result.tricks.history
            local last = history[#history]
            assert.are.equal("set_trump_in_trick", last.action)
            assert.are.equal("hearts", last.suit)
        end)

        it("rejects when the input is not a tricks state", function()
            local result = tricks.set_trump_in_trick({}, "hearts")
            assert.is_false(result.ok)
            assert.are.equal("not_a_tricks", result.error.code)
        end)

        it("rejects an unknown suit", function()
            local s = fresh_tricks(1)
            s = play_ok(s, 1, c("hearts", "9"))
            local result = tricks.set_trump_in_trick(s, "bogus")
            assert.is_false(result.ok)
            assert.are.equal("bad_suit", result.error.code)
        end)
    end)

    describe("legal_cards() — lead", function()
        it("returns every card in the leader's hand on the lead", function()
            local s = fresh_tricks(1)
            local result = tricks.legal_cards(s, 1)
            assert.is_true(result.ok)
            assert.are.equal(8, #result.cards)
        end)

        it("rejects an invalid player", function()
            local s = fresh_tricks(1)
            local result = tricks.legal_cards(s, 0)
            assert.is_false(result.ok)
            assert.are.equal("bad_player", result.error.code)
        end)
    end)

    describe("legal_cards() — must_follow", function()
        it("restricts to led-suit cards when the player holds the led suit", function()
            local s = fresh_tricks(1)
            -- Player 1 leads ♥9; must_follow forces player 2 to play hearts.
            s = play_ok(s, 1, c("hearts", "9"))
            local result = tricks.legal_cards(s, 2)
            assert.is_true(result.ok)
            for _, lc in ipairs(result.cards) do
                assert.are.equal("hearts", lc.suit)
            end
            assert.are.equal(2, #result.cards) -- player 2 holds ♥K and ♥10
        end)

        it("returns the entire hand when the player is void in the led suit", function()
            -- Build hands where player 2 has zero hearts.
            local hands = {
                {
                    c("hearts", "9"),
                    c("hearts", "10"),
                    c("hearts", "Q"),
                    c("hearts", "K"),
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                    c("clubs", "9"),
                    c("clubs", "J"),
                },
                {
                    c("diamonds", "Q"),
                    c("diamonds", "K"),
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                    c("clubs", "Q"),
                    c("clubs", "K"),
                    c("spades", "9"),
                    c("spades", "J"),
                },
                {
                    c("hearts", "A"),
                    c("hearts", "J"),
                    c("clubs", "10"),
                    c("clubs", "A"),
                    c("spades", "Q"),
                    c("spades", "K"),
                    c("spades", "10"),
                    c("spades", "A"),
                },
            }
            local s = tricks.new(config, hands, 1).tricks
            s = play_ok(s, 1, c("hearts", "9"))
            -- Player 2 is void in hearts; with no trump, may discard freely.
            local result = tricks.legal_cards(s, 2)
            assert.is_true(result.ok)
            assert.are.equal(8, #result.cards)
        end)
    end)

    describe("legal_cards() — must_beat", function()
        it("restricts to higher led-suit cards when the player can beat", function()
            local s = fresh_tricks(1)
            -- Player 1 leads ♥9 (rank 1). Player 2 has ♥K (rank 4) and ♥10 (rank 5).
            -- Both beat ♥9, so both are legal.
            s = play_ok(s, 1, c("hearts", "9"))
            local result = tricks.legal_cards(s, 2)
            assert.is_true(result.ok)
            assert.are.equal(2, #result.cards)
            for _, lc in ipairs(result.cards) do
                assert.are.equal("hearts", lc.suit)
            end
        end)

        it("filters out cards that don't beat the current high", function()
            local hands = {
                {
                    c("hearts", "10"),
                    c("hearts", "9"),
                    c("hearts", "J"),
                    c("clubs", "9"),
                    c("clubs", "J"),
                    c("clubs", "Q"),
                    c("spades", "9"),
                    c("spades", "J"),
                },
                {
                    c("hearts", "K"),
                    c("hearts", "Q"),
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                    c("diamonds", "Q"),
                    c("diamonds", "K"),
                    c("clubs", "K"),
                    c("clubs", "10"),
                },
                {
                    c("hearts", "A"),
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                    c("clubs", "A"),
                    c("spades", "Q"),
                    c("spades", "K"),
                    c("spades", "10"),
                    c("spades", "A"),
                },
            }
            local s = tricks.new(config, hands, 1).tricks
            -- Player 1 leads ♥10 (rank 5). Player 2 has ♥K (4) and ♥Q (3).
            -- Neither beats ♥10, so both are legal (fall back to in_suit).
            s = play_ok(s, 1, c("hearts", "10"))
            local result = tricks.legal_cards(s, 2)
            assert.is_true(result.ok)
            assert.are.equal(2, #result.cards)
        end)

        it("does not require beating when a trump is on the trick", function()
            -- Hands: p1 has only ♥10 in hearts; p2 is void in hearts and
            -- holds 5 diamonds (trump); p3 holds 5 hearts including ♥A and
            -- four hearts that do NOT beat ♥10 (♥9, ♥J, ♥Q, ♥K). With no
            -- trump on the trick, must_beat would restrict p3 to ♥A. With
            -- a trump already on the trick, must_beat is bypassed and all
            -- five hearts are legal.
            local hands = {
                {
                    c("hearts", "10"),
                    c("clubs", "9"),
                    c("clubs", "J"),
                    c("clubs", "Q"),
                    c("clubs", "K"),
                    c("spades", "9"),
                    c("spades", "J"),
                    c("spades", "Q"),
                },
                {
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                    c("diamonds", "Q"),
                    c("diamonds", "K"),
                    c("diamonds", "10"),
                    c("clubs", "10"),
                    c("clubs", "A"),
                    c("spades", "K"),
                },
                {
                    c("hearts", "9"),
                    c("hearts", "J"),
                    c("hearts", "Q"),
                    c("hearts", "K"),
                    c("hearts", "A"),
                    c("diamonds", "A"),
                    c("spades", "10"),
                    c("spades", "A"),
                },
            }
            local s = tricks.new(config, hands, 1).tricks
            s = set_trump_ok(s, "diamonds")
            s = play_ok(s, 1, c("hearts", "10"))
            s = play_ok(s, 2, c("diamonds", "K")) -- trump on trick
            local p3_legal = tricks.legal_cards(s, 3).cards
            assert.are.equal(5, #p3_legal)
            for _, lc in ipairs(p3_legal) do
                assert.are.equal("hearts", lc.suit)
            end
        end)
    end)

    describe("legal_cards() — must_trump and must_overtrump", function()
        local function void_in_hearts_setup()
            local hands = {
                {
                    c("hearts", "9"),
                    c("hearts", "10"),
                    c("hearts", "J"),
                    c("hearts", "K"),
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                    c("clubs", "9"),
                    c("clubs", "J"),
                },
                {
                    c("diamonds", "Q"),
                    c("diamonds", "K"),
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                    c("clubs", "Q"),
                    c("clubs", "K"),
                    c("spades", "9"),
                    c("spades", "J"),
                },
                {
                    c("hearts", "A"),
                    c("hearts", "Q"),
                    c("clubs", "10"),
                    c("clubs", "A"),
                    c("spades", "Q"),
                    c("spades", "K"),
                    c("spades", "10"),
                    c("spades", "A"),
                },
            }
            return tricks.new(config, hands, 1).tricks
        end

        it("forces void-in-led-suit player to play trump when held", function()
            local s = void_in_hearts_setup()
            s = set_trump_ok(s, "diamonds")
            s = play_ok(s, 1, c("hearts", "9"))
            -- Player 2 is void in hearts; trump = diamonds; player 2 holds
            -- ♦Q, ♦K, ♦10, ♦A. Must play one of them.
            local result = tricks.legal_cards(s, 2).cards
            assert.are.equal(4, #result)
            for _, lc in ipairs(result) do
                assert.are.equal("diamonds", lc.suit)
            end
        end)

        it("does not force trump when no trump exists yet", function()
            local s = void_in_hearts_setup()
            -- No set_trump call: no marriage has been declared.
            s = play_ok(s, 1, c("hearts", "9"))
            -- Player 2 may discard freely — there is no trump.
            local result = tricks.legal_cards(s, 2).cards
            assert.are.equal(8, #result)
        end)

        it("does not force trump when the player holds none", function()
            local hands = {
                {
                    c("hearts", "9"),
                    c("hearts", "10"),
                    c("hearts", "J"),
                    c("hearts", "K"),
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                    c("clubs", "9"),
                    c("clubs", "J"),
                },
                {
                    c("clubs", "Q"),
                    c("clubs", "K"),
                    c("clubs", "10"),
                    c("clubs", "A"),
                    c("spades", "9"),
                    c("spades", "J"),
                    c("spades", "Q"),
                    c("spades", "K"),
                },
                {
                    c("hearts", "A"),
                    c("hearts", "Q"),
                    c("diamonds", "Q"),
                    c("diamonds", "K"),
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                    c("spades", "10"),
                    c("spades", "A"),
                },
            }
            local s = tricks.new(config, hands, 1).tricks
            s = set_trump_ok(s, "diamonds")
            s = play_ok(s, 1, c("hearts", "9"))
            -- Player 2 has no hearts and no diamonds: discard freely.
            local result = tricks.legal_cards(s, 2).cards
            assert.are.equal(8, #result)
        end)

        it("requires overtrumping when a higher trump is held", function()
            -- p1 holds all 6 hearts so p2 and p3 are void in hearts.
            -- p2 trumps with ♦9 (rank 1, lowest trump). p3 has only trumps
            -- that overtrump ♦9 (♦K=4, ♦10=5, ♦A=6); all are legal.
            local hands = {
                {
                    c("hearts", "9"),
                    c("hearts", "J"),
                    c("hearts", "Q"),
                    c("hearts", "K"),
                    c("hearts", "10"),
                    c("hearts", "A"),
                    c("clubs", "9"),
                    c("clubs", "J"),
                },
                {
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                    c("diamonds", "Q"),
                    c("clubs", "Q"),
                    c("clubs", "K"),
                    c("clubs", "10"),
                    c("spades", "9"),
                    c("spades", "J"),
                },
                {
                    c("diamonds", "K"),
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                    c("clubs", "A"),
                    c("spades", "Q"),
                    c("spades", "K"),
                    c("spades", "10"),
                    c("spades", "A"),
                },
            }
            local s = tricks.new(config, hands, 1).tricks
            s = set_trump_ok(s, "diamonds")
            s = play_ok(s, 1, c("hearts", "9"))
            s = play_ok(s, 2, c("diamonds", "9"))
            local p3 = tricks.legal_cards(s, 3).cards
            assert.are.equal(3, #p3)
            for _, lc in ipairs(p3) do
                assert.are.equal("diamonds", lc.suit)
                assert.is_true(
                    card.trick_rank(lc, config) > card.trick_rank(c("diamonds", "9"), config)
                )
            end
        end)

        it("falls back to any trump when the player cannot overtrump", function()
            -- p1 holds all 6 hearts so p2 and p3 are void in hearts. p2
            -- trumps with ♦A (rank 6, highest); p3 holds only trumps below
            -- ♦A (♦9, ♦J, ♦Q). None can overtrump, so all three are legal.
            local hands = {
                {
                    c("hearts", "9"),
                    c("hearts", "J"),
                    c("hearts", "Q"),
                    c("hearts", "K"),
                    c("hearts", "10"),
                    c("hearts", "A"),
                    c("clubs", "9"),
                    c("clubs", "J"),
                },
                {
                    c("diamonds", "K"),
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                    c("clubs", "Q"),
                    c("clubs", "K"),
                    c("clubs", "10"),
                    c("spades", "9"),
                    c("spades", "J"),
                },
                {
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                    c("diamonds", "Q"),
                    c("clubs", "A"),
                    c("spades", "Q"),
                    c("spades", "K"),
                    c("spades", "10"),
                    c("spades", "A"),
                },
            }
            local s = tricks.new(config, hands, 1).tricks
            s = set_trump_ok(s, "diamonds")
            s = play_ok(s, 1, c("hearts", "9"))
            s = play_ok(s, 2, c("diamonds", "A"))
            local p3 = tricks.legal_cards(s, 3).cards
            assert.are.equal(3, #p3)
            for _, lc in ipairs(p3) do
                assert.are.equal("diamonds", lc.suit)
            end
        end)
    end)

    describe("play() validation", function()
        it("rejects a state that is not a tricks state", function()
            local result = tricks.play({}, 1, c("hearts", "9"))
            assert.is_false(result.ok)
            assert.are.equal("not_a_tricks", result.error.code)
        end)

        it("rejects an invalid player", function()
            local s = fresh_tricks()
            local result = tricks.play(s, 0, c("hearts", "9"))
            assert.is_false(result.ok)
            assert.are.equal("bad_player", result.error.code)
        end)

        it("rejects when it is not the player's turn", function()
            local s = fresh_tricks(1)
            local result = tricks.play(s, 2, c("hearts", "K"))
            assert.is_false(result.ok)
            assert.are.equal("not_your_turn", result.error.code)
        end)

        it("rejects a card that is not in the player's hand", function()
            local s = fresh_tricks(1)
            local result = tricks.play(s, 1, c("hearts", "A"))
            assert.is_false(result.ok)
            assert.are.equal("card_not_in_hand", result.error.code)
        end)

        it("rejects a non-card argument", function()
            local s = fresh_tricks(1)
            local result = tricks.play(s, 1, 42)
            assert.is_false(result.ok)
            assert.are.equal("card_not_in_hand", result.error.code)
        end)

        it("rejects must_follow violations and names the rule", function()
            local s = fresh_tricks(1)
            s = play_ok(s, 1, c("hearts", "9"))
            -- Player 2 holds hearts; playing ♦Q is a must_follow violation.
            local result = tricks.play(s, 2, c("diamonds", "Q"))
            assert.is_false(result.ok)
            assert.are.equal("must_follow_violation", result.error.code)
            assert.are.equal("must_follow", result.error.rule)
        end)

        it("rejects must_beat violations and names the rule", function()
            -- Lead ♥K (rank 4). Player 2 holds ♥9 (1), ♥J (2), ♥A (6).
            -- ♥A beats; ♥9 and ♥J do not. Playing ♥9 violates must_beat.
            local hands = {
                {
                    c("hearts", "10"),
                    c("hearts", "K"),
                    c("clubs", "9"),
                    c("clubs", "J"),
                    c("clubs", "Q"),
                    c("spades", "9"),
                    c("spades", "J"),
                    c("spades", "Q"),
                },
                {
                    c("hearts", "9"),
                    c("hearts", "J"),
                    c("hearts", "A"),
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                    c("diamonds", "Q"),
                    c("diamonds", "K"),
                    c("clubs", "K"),
                },
                {
                    c("hearts", "Q"),
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                    c("clubs", "10"),
                    c("clubs", "A"),
                    c("spades", "K"),
                    c("spades", "10"),
                    c("spades", "A"),
                },
            }
            local s = tricks.new(config, hands, 1).tricks
            s = play_ok(s, 1, c("hearts", "K"))
            local result = tricks.play(s, 2, c("hearts", "9"))
            assert.is_false(result.ok)
            assert.are.equal("must_beat_violation", result.error.code)
            assert.are.equal("must_beat", result.error.rule)
        end)

        it("rejects must_trump violations and names the rule", function()
            local hands = {
                {
                    c("hearts", "9"),
                    c("hearts", "10"),
                    c("hearts", "J"),
                    c("hearts", "K"),
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                    c("clubs", "9"),
                    c("clubs", "J"),
                },
                {
                    c("diamonds", "Q"),
                    c("diamonds", "K"),
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                    c("clubs", "Q"),
                    c("clubs", "K"),
                    c("spades", "9"),
                    c("spades", "J"),
                },
                {
                    c("hearts", "A"),
                    c("hearts", "Q"),
                    c("clubs", "10"),
                    c("clubs", "A"),
                    c("spades", "Q"),
                    c("spades", "K"),
                    c("spades", "10"),
                    c("spades", "A"),
                },
            }
            local s = tricks.new(config, hands, 1).tricks
            s = set_trump_ok(s, "diamonds")
            s = play_ok(s, 1, c("hearts", "9"))
            -- Player 2 is void in hearts and holds diamonds (trump). Playing
            -- a club is a must_trump violation.
            local result = tricks.play(s, 2, c("clubs", "Q"))
            assert.is_false(result.ok)
            assert.are.equal("must_trump_violation", result.error.code)
            assert.are.equal("must_trump", result.error.rule)
        end)

        it("rejects must_overtrump violations and names the rule", function()
            -- p1 holds all 6 hearts so p2 and p3 are void in hearts. p2
            -- trumps with ♦Q (rank 3). p3 holds ♦J (2) and ♦A (6) plus a
            -- non-trump filler. ♦A overtrumps ♦Q; ♦J does not. Playing ♦J
            -- violates must_overtrump.
            local hands = {
                {
                    c("hearts", "9"),
                    c("hearts", "J"),
                    c("hearts", "Q"),
                    c("hearts", "K"),
                    c("hearts", "10"),
                    c("hearts", "A"),
                    c("clubs", "9"),
                    c("clubs", "J"),
                },
                {
                    c("diamonds", "9"),
                    c("diamonds", "Q"),
                    c("diamonds", "K"),
                    c("clubs", "Q"),
                    c("clubs", "K"),
                    c("clubs", "10"),
                    c("spades", "9"),
                    c("spades", "J"),
                },
                {
                    c("diamonds", "J"),
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                    c("clubs", "A"),
                    c("spades", "Q"),
                    c("spades", "K"),
                    c("spades", "10"),
                    c("spades", "A"),
                },
            }
            local s = tricks.new(config, hands, 1).tricks
            s = set_trump_ok(s, "diamonds")
            s = play_ok(s, 1, c("hearts", "9"))
            s = play_ok(s, 2, c("diamonds", "Q"))
            local result = tricks.play(s, 3, c("diamonds", "J"))
            assert.is_false(result.ok)
            assert.are.equal("must_overtrump_violation", result.error.code)
            assert.are.equal("must_overtrump", result.error.rule)
        end)

        it("rejects play after the deal is done", function()
            -- Drive a full deal end-to-end with default hands and no trump,
            -- then attempt a 25th play.
            local s = fresh_tricks(1)
            -- Walk through 8 tricks. Each trick's leader plays a card, the
            -- next two play legal cards in clockwise order. We use legal
            -- _cards[1] each turn as a simple legal choice.
            while s.status == "in_progress" do
                local p = s.next_to_play
                local card_to_play = tricks.legal_cards(s, p).cards[1]
                s = play_ok(s, p, card_to_play)
            end
            assert.are.equal("done", s.status)
            local result = tricks.play(s, 1, c("hearts", "9"))
            assert.is_false(result.ok)
            assert.are.equal("wrong_phase", result.error.code)
        end)
    end)

    describe("play() — turn order and trick resolution", function()
        it("advances the turn clockwise after a non-final play", function()
            local s = fresh_tricks(1)
            s = play_ok(s, 1, c("hearts", "9"))
            assert.are.equal(2, s.next_to_play)
            -- Player 2 must follow hearts: pick a hearts card.
            s = play_ok(s, 2, c("hearts", "K"))
            assert.are.equal(3, s.next_to_play)
        end)

        it("resolves the trick after the third play and credits the winner", function()
            local s = fresh_tricks(1)
            s = play_ok(s, 1, c("hearts", "9")) -- rank 1
            s = play_ok(s, 2, c("hearts", "K")) -- rank 4
            s = play_ok(s, 3, c("hearts", "A")) -- rank 6
            -- ♥A wins. Captured points: 0 + 4 + 11 = 15.
            assert.are.equal(1, s.tricks_played)
            assert.are.equal(0, #s.current_trick.plays)
            assert.are.equal(3, s.next_to_play)
            assert.are.equal(15, s.captured_points[3])
            assert.are.equal(0, s.captured_points[1])
            assert.are.equal(0, s.captured_points[2])
            assert.are.equal(1, s.tricks_won[3])
            assert.are.equal(1, #s.completed_tricks)
            local first = s.completed_tricks[1]
            assert.are.equal(1, first.leader)
            assert.are.equal(3, first.winner)
            assert.are.equal(15, first.captured_points)
            assert.are.equal("hearts", first.led_suit)
            assert.is_nil(first.trump)
        end)

        it("highest trump beats any led-suit card", function()
            local hands = {
                {
                    c("hearts", "A"),
                    c("hearts", "10"),
                    c("hearts", "K"),
                    c("clubs", "9"),
                    c("clubs", "J"),
                    c("clubs", "Q"),
                    c("spades", "9"),
                    c("spades", "J"),
                },
                {
                    c("hearts", "Q"),
                    c("hearts", "J"),
                    c("hearts", "9"),
                    c("clubs", "K"),
                    c("clubs", "10"),
                    c("clubs", "A"),
                    c("spades", "Q"),
                    c("spades", "K"),
                },
                {
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                    c("diamonds", "Q"),
                    c("diamonds", "K"),
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                    c("spades", "10"),
                    c("spades", "A"),
                },
            }
            local s = tricks.new(config, hands, 1).tricks
            s = set_trump_ok(s, "diamonds")
            s = play_ok(s, 1, c("hearts", "A")) -- led, rank 6
            s = play_ok(s, 2, c("hearts", "Q")) -- follow, rank 3
            s = play_ok(s, 3, c("diamonds", "9")) -- trump, rank 1
            -- Trump beats ♥A. Player 3 wins.
            assert.are.equal(3, s.completed_tricks[1].winner)
            assert.are.equal(3, s.next_to_play)
        end)

        it("among trumps, the highest trick rank wins", function()
            -- p1 holds all 6 hearts so p2 and p3 are void in hearts. p2
            -- trumps with ♦K (rank 4); p3 must overtrump and only ♦A
            -- (rank 6) qualifies. ♦A wins the trick for p3.
            local hands = {
                {
                    c("hearts", "9"),
                    c("hearts", "J"),
                    c("hearts", "Q"),
                    c("hearts", "K"),
                    c("hearts", "10"),
                    c("hearts", "A"),
                    c("clubs", "9"),
                    c("clubs", "J"),
                },
                {
                    c("diamonds", "9"),
                    c("diamonds", "Q"),
                    c("diamonds", "K"),
                    c("clubs", "Q"),
                    c("clubs", "K"),
                    c("clubs", "10"),
                    c("spades", "9"),
                    c("spades", "J"),
                },
                {
                    c("diamonds", "J"),
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                    c("clubs", "A"),
                    c("spades", "Q"),
                    c("spades", "K"),
                    c("spades", "10"),
                    c("spades", "A"),
                },
            }
            local s = tricks.new(config, hands, 1).tricks
            s = set_trump_ok(s, "diamonds")
            s = play_ok(s, 1, c("hearts", "9"))
            s = play_ok(s, 2, c("diamonds", "K"))
            s = play_ok(s, 3, c("diamonds", "A"))
            assert.are.equal(3, s.completed_tricks[1].winner)
        end)

        it("trick winner becomes next leader", function()
            local s = fresh_tricks(1)
            s = play_ok(s, 1, c("hearts", "9"))
            s = play_ok(s, 2, c("hearts", "K"))
            s = play_ok(s, 3, c("hearts", "A"))
            assert.are.equal(3, s.next_to_play)
        end)

        it("reflects updated hand sizes through the deal", function()
            local s = fresh_tricks(1)
            assert.are.equal(8, #s.hands[1])
            assert.are.equal(8, #s.hands[2])
            assert.are.equal(8, #s.hands[3])
            s = play_ok(s, 1, c("hearts", "9"))
            assert.are.equal(7, #s.hands[1])
            s = play_ok(s, 2, c("hearts", "K"))
            assert.are.equal(7, #s.hands[2])
            s = play_ok(s, 3, c("hearts", "A"))
            assert.are.equal(7, #s.hands[3])
        end)
    end)

    describe("play() — discard cannot win", function()
        it("a non-trump non-led-suit card cannot win the trick", function()
            -- p1 leads ♥A (rank 6, highest). p2 holds only hearts that
            -- cannot beat ♥A and follows with ♥9 (any heart is legal). p3
            -- is void in hearts and there is no trump, so p3 discards ♦A
            -- — a worth-11 discard that cannot take the trick. p1 wins.
            local hands = {
                {
                    c("hearts", "A"),
                    c("hearts", "10"),
                    c("hearts", "K"),
                    c("clubs", "9"),
                    c("clubs", "J"),
                    c("clubs", "Q"),
                    c("spades", "9"),
                    c("spades", "J"),
                },
                {
                    c("hearts", "9"),
                    c("hearts", "Q"),
                    c("hearts", "J"),
                    c("clubs", "K"),
                    c("clubs", "10"),
                    c("clubs", "A"),
                    c("spades", "Q"),
                    c("spades", "K"),
                },
                {
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                    c("diamonds", "Q"),
                    c("diamonds", "K"),
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                    c("spades", "10"),
                    c("spades", "A"),
                },
            }
            local s = tricks.new(config, hands, 1).tricks
            s = play_ok(s, 1, c("hearts", "A"))
            s = play_ok(s, 2, c("hearts", "9"))
            s = play_ok(s, 3, c("diamonds", "A"))
            assert.are.equal(1, s.completed_tricks[1].winner)
            assert.are.equal(22, s.captured_points[1])
        end)
    end)

    describe("end of deal", function()
        it("transitions to status 'done' after exactly 8 tricks", function()
            local s = fresh_tricks(1)
            local trick_count = 0
            while s.status == "in_progress" do
                local p = s.next_to_play
                local choice = tricks.legal_cards(s, p).cards[1]
                s = play_ok(s, p, choice)
                if #s.current_trick.plays == 0 then
                    trick_count = trick_count + 1
                end
            end
            assert.are.equal(8, trick_count)
            assert.are.equal(8, s.tricks_played)
            assert.are.equal("done", s.status)
            assert.is_nil(s.next_to_play)
        end)

        it("empties every hand by the time the deal is done", function()
            local s = fresh_tricks(1)
            while s.status == "in_progress" do
                local p = s.next_to_play
                local choice = tricks.legal_cards(s, p).cards[1]
                s = play_ok(s, p, choice)
            end
            for i = 1, config.players.count do
                assert.are.equal(0, #s.hands[i])
            end
        end)

        it("captured points across all sides sum to the deck total", function()
            local s = fresh_tricks(1)
            while s.status == "in_progress" do
                local p = s.next_to_play
                local choice = tricks.legal_cards(s, p).cards[1]
                s = play_ok(s, p, choice)
            end
            local total = 0
            for i = 1, config.players.count do
                total = total + s.captured_points[i]
            end
            assert.are.equal(120, total)
        end)

        it("tricks_won across all sides sums to 8", function()
            local s = fresh_tricks(1)
            while s.status == "in_progress" do
                local p = s.next_to_play
                local choice = tricks.legal_cards(s, p).cards[1]
                s = play_ok(s, p, choice)
            end
            local total = 0
            for i = 1, config.players.count do
                total = total + s.tricks_won[i]
            end
            assert.are.equal(8, total)
        end)
    end)

    describe("immutability", function()
        it("does not mutate the input on play()", function()
            local before = fresh_tricks(1)
            local hand1_before = before.hands[1]
            local hand1_card = find_in_hand(hand1_before, "hearts", "9")
            assert.is_not_nil(hand1_card)
            local after = play_ok(before, 1, c("hearts", "9"))
            assert.are_not.equal(before, after)
            assert.are.equal(8, #before.hands[1])
            assert.are.equal(7, #after.hands[1])
            assert.are.equal(0, #before.current_trick.plays)
            assert.are.equal(1, #after.current_trick.plays)
            assert.are.equal(1, before.next_to_play)
            assert.are.equal(2, after.next_to_play)
        end)

        it("does not mutate the input on set_trump()", function()
            local before = fresh_tricks()
            local after = set_trump_ok(before, "hearts")
            assert.are_not.equal(before, after)
            assert.is_nil(before.trump)
            assert.are.equal("hearts", after.trump)
        end)
    end)

    describe("history", function()
        it("appends a play entry on every successful play", function()
            local s = fresh_tricks(1)
            s = play_ok(s, 1, c("hearts", "9"))
            assert.are.equal(1, #s.history)
            assert.are.equal("play", s.history[1].action)
            assert.are.equal(1, s.history[1].player)
            assert.are.equal("hearts", s.history[1].card.suit)
            assert.are.equal("9", s.history[1].card.rank)
        end)

        it("appends a trick_resolved entry when the trick completes", function()
            local s = fresh_tricks(1)
            s = play_ok(s, 1, c("hearts", "9"))
            s = play_ok(s, 2, c("hearts", "K"))
            s = play_ok(s, 3, c("hearts", "A"))
            -- 3 play entries + 1 trick_resolved entry.
            assert.are.equal(4, #s.history)
            local last = s.history[4]
            assert.are.equal("trick_resolved", last.action)
            assert.are.equal(1, last.trick_index)
            assert.are.equal(3, last.winner)
            assert.are.equal(15, last.captured_points)
        end)
    end)

    -- Phase 3.6 trick-play house rules ------------------------------------
    --
    -- Build a config that overrides the canonical Russian baseline only
    -- in the tricks group — every other rule stays at canonical defaults
    -- so the new branches isolate cleanly.
    local function with_tricks(overrides)
        local app_json = require("app.json")
        local parsed = app_json.decode(rule_config.to_json(rule_config.canonical_russian))
        for k, v in pairs(overrides) do
            parsed.tricks[k] = v
        end
        return rule_config.new(parsed)
    end

    local function tricks_with(cfg, hands, leader, opts)
        local result = tricks.new(cfg, hands, leader, opts)
        assert.is_true(
            result.ok,
            "fixture: tricks.new must succeed (got "
                .. (result.error and result.error.code or "?")
                .. ")"
        )
        return result.tricks
    end

    describe("polish_strict overtake", function()
        local function follow_with_three_beating_hearts()
            return {
                {
                    c("hearts", "9"),
                    c("clubs", "9"),
                    c("clubs", "J"),
                    c("clubs", "Q"),
                    c("clubs", "K"),
                    c("clubs", "10"),
                    c("clubs", "A"),
                    c("spades", "9"),
                },
                {
                    c("hearts", "Q"),
                    c("hearts", "10"),
                    c("hearts", "A"),
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                    c("diamonds", "Q"),
                    c("diamonds", "K"),
                    c("spades", "J"),
                },
                {
                    c("hearts", "J"),
                    c("hearts", "K"),
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                    c("spades", "Q"),
                    c("spades", "K"),
                    c("spades", "10"),
                    c("spades", "A"),
                },
            }
        end

        it("narrows legal cards to the single highest beating card", function()
            local cfg = with_tricks({ must_overtake_strictness = "polish_strict" })
            local s = tricks_with(cfg, follow_with_three_beating_hearts(), 1)
            s = play_ok(s, 1, c("hearts", "9"))
            local r = tricks.legal_cards(s, 2)
            assert.is_true(r.ok)
            assert.are.equal(1, #r.cards)
            assert.are.equal("hearts", r.cards[1].suit)
            assert.are.equal("A", r.cards[1].rank)
        end)

        it("standard mode admits every beating card", function()
            local cfg = with_tricks({ must_overtake_strictness = "standard" })
            local s = tricks_with(cfg, follow_with_three_beating_hearts(), 1)
            s = play_ok(s, 1, c("hearts", "9"))
            local r = tricks.legal_cards(s, 2)
            assert.is_true(r.ok)
            assert.are.equal(3, #r.cards)
        end)

        it("rejects a non-highest beating card with polish_strict_overtake_violation", function()
            local cfg = with_tricks({ must_overtake_strictness = "polish_strict" })
            local s = tricks_with(cfg, follow_with_three_beating_hearts(), 1)
            s = play_ok(s, 1, c("hearts", "9"))
            local r = tricks.play(s, 2, c("hearts", "Q"))
            assert.is_false(r.ok)
            assert.are.equal("polish_strict_overtake_violation", r.error.code)
            assert.are.equal("must_overtake_strictness", r.error.rule)
        end)

        it("does not engage when the player cannot beat the threshold", function()
            -- p1 leads hearts.A; p2 must follow with hearts but holds only Q,10
            -- (no card above A). Polish_strict should not narrow anything.
            local hands = {
                {
                    c("hearts", "A"),
                    c("hearts", "K"),
                    c("clubs", "9"),
                    c("clubs", "J"),
                    c("clubs", "Q"),
                    c("clubs", "K"),
                    c("clubs", "10"),
                    c("spades", "9"),
                },
                {
                    c("hearts", "Q"),
                    c("hearts", "10"),
                    c("hearts", "9"),
                    c("clubs", "A"),
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                    c("diamonds", "Q"),
                    c("spades", "J"),
                },
                {
                    c("hearts", "J"),
                    c("diamonds", "K"),
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                    c("spades", "Q"),
                    c("spades", "K"),
                    c("spades", "10"),
                    c("spades", "A"),
                },
            }
            local cfg = with_tricks({ must_overtake_strictness = "polish_strict" })
            local s = tricks_with(cfg, hands, 1)
            s = play_ok(s, 1, c("hearts", "A"))
            local r = tricks.legal_cards(s, 2)
            assert.is_true(r.ok)
            assert.are.equal(3, #r.cards)
        end)
    end)

    describe("polish_strict trump", function()
        local function void_in_led_with_two_high_trumps()
            return {
                {
                    c("hearts", "Q"),
                    c("hearts", "10"),
                    c("hearts", "A"),
                    c("clubs", "9"),
                    c("clubs", "J"),
                    c("clubs", "K"),
                    c("clubs", "10"),
                    c("clubs", "A"),
                },
                {
                    c("spades", "9"),
                    c("spades", "J"),
                    c("spades", "Q"),
                    c("spades", "K"),
                    c("spades", "A"),
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                    c("diamonds", "Q"),
                },
                {
                    c("hearts", "9"),
                    c("hearts", "J"),
                    c("hearts", "K"),
                    c("clubs", "Q"),
                    c("diamonds", "K"),
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                    c("spades", "10"),
                },
            }
        end

        it("narrows to the single highest trump when must_trump fires", function()
            local cfg = with_tricks({ must_trump_strictness = "polish_strict" })
            local s = tricks_with(cfg, void_in_led_with_two_high_trumps(), 1)
            s = set_trump_ok(s, "spades")
            s = play_ok(s, 1, c("hearts", "Q"))
            -- p2 is void in hearts, holds spades 9/J/Q/K/A. Polish_strict
            -- says only spades.A is legal (the highest).
            local r = tricks.legal_cards(s, 2)
            assert.is_true(r.ok)
            assert.are.equal(1, #r.cards)
            assert.are.equal("spades", r.cards[1].suit)
            assert.are.equal("A", r.cards[1].rank)
        end)

        it("standard mode allows any trump when must_trump fires", function()
            local cfg = with_tricks({ must_trump_strictness = "standard" })
            local s = tricks_with(cfg, void_in_led_with_two_high_trumps(), 1)
            s = set_trump_ok(s, "spades")
            s = play_ok(s, 1, c("hearts", "Q"))
            local r = tricks.legal_cards(s, 2)
            assert.is_true(r.ok)
            -- Standard with must_overtrump=true and no trump on trick yet:
            -- threshold = 0 → all spades legal.
            assert.are.equal(5, #r.cards)
        end)
    end)

    describe("defender_must_overtrump_declarer", function()
        local function void_in_clubs_setup()
            -- p1 (declarer) and p2 (defender) both void in clubs. p3
            -- holds all six clubs and leads one. p1 has spades.Q
            -- (trump). p2 has spades.K and spades.A (both higher than
            -- Q). Other cards distributed so each hand has 8 cards.
            return {
                {
                    c("hearts", "9"),
                    c("hearts", "J"),
                    c("hearts", "Q"),
                    c("hearts", "K"),
                    c("spades", "9"),
                    c("spades", "Q"),
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                },
                {
                    c("hearts", "10"),
                    c("hearts", "A"),
                    c("spades", "K"),
                    c("spades", "A"),
                    c("diamonds", "Q"),
                    c("diamonds", "K"),
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                },
                {
                    c("clubs", "9"),
                    c("clubs", "J"),
                    c("clubs", "Q"),
                    c("clubs", "K"),
                    c("clubs", "10"),
                    c("clubs", "A"),
                    c("spades", "J"),
                    c("spades", "10"),
                },
            }
        end

        it("forces a defender to overtrump declarer's trump even with must_trump=off", function()
            local cfg = with_tricks({
                must_trump = false,
                must_overtrump = false,
                defender_must_overtrump_declarer = "on",
            })
            local s = tricks_with(cfg, void_in_clubs_setup(), 3, { declarer = 1 })
            s = set_trump_ok(s, "spades")
            s = play_ok(s, 3, c("clubs", "J"))
            s = play_ok(s, 1, c("spades", "Q")) -- declarer trumps with spades.Q
            -- p2 is void in clubs, has spades.K and spades.A (both > Q).
            -- defender_must_overtrump_declarer="on" + must_trump=off:
            -- p2 must overtrump (play spades.K or spades.A).
            local r = tricks.legal_cards(s, 2)
            assert.is_true(r.ok)
            assert.are.equal(2, #r.cards)
            local ranks = {}
            for _, card_obj in ipairs(r.cards) do
                assert.are.equal("spades", card_obj.suit)
                ranks[card_obj.rank] = true
            end
            assert.is_true(ranks["K"])
            assert.is_true(ranks["A"])
        end)

        it("rejects a non-overtrumping play with the dedicated violation code", function()
            local cfg = with_tricks({
                must_trump = false,
                must_overtrump = false,
                defender_must_overtrump_declarer = "on",
            })
            local s = tricks_with(cfg, void_in_clubs_setup(), 3, { declarer = 1 })
            s = set_trump_ok(s, "spades")
            s = play_ok(s, 3, c("clubs", "J"))
            s = play_ok(s, 1, c("spades", "Q"))
            local r = tricks.play(s, 2, c("diamonds", "A"))
            assert.is_false(r.ok)
            assert.are.equal("defender_must_overtrump_declarer_violation", r.error.code)
        end)

        it("does not engage for the declarer themselves", function()
            local cfg = with_tricks({
                must_trump = false,
                must_overtrump = false,
                defender_must_overtrump_declarer = "on",
            })
            -- Same fixture but p2 is now the declarer. p1 (defender)
            -- plays spades.Q; p2 (declarer) is void in clubs, holds
            -- spades.K, spades.A — but the defender rule does not bind
            -- the declarer, so p2 may discard freely.
            local s = tricks_with(cfg, void_in_clubs_setup(), 3, { declarer = 2 })
            s = set_trump_ok(s, "spades")
            s = play_ok(s, 3, c("clubs", "J"))
            s = play_ok(s, 1, c("spades", "Q"))
            local r = tricks.legal_cards(s, 2)
            assert.is_true(r.ok)
            -- p2 has 8 cards, all legal (no must_trump, no defender
            -- rule applies to declarer).
            assert.are.equal(8, #r.cards)
        end)
    end)

    describe("partial_trumping", function()
        local function partial_trumping_fixture()
            -- p1 = declarer, void in clubs, holds spades.A (highest trump).
            -- p2 = defender, void in clubs, holds only sub-A trumps + diamonds.
            -- p3 = leader, holds 6 clubs + 2 diamonds.
            return {
                {
                    c("hearts", "9"),
                    c("hearts", "J"),
                    c("hearts", "Q"),
                    c("hearts", "K"),
                    c("hearts", "10"),
                    c("hearts", "A"),
                    c("spades", "A"),
                    c("diamonds", "A"),
                },
                {
                    c("spades", "9"),
                    c("spades", "J"),
                    c("spades", "Q"),
                    c("spades", "K"),
                    c("spades", "10"),
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                    c("diamonds", "Q"),
                },
                {
                    c("clubs", "9"),
                    c("clubs", "J"),
                    c("clubs", "Q"),
                    c("clubs", "K"),
                    c("clubs", "10"),
                    c("clubs", "A"),
                    c("diamonds", "K"),
                    c("diamonds", "10"),
                },
            }
        end

        it("lifts must_trump when defender holds only sub-threshold trumps", function()
            local cfg = with_tricks({ partial_trumping = "on" })
            local s = tricks_with(cfg, partial_trumping_fixture(), 3, { declarer = 1 })
            s = set_trump_ok(s, "spades")
            s = play_ok(s, 3, c("clubs", "K"))
            s = play_ok(s, 1, c("spades", "A")) -- declarer trumps with the top spade
            -- p2 (defender) is void in clubs and holds only spades 9/J/Q/K/10
            -- (all < A). partial_trumping="on" lifts must_trump → may discard.
            local r = tricks.legal_cards(s, 2)
            assert.is_true(r.ok)
            assert.are.equal(8, #r.cards)
        end)

        it("standard mode forces must_trump even with only lower trumps", function()
            local cfg = with_tricks({ partial_trumping = "off" })
            local s = tricks_with(cfg, partial_trumping_fixture(), 3, { declarer = 1 })
            s = set_trump_ok(s, "spades")
            s = play_ok(s, 3, c("clubs", "K"))
            s = play_ok(s, 1, c("spades", "A"))
            -- Standard: defender must play one of their (lower) trumps. With
            -- must_overtrump on but no card can beat A, all spades are legal.
            local r = tricks.legal_cards(s, 2)
            assert.is_true(r.ok)
            assert.are.equal(5, #r.cards)
            for _, card_obj in ipairs(r.cards) do
                assert.are.equal("spades", card_obj.suit)
            end
        end)

        it("does not engage for the declarer themselves", function()
            local cfg = with_tricks({ partial_trumping = "on" })
            -- Swap p1/p2 roles: p2 = declarer this time. Even with
            -- partial_trumping="on", the declarer is not relaxed.
            local s = tricks_with(cfg, partial_trumping_fixture(), 3, { declarer = 2 })
            s = set_trump_ok(s, "spades")
            s = play_ok(s, 3, c("clubs", "K"))
            s = play_ok(s, 1, c("spades", "A")) -- p1 (defender) plays trump A
            -- p2 is the declarer, void in clubs, only sub-A trumps. Standard
            -- must_trump engages because partial_trumping is defender-only.
            local r = tricks.legal_cards(s, 2)
            assert.is_true(r.ok)
            assert.are.equal(5, #r.cards)
        end)
    end)

    describe("lead_trump_after_marriage", function()
        it("restricts the on-lead seat to trump cards when the flag is pending", function()
            local cfg = with_tricks({ lead_trump_after_marriage = "on" })
            local s = tricks_with(cfg, default_hands(), 1)
            s = set_trump_ok(s, "spades")
            -- Mark the flag (session would call this after a marriage).
            local mark = tricks.mark_lead_trump_after_marriage(s)
            assert.is_true(mark.ok)
            s = mark.tricks
            -- p1 hand: hearts 9/J/Q, diamonds 9/J, clubs 9, spades 9/J.
            -- Lead is restricted to spades (the trump suit).
            local r = tricks.legal_cards(s, 1)
            assert.is_true(r.ok)
            assert.are.equal(2, #r.cards)
            for _, card_obj in ipairs(r.cards) do
                assert.are.equal("spades", card_obj.suit)
            end
        end)

        it("drops the constraint when the leader holds no trump", function()
            local cfg = with_tricks({ lead_trump_after_marriage = "on" })
            local hands = {
                {
                    c("hearts", "9"),
                    c("hearts", "J"),
                    c("hearts", "Q"),
                    c("clubs", "9"),
                    c("clubs", "J"),
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                    c("diamonds", "Q"),
                },
                {
                    c("hearts", "K"),
                    c("hearts", "10"),
                    c("hearts", "A"),
                    c("clubs", "Q"),
                    c("diamonds", "K"),
                    c("spades", "9"),
                    c("spades", "J"),
                    c("spades", "Q"),
                },
                {
                    c("clubs", "K"),
                    c("clubs", "10"),
                    c("clubs", "A"),
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                    c("spades", "K"),
                    c("spades", "10"),
                    c("spades", "A"),
                },
            }
            local s = tricks_with(cfg, hands, 1)
            s = set_trump_ok(s, "spades")
            local mark = tricks.mark_lead_trump_after_marriage(s)
            s = mark.tricks
            -- p1 holds no spades; the constraint lifts and the full hand is legal.
            local r = tricks.legal_cards(s, 1)
            assert.is_true(r.ok)
            assert.are.equal(8, #r.cards)
        end)

        it("clears the flag once a card is played to the lead", function()
            local cfg = with_tricks({ lead_trump_after_marriage = "on" })
            local s = tricks_with(cfg, default_hands(), 1)
            s = set_trump_ok(s, "spades")
            s = tricks.mark_lead_trump_after_marriage(s).tricks
            assert.is_true(s.lead_trump_after_marriage_pending)
            s = play_ok(s, 1, c("spades", "9"))
            assert.is_false(s.lead_trump_after_marriage_pending)
        end)

        it("rejects a non-trump lead with lead_trump_after_marriage_violation", function()
            local cfg = with_tricks({ lead_trump_after_marriage = "on" })
            local s = tricks_with(cfg, default_hands(), 1)
            s = set_trump_ok(s, "spades")
            s = tricks.mark_lead_trump_after_marriage(s).tricks
            local r = tricks.play(s, 1, c("hearts", "9"))
            assert.is_false(r.ok)
            assert.are.equal("lead_trump_after_marriage_violation", r.error.code)
        end)
    end)

    describe("lazy_revoke", function()
        it('accepts an otherwise-illegal play under "on" and tags the violation', function()
            local cfg = with_tricks({ lazy_revoke = "on" })
            local s = tricks_with(cfg, default_hands(), 1)
            s = play_ok(s, 1, c("hearts", "9"))
            -- p2 holds hearts.K and hearts.10; must follow. Under lazy_revoke=off
            -- playing clubs.J would be a must_follow_violation.
            local r = tricks.play(s, 2, c("clubs", "J"))
            assert.is_true(r.ok, "lazy_revoke=on must accept the illegal play")
            -- The violation is tagged in current_trick.revoke_violations.
            local s2 = r.tricks
            assert.is_table(s2.current_trick.revoke_violations)
            assert.are.equal(1, #s2.current_trick.revoke_violations)
            assert.are.equal("must_follow_violation", s2.current_trick.revoke_violations[1].code)
            assert.are.equal(2, s2.current_trick.revoke_violations[1].player)
        end)

        it('still rejects illegal plays under "off" (the standard rule)', function()
            local cfg = with_tricks({ lazy_revoke = "off" })
            local s = tricks_with(cfg, default_hands(), 1)
            s = play_ok(s, 1, c("hearts", "9"))
            local r = tricks.play(s, 2, c("clubs", "J"))
            assert.is_false(r.ok)
            assert.are.equal("must_follow_violation", r.error.code)
        end)

        it("preserves revoke_violations into completed_tricks", function()
            local cfg = with_tricks({ lazy_revoke = "on" })
            local s = tricks_with(cfg, default_hands(), 1)
            s = play_ok(s, 1, c("hearts", "9"))
            s = play_ok(s, 2, c("clubs", "J")) -- revoke
            s = play_ok(s, 3, c("hearts", "A"))
            local last = s.completed_tricks[#s.completed_tricks]
            assert.is_table(last.revoke_violations)
            assert.are.equal(1, #last.revoke_violations)
            assert.are.equal("must_follow_violation", last.revoke_violations[1].code)
        end)

        it("records the revoke action in history", function()
            local cfg = with_tricks({ lazy_revoke = "on" })
            local s = tricks_with(cfg, default_hands(), 1)
            s = play_ok(s, 1, c("hearts", "9"))
            s = play_ok(s, 2, c("clubs", "J"))
            local revoke_entry = nil
            for i = 1, #s.history do
                if s.history[i].action == "revoke" then
                    revoke_entry = s.history[i]
                    break
                end
            end
            assert.is_table(revoke_entry)
            assert.are.equal(2, revoke_entry.player)
            assert.are.equal("must_follow_violation", revoke_entry.code)
        end)
    end)

    describe("draw phase short-circuit", function()
        it("polish_strict and partial_trumping do not engage during draw phase", function()
            -- 2-player Variant A engages the draw phase. Build a config
            -- under that variant with polish_strict + partial_trumping set
            -- and confirm legality stays unrestricted (the existing
            -- short-circuit on phase=="draw" still wins).
            local app_json = require("app.json")
            local parsed = app_json.decode(rule_config.to_json(rule_config.canonical_russian))
            parsed.players.count = 2
            parsed.players.two_player_config = "closed_talon_draw_stock"
            parsed.talon.size = 0
            parsed.tricks.must_overtake_strictness = "polish_strict"
            parsed.tricks.must_trump_strictness = "polish_strict"
            parsed.tricks.partial_trumping = "on"
            local cfg = rule_config.new(parsed)
            -- 2-player Variant A: 9 cards each in hand, 6 in stock.
            local hands_2p = {
                {
                    c("hearts", "9"),
                    c("hearts", "J"),
                    c("hearts", "Q"),
                    c("hearts", "K"),
                    c("hearts", "10"),
                    c("hearts", "A"),
                    c("clubs", "9"),
                    c("clubs", "J"),
                    c("clubs", "Q"),
                },
                {
                    c("clubs", "K"),
                    c("clubs", "10"),
                    c("clubs", "A"),
                    c("diamonds", "9"),
                    c("diamonds", "J"),
                    c("diamonds", "Q"),
                    c("diamonds", "K"),
                    c("diamonds", "10"),
                    c("diamonds", "A"),
                },
            }
            local stock = {
                c("spades", "9"),
                c("spades", "J"),
                c("spades", "Q"),
                c("spades", "K"),
                c("spades", "10"),
                c("spades", "A"),
            }
            local result = tricks.new(cfg, hands_2p, 1, {
                stock = stock,
                trump_indicator = c("spades", "A"),
                declarer = 1,
            })
            assert.is_true(
                result.ok,
                "2-player A fixture must succeed (got "
                    .. (result.error and result.error.code or "?")
                    .. ")"
            )
            local s = result.tricks
            assert.are.equal("draw", s.phase)
            local r = tricks.play(s, 1, c("hearts", "9"))
            assert.is_true(r.ok)
            -- p2 may discard freely under draw phase regardless of polish_strict.
            local lc = tricks.legal_cards(r.tricks, 2)
            assert.is_true(lc.ok)
            assert.are.equal(9, #lc.cards)
        end)
    end)
end)
