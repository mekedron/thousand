-- End-to-end journey for the Phase 3.6 marriage-variants UI. Builds a
-- session positioned mid-tricks under each marriage house rule and
-- asserts the table view-model surfaces the matching affordance keys.
-- Full Love2D rendering is exercised at the unit-spec level
-- (`tests/spec/ui/scenes/table_spec.lua`); these journeys validate the
-- view-model contract the scene renders against.

local Session = require("app.session")
local view_model = require("app.table_view_model")
local rule_config = require("core.rule_config")
local card = require("core.card")
local json = require("app.json")
local marriages_module = require("core.marriages")
local auction_module = require("core.auction")
local tricks_module = require("core.tricks")

local function c(suit, rank)
    return card.new(suit, rank)
end

local function with_overrides(overrides)
    local blob = json.decode(rule_config.to_json(rule_config.canonical_russian))
    overrides = overrides or {}
    for k, v in pairs(overrides) do
        blob.marriages[k] = v
    end
    return rule_config.new(blob)
end

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

local function aces_layout()
    return {
        {
            c("hearts", "K"),
            c("hearts", "Q"),
            c("hearts", "J"),
            c("diamonds", "K"),
            c("diamonds", "Q"),
            c("diamonds", "J"),
            c("clubs", "9"),
            c("spades", "9"),
        },
        {
            c("hearts", "A"),
            c("diamonds", "A"),
            c("clubs", "A"),
            c("spades", "A"),
            c("hearts", "10"),
            c("diamonds", "10"),
            c("clubs", "10"),
            c("spades", "10"),
        },
        {
            c("hearts", "9"),
            c("diamonds", "9"),
            c("clubs", "K"),
            c("clubs", "Q"),
            c("clubs", "J"),
            c("spades", "K"),
            c("spades", "Q"),
            c("spades", "J"),
        },
    }
end

local function session_at_tricks(test_config, hands, opts)
    opts = opts or {}
    local dealer = opts.dealer or 1
    local pc = test_config.players.count
    local declarer = opts.declarer or ((dealer % pc) + 1)
    local running_totals = {}
    for i = 1, pc do
        running_totals[i] = 0
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
    }).tricks

    return Session.from_state({
        config = test_config,
        seed = 1,
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

describe("marriage variants journey", function()
    describe("hand_announcement timing", function()
        it("surfaces the announce-from-hand offer for the leader", function()
            local cfg = with_overrides({ marriage_announcement_timing = "hand_announcement" })
            local s = session_at_tricks(cfg, full_deal_layout())
            local view = view_model.from_session(s)
            assert.is_table(view.hand_announcement_marriage_offer)
            assert.are.equal(2, view.hand_announcement_marriage_offer.seat)
            assert.is_table(view.hand_announcement_marriage_offer.suits)
            assert.is_true(#view.hand_announcement_marriage_offer.suits > 0)
            -- The on-lead K/Q-tap modal is suppressed under this variant.
            assert.is_nil(view.marriage_offer)
        end)

        it("clears the offer once the marriage is announced", function()
            local cfg = with_overrides({ marriage_announcement_timing = "hand_announcement" })
            local s = session_at_tricks(cfg, full_deal_layout())
            assert.is_true(s:announce_marriage(2, "hearts").ok)
            local view = view_model.from_session(s)
            -- Hearts is no longer available for re-declaration; offer is
            -- still present for the second marriage in clubs.
            assert.is_table(view.hand_announcement_marriage_offer)
            local has_clubs = false
            for _, suit in ipairs(view.hand_announcement_marriage_offer.suits) do
                if suit == "clubs" then
                    has_clubs = true
                end
            end
            assert.is_true(has_clubs)
        end)
    end)

    describe("pre_first_trick timing", function()
        it("surfaces the announcement queue", function()
            local cfg = with_overrides({ marriage_announcement_timing = "pre_first_trick" })
            local s = session_at_tricks(cfg, full_deal_layout())
            local view = view_model.from_session(s)
            assert.is_table(view.pre_first_trick_marriage_offer)
            assert.are.equal(2, view.pre_first_trick_marriage_offer.seat)
            assert.are.equal("awaiting_pre_first_trick_marriages", view.phase)
        end)

        it("closes the queue after every seat resolves", function()
            local cfg = with_overrides({ marriage_announcement_timing = "pre_first_trick" })
            local s = session_at_tricks(cfg, full_deal_layout())
            assert.is_true(s:skip_pre_first_trick_marriage(2).ok)
            assert.is_true(s:skip_pre_first_trick_marriage(3).ok)
            assert.is_true(s:skip_pre_first_trick_marriage(1).ok)
            local view = view_model.from_session(s)
            assert.is_nil(view.pre_first_trick_marriage_offer)
            assert.are.equal("tricks", view.phase)
        end)
    end)

    describe("ace_marriage", function()
        it("surfaces the four-aces declaration affordance", function()
            local cfg = with_overrides({ ace_marriage = "on" })
            local s = session_at_tricks(cfg, aces_layout())
            local view = view_model.from_session(s)
            assert.is_table(view.ace_marriage_offer)
            assert.are.equal(2, view.ace_marriage_offer.seat)
        end)

        it("clears the offer after declaration", function()
            local cfg = with_overrides({ ace_marriage = "on" })
            local s = session_at_tricks(cfg, aces_layout())
            assert.is_true(s:declare_ace_marriage(2).ok)
            local view = view_model.from_session(s)
            assert.is_nil(view.ace_marriage_offer)
        end)

        it("exposes the pending_ace_trump_seat under sets_trump", function()
            local cfg = with_overrides({ ace_marriage = "sets_trump" })
            local s = session_at_tricks(cfg, aces_layout())
            assert.is_true(s:declare_ace_marriage(2).ok)
            local view = view_model.from_session(s)
            assert.are.equal(2, view.pending_ace_trump_seat)
        end)
    end)

    describe("drowned_marriage", function()
        it("surfaces the drowned-marriage banner", function()
            local cfg = with_overrides({
                drowned_marriage = "retroactive_cancel",
                trump_activation_timing = "immediate",
            })
            local s = session_at_tricks(cfg, full_deal_layout())
            assert.is_true(s:declare_marriage(2, "hearts").ok)
            assert.is_true(s:play(2, c("hearts", "K")).ok)
            assert.is_true(s:play(3, c("hearts", "A")).ok)
            assert.is_true(s:play(1, c("diamonds", "9")).ok)
            local view = view_model.from_session(s)
            assert.is_table(view.drowned_marriage_banner)
            assert.are.equal("hearts", view.drowned_marriage_banner.suit)
            assert.are.equal(2, view.drowned_marriage_banner.declarer)
        end)
    end)

    describe("trump_activation_timing", function()
        it("default next_trick keeps trump nil on declaring trick", function()
            local cfg = with_overrides({ trump_activation_timing = "next_trick" })
            local s = session_at_tricks(cfg, full_deal_layout())
            assert.is_true(s:declare_marriage(2, "hearts").ok)
            local view = view_model.from_session(s)
            assert.is_nil(view.trump)
        end)

        it("immediate flips trump on declaration", function()
            local cfg = with_overrides({ trump_activation_timing = "immediate" })
            local s = session_at_tricks(cfg, full_deal_layout())
            assert.is_true(s:declare_marriage(2, "hearts").ok)
            local view = view_model.from_session(s)
            assert.are.equal("hearts", view.trump)
        end)
    end)
end)
