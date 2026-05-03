local marriages = require("core.marriages")
local card = require("core.card")
local rule_config = require("core.rule_config")

local config = rule_config.canonical_russian

local function fresh_marriages()
    local result = marriages.new(config)
    assert.is_true(result.ok, "fixture: marriages.new must succeed")
    return result.marriages
end

-- The fixture passes `tricks_won = 1` by default so the canonical
-- `marriages.trick_required = "on"` rule does not gate happy-path
-- declaration tests. Tests targeting the trick gate itself call
-- `marriages.declare` directly with the count they need to assert.
local function declare(state, player, suit, hand, tricks_won)
    local result = marriages.declare(state, player, suit, hand, tricks_won or 1)
    assert.is_true(
        result.ok,
        "fixture: declare must succeed (got " .. (result.error and result.error.code or "?") .. ")"
    )
    return result.marriages
end

local function king_of(suit)
    return card.new(suit, "K")
end

local function queen_of(suit)
    return card.new(suit, "Q")
end

local function hand_with_marriage(suit, extras)
    local hand = { king_of(suit), queen_of(suit) }
    if extras then
        for i = 1, #extras do
            hand[#hand + 1] = extras[i]
        end
    end
    return hand
end

describe("core.marriages", function()
    describe("module shape", function()
        it("exposes the documented public surface", function()
            assert.is_function(marriages.new)
            assert.is_function(marriages.detect)
            assert.is_function(marriages.declare)
            assert.is_function(marriages.is_marriages)
            assert.is_number(marriages.SCHEMA_VERSION)
        end)

        it("declares the four canonical suits", function()
            local seen = {}
            for _, suit in ipairs(marriages.SUITS) do
                seen[suit] = true
            end
            assert.is_true(seen.hearts)
            assert.is_true(seen.diamonds)
            assert.is_true(seen.clubs)
            assert.is_true(seen.spades)
            assert.are.equal(4, #marriages.SUITS)
        end)
    end)

    describe("new()", function()
        it("rejects a non-RuleConfig", function()
            for _, bad in ipairs({ 42, "config", {}, true }) do
                local result = marriages.new(bad)
                assert.is_false(result.ok)
                assert.are.equal("not_a_rule_config", result.error.code)
            end
            local nil_result = marriages.new(nil)
            assert.is_false(nil_result.ok)
            assert.are.equal("not_a_rule_config", nil_result.error.code)
        end)

        it("starts with no trump declared", function()
            local m = fresh_marriages()
            assert.is_nil(m.trump)
        end)

        it("starts with zero bonus per player", function()
            local m = fresh_marriages()
            assert.are.equal(config.players.count, #m.bonuses)
            for i = 1, #m.bonuses do
                assert.are.equal(0, m.bonuses[i])
            end
        end)

        it("starts with no declarations recorded", function()
            local m = fresh_marriages()
            assert.are.equal(0, #m.declarations)
        end)

        it("tags the state so is_marriages recognises it", function()
            local m = fresh_marriages()
            assert.is_true(marriages.is_marriages(m))
        end)

        it("stamps the schema version on the state", function()
            local m = fresh_marriages()
            assert.are.equal(marriages.SCHEMA_VERSION, m.schema_version)
        end)

        it("retains the config for later reads", function()
            local m = fresh_marriages()
            assert.are.equal(config, m.config)
        end)
    end)

    describe("is_marriages()", function()
        it("rejects non-tables", function()
            assert.is_false(marriages.is_marriages(nil))
            assert.is_false(marriages.is_marriages(42))
            assert.is_false(marriages.is_marriages("marriages"))
            assert.is_false(marriages.is_marriages(true))
        end)

        it("rejects plain tables without the type tag", function()
            assert.is_false(marriages.is_marriages({}))
            assert.is_false(marriages.is_marriages({
                trump = "hearts",
                bonuses = { 0, 0, 0 },
                declarations = {},
            }))
        end)

        it("accepts a state produced by new()", function()
            assert.is_true(marriages.is_marriages(fresh_marriages()))
        end)

        it("accepts a state produced by declare()", function()
            local hand = hand_with_marriage("hearts")
            local declared = declare(fresh_marriages(), 1, "hearts", hand)
            assert.is_true(marriages.is_marriages(declared))
        end)
    end)

    describe("detect()", function()
        it("returns an empty list for an empty hand", function()
            local found = marriages.detect({})
            assert.are.equal(0, #found)
        end)

        it("ignores a hand that holds only the King", function()
            local found = marriages.detect({ king_of("hearts") })
            assert.are.equal(0, #found)
        end)

        it("ignores a hand that holds only the Queen", function()
            local found = marriages.detect({ queen_of("hearts") })
            assert.are.equal(0, #found)
        end)

        it("ignores K + Q from different suits", function()
            local found = marriages.detect({ king_of("hearts"), queen_of("diamonds") })
            assert.are.equal(0, #found)
        end)

        it("detects a single marriage", function()
            local found = marriages.detect(hand_with_marriage("clubs"))
            assert.are.same({ "clubs" }, found)
        end)

        it("detects every suit on its own", function()
            for _, suit in ipairs({ "hearts", "diamonds", "clubs", "spades" }) do
                local found = marriages.detect(hand_with_marriage(suit))
                assert.are.same({ suit }, found)
            end
        end)

        it("detects multiple marriages in a single hand", function()
            local hand = {
                king_of("hearts"),
                queen_of("hearts"),
                king_of("clubs"),
                queen_of("clubs"),
            }
            local found = marriages.detect(hand)
            assert.are.same({ "hearts", "clubs" }, found)
        end)

        it("returns marriages in canonical descending-value order", function()
            -- Build a hand with all four marriages; the value order is
            -- hearts (100) > diamonds (80) > clubs (60) > spades (40).
            local hand = {}
            for _, suit in ipairs({ "spades", "clubs", "diamonds", "hearts" }) do
                hand[#hand + 1] = king_of(suit)
                hand[#hand + 1] = queen_of(suit)
            end
            local found = marriages.detect(hand)
            assert.are.same({ "hearts", "diamonds", "clubs", "spades" }, found)
        end)

        it("works on a full 8-card hand", function()
            local hand = hand_with_marriage("diamonds", {
                card.new("hearts", "9"),
                card.new("hearts", "J"),
                card.new("clubs", "9"),
                card.new("spades", "A"),
                card.new("diamonds", "10"),
                card.new("spades", "K"),
            })
            assert.are.equal(8, #hand)
            local found = marriages.detect(hand)
            assert.are.same({ "diamonds" }, found)
        end)

        it("raises a clear error on a non-table hand", function()
            assert.has_error(function()
                marriages.detect("hand")
            end)
        end)

        it("raises a clear error on a non-card entry", function()
            assert.has_error(function()
                marriages.detect({ king_of("hearts"), 42 })
            end)
        end)
    end)

    describe("declare()", function()
        it("credits the marriage value to the declaring player", function()
            local hand = hand_with_marriage("hearts")
            local m = declare(fresh_marriages(), 1, "hearts", hand)
            assert.are.equal(100, m.bonuses[1])
            assert.are.equal(0, m.bonuses[2])
            assert.are.equal(0, m.bonuses[3])
        end)

        it("sets the trump suit to the declared suit", function()
            local hand = hand_with_marriage("clubs")
            local m = declare(fresh_marriages(), 2, "clubs", hand)
            assert.are.equal("clubs", m.trump)
        end)

        it("posts the bonus exactly per the canonical config table", function()
            for suit, expected in pairs(config.marriages.values) do
                local hand = hand_with_marriage(suit)
                local m = declare(fresh_marriages(), 1, suit, hand)
                assert.are.equal(expected, m.bonuses[1], "expected " .. expected .. " for " .. suit)
            end
        end)

        it("appends a declaration entry", function()
            local hand = hand_with_marriage("diamonds")
            local m = declare(fresh_marriages(), 3, "diamonds", hand)
            assert.are.equal(1, #m.declarations)
            local entry = m.declarations[1]
            assert.are.equal(3, entry.player)
            assert.are.equal("diamonds", entry.suit)
            assert.are.equal(80, entry.value)
        end)

        it("returns a new state without mutating the input", function()
            local before = fresh_marriages()
            local hand = hand_with_marriage("hearts")
            local after = declare(before, 1, "hearts", hand)
            assert.are_not.equal(before, after)
            assert.is_nil(before.trump)
            assert.are.equal(0, before.bonuses[1])
            assert.are.equal(0, #before.declarations)
            assert.are.equal("hearts", after.trump)
            assert.are.equal(100, after.bonuses[1])
            assert.are.equal(1, #after.declarations)
        end)

        it("replaces trump when a second marriage is declared", function()
            local m = fresh_marriages()
            m = declare(m, 1, "spades", hand_with_marriage("spades"))
            assert.are.equal("spades", m.trump)
            m = declare(m, 1, "hearts", hand_with_marriage("hearts"))
            assert.are.equal("hearts", m.trump)
        end)

        it("accumulates bonuses across multiple declarations", function()
            local m = fresh_marriages()
            m = declare(m, 1, "spades", hand_with_marriage("spades")) -- 40
            m = declare(m, 1, "hearts", hand_with_marriage("hearts")) -- 100
            assert.are.equal(140, m.bonuses[1])
            assert.are.equal(2, #m.declarations)
        end)

        it("credits bonuses to different players independently", function()
            local m = fresh_marriages()
            m = declare(m, 2, "hearts", hand_with_marriage("hearts")) -- 100 to player 2
            m = declare(m, 3, "clubs", hand_with_marriage("clubs")) -- 60 to player 3
            assert.are.equal(0, m.bonuses[1])
            assert.are.equal(100, m.bonuses[2])
            assert.are.equal(60, m.bonuses[3])
        end)

        it("preserves declarations in chronological order", function()
            local m = fresh_marriages()
            m = declare(m, 1, "spades", hand_with_marriage("spades"))
            m = declare(m, 2, "diamonds", hand_with_marriage("diamonds"))
            m = declare(m, 3, "clubs", hand_with_marriage("clubs"))
            local suits = {}
            for i = 1, #m.declarations do
                suits[i] = m.declarations[i].suit
            end
            assert.are.same({ "spades", "diamonds", "clubs" }, suits)
        end)

        it("accepts a marriage whose K+Q arrived through the talon pass", function()
            -- The 1.5 spec treats marriages "formed through the talon" as
            -- legal: only the hand at declaration time matters. Build an
            -- 8-card hand mid-deal that includes the K+Q and confirm
            -- declaration succeeds.
            local hand = {
                card.new("diamonds", "9"),
                card.new("diamonds", "J"),
                card.new("hearts", "A"),
                card.new("clubs", "10"),
                card.new("spades", "9"),
                card.new("spades", "K"),
                king_of("hearts"),
                queen_of("hearts"),
            }
            local m = declare(fresh_marriages(), 1, "hearts", hand)
            assert.are.equal(100, m.bonuses[1])
            assert.are.equal("hearts", m.trump)
        end)
    end)

    describe("declare() errors", function()
        local function err(state, player, suit, hand)
            local result = marriages.declare(state, player, suit, hand)
            assert.is_false(result.ok)
            return result.error
        end

        it("rejects a state that is not a marriages state", function()
            for _, bad in ipairs({ 42, "marriages", {}, true }) do
                local e = err(bad, 1, "hearts", hand_with_marriage("hearts"))
                assert.are.equal("not_a_marriages", e.code)
            end
            local nil_err = err(nil, 1, "hearts", hand_with_marriage("hearts"))
            assert.are.equal("not_a_marriages", nil_err.code)
        end)

        it("rejects a non-integer player", function()
            local m = fresh_marriages()
            local hand = hand_with_marriage("hearts")
            for _, bad in ipairs({ 1.5, "1", true, {} }) do
                local e = err(m, bad, "hearts", hand)
                assert.are.equal("bad_player", e.code)
            end
            local nil_err = err(m, nil, "hearts", hand)
            assert.are.equal("bad_player", nil_err.code)
        end)

        it("rejects a player below 1", function()
            local m = fresh_marriages()
            local e = err(m, 0, "hearts", hand_with_marriage("hearts"))
            assert.are.equal("bad_player", e.code)
        end)

        it("rejects a player above the configured count", function()
            local m = fresh_marriages()
            local e = err(m, config.players.count + 1, "hearts", hand_with_marriage("hearts"))
            assert.are.equal("bad_player", e.code)
        end)

        it("rejects an unknown suit", function()
            local m = fresh_marriages()
            for _, bad in ipairs({ "trump", "h", "Hearts", "" }) do
                local e = err(m, 1, bad, hand_with_marriage("hearts"))
                assert.are.equal("bad_suit", e.code)
            end
        end)

        it("rejects a non-string suit", function()
            local m = fresh_marriages()
            for _, bad in ipairs({ 42, true, {} }) do
                local e = err(m, 1, bad, hand_with_marriage("hearts"))
                assert.are.equal("bad_suit", e.code)
            end
            local nil_err = err(m, 1, nil, hand_with_marriage("hearts"))
            assert.are.equal("bad_suit", nil_err.code)
        end)

        it("rejects when the K of the suit is missing from the hand", function()
            local m = fresh_marriages()
            local hand = { queen_of("hearts") }
            local e = err(m, 1, "hearts", hand)
            assert.are.equal("card_not_in_hand", e.code)
        end)

        it("rejects when the Q of the suit is missing from the hand", function()
            local m = fresh_marriages()
            local hand = { king_of("hearts") }
            local e = err(m, 1, "hearts", hand)
            assert.are.equal("card_not_in_hand", e.code)
        end)

        it("rejects when both K and Q of the suit are missing", function()
            local m = fresh_marriages()
            local e = err(m, 1, "hearts", hand_with_marriage("clubs"))
            assert.are.equal("card_not_in_hand", e.code)
        end)

        it("rejects a non-table hand", function()
            local m = fresh_marriages()
            local e = err(m, 1, "hearts", "hand")
            assert.are.equal("card_not_in_hand", e.code)
        end)

        it("rejects a hand that contains a non-card entry", function()
            local m = fresh_marriages()
            local hand = { king_of("hearts"), queen_of("hearts"), 42 }
            local e = err(m, 1, "hearts", hand)
            assert.are.equal("card_not_in_hand", e.code)
        end)

        it("rejects re-declaring the same suit", function()
            local m = fresh_marriages()
            m = declare(m, 1, "hearts", hand_with_marriage("hearts"))
            local e = err(m, 1, "hearts", hand_with_marriage("hearts"))
            assert.are.equal("marriage_suit_already_declared", e.code)
        end)

        it("does not block a different suit after one has been declared", function()
            local m = fresh_marriages()
            m = declare(m, 1, "hearts", hand_with_marriage("hearts"))
            -- This must succeed; declaring a second, distinct suit is the
            -- multiple-marriages path documented in the rules.
            m = declare(m, 1, "clubs", hand_with_marriage("clubs"))
            assert.are.equal("clubs", m.trump)
            assert.are.equal(160, m.bonuses[1])
        end)
    end)

    -- Phase 3.6 marriage house rules ---------------------------------------

    local json = require("app.json")

    local function config_with_marriage_overrides(overrides)
        local blob = json.decode(rule_config.to_json(rule_config.canonical_russian))
        for key, value in pairs(overrides) do
            blob.marriages[key] = value
        end
        return rule_config.new(blob)
    end

    describe("declare() honours marriages.one_trump_per_deal", function()
        it("leaves trump unchanged on the second K-Q declaration when 'on'", function()
            local cfg = config_with_marriage_overrides({ one_trump_per_deal = "on" })
            local result = marriages.new(cfg)
            assert.is_true(result.ok)
            local m = result.marriages
            m = declare(m, 1, "hearts", hand_with_marriage("hearts"))
            assert.are.equal("hearts", m.trump)
            m = declare(m, 2, "spades", hand_with_marriage("spades"))
            assert.are.equal("hearts", m.trump, "second declaration must not flip trump")
            assert.are.equal(40, m.bonuses[2], "bonus still posts under one_trump_per_deal")
        end)

        it("flips trump on every K-Q declaration when 'off' (default)", function()
            local m = fresh_marriages()
            m = declare(m, 1, "hearts", hand_with_marriage("hearts"))
            m = declare(m, 2, "spades", hand_with_marriage("spades"))
            assert.are.equal("spades", m.trump)
        end)
    end)

    describe("announce_from_hand()", function()
        it("records a K-Q marriage and sets trump", function()
            local m = fresh_marriages()
            local result =
                marriages.announce_from_hand(m, 1, "hearts", hand_with_marriage("hearts"), 1)
            assert.is_true(result.ok)
            assert.are.equal("hearts", result.marriages.trump)
            assert.are.equal(100, result.marriages.bonuses[1])
            assert.are.equal(1, #result.marriages.declarations)
            assert.are.equal("kq", result.marriages.declarations[1].kind)
        end)

        it("rejects when the hand is missing K or Q", function()
            local m = fresh_marriages()
            local result = marriages.announce_from_hand(m, 1, "hearts", { king_of("hearts") }, 1)
            assert.is_false(result.ok)
            assert.are.equal("card_not_in_hand", result.error.code)
        end)

        it("respects one_trump_per_deal", function()
            local cfg = config_with_marriage_overrides({ one_trump_per_deal = "on" })
            local m = marriages.new(cfg).marriages
            m =
                marriages.announce_from_hand(m, 1, "hearts", hand_with_marriage("hearts"), 1).marriages
            local r = marriages.announce_from_hand(m, 2, "spades", hand_with_marriage("spades"), 1)
            assert.is_true(r.ok)
            assert.are.equal("hearts", r.marriages.trump)
        end)
    end)

    describe("declare_ace_marriage()", function()
        local function four_aces_hand(extras)
            local hand = {
                card.new("hearts", "A"),
                card.new("diamonds", "A"),
                card.new("clubs", "A"),
                card.new("spades", "A"),
            }
            if extras then
                for i = 1, #extras do
                    hand[#hand + 1] = extras[i]
                end
            end
            return hand
        end

        it("rejects when ace_marriage = 'off'", function()
            local m = fresh_marriages()
            local r = marriages.declare_ace_marriage(m, 1, four_aces_hand(), 1)
            assert.is_false(r.ok)
            assert.are.equal("ace_marriage_disabled", r.error.code)
        end)

        it("awards ace_marriage_value under 'on' without setting trump", function()
            local cfg = config_with_marriage_overrides({ ace_marriage = "on" })
            local m = marriages.new(cfg).marriages
            local r = marriages.declare_ace_marriage(m, 1, four_aces_hand(), 1)
            assert.is_true(r.ok)
            assert.are.equal(200, r.marriages.bonuses[1])
            assert.is_nil(r.marriages.trump)
            assert.is_nil(r.marriages.pending_ace_trump)
            assert.are.equal("ace_marriage", r.marriages.declarations[1].kind)
        end)

        it("marks pending_ace_trump under 'sets_trump'", function()
            local cfg = config_with_marriage_overrides({ ace_marriage = "sets_trump" })
            local m = marriages.new(cfg).marriages
            local r = marriages.declare_ace_marriage(m, 2, four_aces_hand(), 1)
            assert.is_true(r.ok)
            assert.are.equal(2, r.marriages.pending_ace_trump)
        end)

        it("rejects without four aces in hand", function()
            local cfg = config_with_marriage_overrides({ ace_marriage = "on" })
            local m = marriages.new(cfg).marriages
            local hand = {
                card.new("hearts", "A"),
                card.new("diamonds", "A"),
                card.new("clubs", "A"),
                card.new("spades", "K"),
            }
            local r = marriages.declare_ace_marriage(m, 1, hand, 1)
            assert.is_false(r.ok)
            assert.are.equal("ace_marriage_requires_four_aces", r.error.code)
        end)

        it("rejects re-declaring the ace marriage", function()
            local cfg = config_with_marriage_overrides({ ace_marriage = "on" })
            local m = marriages.new(cfg).marriages
            m = marriages.declare_ace_marriage(m, 1, four_aces_hand(), 1).marriages
            local r = marriages.declare_ace_marriage(m, 1, four_aces_hand(), 1)
            assert.is_false(r.ok)
            assert.are.equal("ace_marriage_already_declared", r.error.code)
        end)

        it("uses the configured ace_marriage_value", function()
            local cfg = config_with_marriage_overrides({
                ace_marriage = "on",
                ace_marriage_value = 250,
            })
            local m = marriages.new(cfg).marriages
            local r = marriages.declare_ace_marriage(m, 1, four_aces_hand(), 1)
            assert.is_true(r.ok)
            assert.are.equal(250, r.marriages.bonuses[1])
        end)
    end)

    describe("activate_ace_trump()", function()
        it("sets trump and clears pending_ace_trump", function()
            local cfg = config_with_marriage_overrides({ ace_marriage = "sets_trump" })
            local m = marriages.new(cfg).marriages
            m = marriages.declare_ace_marriage(m, 1, {
                card.new("hearts", "A"),
                card.new("diamonds", "A"),
                card.new("clubs", "A"),
                card.new("spades", "A"),
            }, 1).marriages
            local r = marriages.activate_ace_trump(m, "diamonds")
            assert.is_true(r.ok)
            assert.are.equal("diamonds", r.marriages.trump)
            assert.is_nil(r.marriages.pending_ace_trump)
        end)

        it("rejects when no pending ace-trump activation is recorded", function()
            local m = fresh_marriages()
            local r = marriages.activate_ace_trump(m, "hearts")
            assert.is_false(r.ok)
            assert.are.equal("no_pending_ace_trump", r.error.code)
        end)
    end)

    describe("cancel_drowned()", function()
        it("reverses the bonus and marks the declaration cancelled", function()
            local m = fresh_marriages()
            m = declare(m, 1, "hearts", hand_with_marriage("hearts"))
            assert.are.equal(100, m.bonuses[1])
            local r = marriages.cancel_drowned(m, "hearts")
            assert.is_true(r.ok)
            assert.are.equal(0, r.marriages.bonuses[1])
            assert.is_true(r.marriages.declarations[1].cancelled)
        end)

        it("does NOT revert the trump suit", function()
            local m = fresh_marriages()
            m = declare(m, 1, "hearts", hand_with_marriage("hearts"))
            local r = marriages.cancel_drowned(m, "hearts")
            assert.is_true(r.ok)
            assert.are.equal("hearts", r.marriages.trump)
        end)

        it("rejects when no active marriage in the suit exists", function()
            local m = fresh_marriages()
            local r = marriages.cancel_drowned(m, "hearts")
            assert.is_false(r.ok)
            assert.are.equal("no_active_marriage", r.error.code)
        end)

        it("allows a re-declaration of the cancelled suit", function()
            local m = fresh_marriages()
            m = declare(m, 1, "hearts", hand_with_marriage("hearts"))
            m = marriages.cancel_drowned(m, "hearts").marriages
            local r = marriages.declare(m, 2, "hearts", hand_with_marriage("hearts"), 1)
            assert.is_true(r.ok)
            assert.are.equal(100, r.marriages.bonuses[2])
        end)
    end)

    describe("trick_required gate", function()
        local function four_aces_hand()
            return {
                card.new("hearts", "A"),
                card.new("diamonds", "A"),
                card.new("clubs", "A"),
                card.new("spades", "A"),
            }
        end

        it(
            "declare() rejects a K-Q marriage when no trick has been captured under trick_required=on",
            function()
                local cfg = config_with_marriage_overrides({ trick_required = "on" })
                local m = marriages.new(cfg).marriages
                local r = marriages.declare(m, 1, "hearts", hand_with_marriage("hearts"), 0)
                assert.is_false(r.ok)
                assert.are.equal("trick_required_not_met", r.error.code)
            end
        )

        it("declare() accepts a K-Q marriage with at least one trick captured", function()
            local cfg = config_with_marriage_overrides({ trick_required = "on" })
            local m = marriages.new(cfg).marriages
            local r = marriages.declare(m, 1, "hearts", hand_with_marriage("hearts"), 1)
            assert.is_true(r.ok)
        end)

        it("declare() ignores tricks_won when trick_required=off", function()
            local cfg = config_with_marriage_overrides({ trick_required = "off" })
            local m = marriages.new(cfg).marriages
            local r = marriages.declare(m, 1, "hearts", hand_with_marriage("hearts"), 0)
            assert.is_true(r.ok)
        end)

        it(
            "announce_from_hand() rejects without a captured trick under trick_required=on",
            function()
                local cfg = config_with_marriage_overrides({ trick_required = "on" })
                local m = marriages.new(cfg).marriages
                local r =
                    marriages.announce_from_hand(m, 1, "hearts", hand_with_marriage("hearts"), 0)
                assert.is_false(r.ok)
                assert.are.equal("trick_required_not_met", r.error.code)
            end
        )

        it("announce_from_hand() ignores tricks_won when trick_required=off", function()
            local cfg = config_with_marriage_overrides({ trick_required = "off" })
            local m = marriages.new(cfg).marriages
            local r = marriages.announce_from_hand(m, 1, "hearts", hand_with_marriage("hearts"), 0)
            assert.is_true(r.ok)
        end)

        it(
            "declare_ace_marriage() rejects without a captured trick under trick_required=on",
            function()
                local cfg =
                    config_with_marriage_overrides({ ace_marriage = "on", trick_required = "on" })
                local m = marriages.new(cfg).marriages
                local r = marriages.declare_ace_marriage(m, 1, four_aces_hand(), 0)
                assert.is_false(r.ok)
                assert.are.equal("trick_required_not_met", r.error.code)
            end
        )

        it("declare_ace_marriage() accepts when a trick has been captured", function()
            local cfg =
                config_with_marriage_overrides({ ace_marriage = "on", trick_required = "on" })
            local m = marriages.new(cfg).marriages
            local r = marriages.declare_ace_marriage(m, 1, four_aces_hand(), 1)
            assert.is_true(r.ok)
        end)

        it("declare_ace_marriage() ignores tricks_won when trick_required=off", function()
            local cfg =
                config_with_marriage_overrides({ ace_marriage = "on", trick_required = "off" })
            local m = marriages.new(cfg).marriages
            local r = marriages.declare_ace_marriage(m, 1, four_aces_hand(), 0)
            assert.is_true(r.ok)
        end)
    end)
end)
