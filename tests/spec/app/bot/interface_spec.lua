-- Phase 4.1: the bot interface contract.
-- This spec is the single source of truth for which choosers the bot
-- module is required to provide. Drift between app/bot/init.lua and the
-- task list surfaces here.

local Session = require("app.session")
local bot = require("app.bot.contract")

local EXPECTED_CHOOSERS = {
    {
        name = "choose_bad_talon_redeal",
        phase = "awaiting_bad_talon_decision",
        returns = { "accept_bad_talon_redeal", "decline_bad_talon_redeal" },
    },
    {
        name = "choose_bid",
        phase = "auction",
        returns = { "bid", "pass", "declare_blind", "bid_re_entry", "bid_named_contract" },
    },
    {
        name = "choose_card",
        phase = "tricks",
        returns = { "play" },
    },
    {
        name = "choose_contra",
        phase = "auction",
        returns = { "declare_contra", "declare_redouble", "skip_contra" },
    },
    {
        name = "choose_forced_bid_concession",
        phase = "awaiting_forced_concession_decision",
        returns = { "concede_forced_bid", "decline_forced_bid" },
    },
    {
        name = "choose_marriage",
        phase = "tricks",
        returns = { "declare_marriage" },
    },
    {
        name = "choose_next_deal",
        phase = "deal_done",
        returns = { "start_next_deal" },
    },
    {
        name = "choose_pre_first_trick_marriage",
        phase = "awaiting_pre_first_trick_marriages",
        returns = { "announce_marriage", "skip_announce_marriage" },
    },
    {
        name = "choose_raise",
        phase = "talon",
        returns = { "raise", "skip_raise" },
    },
    {
        name = "choose_rebuy",
        phase = "awaiting_rebuy_decision",
        returns = { "claim_rebuy", "decline_rebuy" },
    },
    {
        name = "choose_redeal",
        phase = "awaiting_redeal_decision",
        returns = { "accept_redeal", "decline_redeal" },
    },
    {
        name = "choose_talon_action",
        phase = "talon",
        returns = { "take_talon", "concede_deal", "buyback_hand" },
    },
    {
        name = "choose_talon_pass",
        phase = "talon",
        returns = { "pass_talon", "pass_polish_talon", "discard_talon" },
    },
    {
        name = "choose_write_off",
        phase = "awaiting_write_off_decision",
        returns = { "accept_play", "write_off" },
    },
}

describe("app.bot interface contract", function()
    it("publishes exactly the expected chooser registry", function()
        assert.are.equal(#EXPECTED_CHOOSERS, #bot.CHOOSERS)
        for i, expected in ipairs(EXPECTED_CHOOSERS) do
            local actual = bot.CHOOSERS[i]
            assert.is_not_nil(actual)
            assert.are.equal(expected.name, actual.name)
            assert.are.equal(expected.phase, actual.phase)
            assert.are.same(expected.returns, actual.returns)
        end
    end)

    it("orders the registry alphabetically by name", function()
        for i = 2, #bot.CHOOSERS do
            assert.is_true(
                bot.CHOOSERS[i - 1].name < bot.CHOOSERS[i].name,
                "CHOOSERS entries must be sorted alphabetically by name"
            )
        end
    end)

    it("freezes the chooser registry against new entries", function()
        assert.error_matches(function()
            bot.CHOOSERS.unexpected = { name = "choose_unexpected" }
        end, "frozen")
    end)

    it("freezes individual chooser entries against new keys", function()
        assert.error_matches(function()
            bot.CHOOSERS[1].extra = "drift"
        end, "frozen")
    end)

    it("freezes the per-entry returns lists against new entries", function()
        assert.error_matches(function()
            bot.CHOOSERS[1].returns[#bot.CHOOSERS[1].returns + 1] = "drift_action"
        end, "frozen")
    end)

    describe("make_view", function()
        it("returns a SessionView that delegates to the session", function()
            local s = Session.new({ seed = 42, dealer = 1 })
            local view = bot.make_view(s)
            assert.are.equal(s:current_phase(), view:current_phase())
            assert.are.equal(s:current_turn(), view:current_turn())
        end)

        it("returns a SessionView that rejects mutator calls", function()
            local s = Session.new({ seed = 42, dealer = 1 })
            local view = bot.make_view(s)
            assert.error_matches(function()
                view:bid(2, 100)
            end, "not exposed")
        end)

        it("returns a SessionView that does not leak its session via a field", function()
            local s = Session.new({ seed = 42, dealer = 1 })
            local view = bot.make_view(s)
            assert.error_matches(function()
                local _ = view._session
            end, "not exposed")
        end)
    end)
end)
