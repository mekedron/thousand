-- Phase 4.1: SessionView is the read-only proxy a bot operates on.
-- Verifies (a) every listed accessor delegates to the underlying Session,
-- (b) no engine mutator is reachable through the view, (c) the view does
-- not expose its captured session via any field on the table.

local Session = require("app.session")
local session_view = require("app.bot.session_view")

local function fresh_auction_session()
    return Session.new({ seed = 42, dealer = 1 })
end

local function drive_to_talon()
    local s = Session.new({ seed = 42, dealer = 1 })
    assert(s:bid(2, 100).ok)
    assert(s:pass(3).ok)
    assert(s:pass(1).ok)
    return s
end

local function clear_write_off_prompt_if_pending(s)
    if s:current_phase() == "awaiting_write_off_decision" then
        assert(s:accept_play().ok)
    end
end

local function drive_to_tricks()
    local s = drive_to_talon()
    assert(s:take_talon().ok)
    clear_write_off_prompt_if_pending(s)
    local hand = s:hands()[2]
    assert(s:pass_talon(1, hand[1]).ok)
    hand = s:hands()[2]
    assert(s:pass_talon(3, hand[1]).ok)
    assert(s:skip_raise().ok)
    return s
end

describe("app.bot.session_view", function()
    describe("M.new", function()
        it("requires a session argument", function()
            assert.error_matches(function()
                session_view.new(nil)
            end, "session is required")
        end)

        it("returns a table", function()
            local view = session_view.new(fresh_auction_session())
            assert.are.equal("table", type(view))
        end)
    end)

    describe("accessor delegation", function()
        it("forwards hands()", function()
            local s = fresh_auction_session()
            local view = session_view.new(s)
            assert.are.same(s:hands(), view:hands())
        end)

        it("forwards current_turn()", function()
            local s = fresh_auction_session()
            local view = session_view.new(s)
            assert.are.equal(s:current_turn(), view:current_turn())
        end)

        it("forwards current_phase()", function()
            local s = fresh_auction_session()
            local view = session_view.new(s)
            assert.are.equal(s:current_phase(), view:current_phase())
        end)

        it("forwards current_bid() — nil during early auction", function()
            local s = fresh_auction_session()
            local view = session_view.new(s)
            assert.is_nil(s:current_bid())
            assert.is_nil(view:current_bid())
        end)

        it("forwards current_bid() — set once a bid lands", function()
            local s = drive_to_talon()
            local view = session_view.new(s)
            assert.are.equal(s:current_bid(), view:current_bid())
            assert.are.equal(100, view:current_bid())
        end)

        it("forwards trump() — nil pre-marriage", function()
            local s = fresh_auction_session()
            local view = session_view.new(s)
            assert.is_nil(s:trump())
            assert.is_nil(view:trump())
        end)

        it("forwards talon_cards() during the auction", function()
            local s = fresh_auction_session()
            local view = session_view.new(s)
            assert.are.same(s:talon_cards(), view:talon_cards())
            assert.are.equal(3, #view:talon_cards())
        end)

        it("forwards talon_substate() — nil during auction, 'action' at revealed", function()
            local fresh = fresh_auction_session()
            local fresh_view = session_view.new(fresh)
            assert.is_nil(fresh_view:talon_substate())

            local at_talon = drive_to_talon()
            local at_talon_view = session_view.new(at_talon)
            assert.are.equal("action", at_talon_view:talon_substate())
        end)

        it("forwards talon_pass_targets() — list during pass, nil otherwise", function()
            local fresh = fresh_auction_session()
            local fresh_view = session_view.new(fresh)
            assert.is_nil(fresh_view:talon_pass_targets())

            local at_pass = drive_to_talon()
            assert(at_pass:take_talon().ok)
            if at_pass:current_phase() == "awaiting_write_off_decision" then
                assert(at_pass:accept_play().ok)
            end
            local at_pass_view = session_view.new(at_pass)
            assert.are.same(at_pass:talon_pass_targets(), at_pass_view:talon_pass_targets())
            assert.are.same({ 1, 3 }, at_pass_view:talon_pass_targets())
        end)

        it("forwards config() — same reference as Session:config", function()
            local s = fresh_auction_session()
            local view = session_view.new(s)
            assert.are.equal(s:config(), view:config())
        end)

        it("forwards legal_cards(seat) during tricks", function()
            local s = drive_to_tricks()
            local seat = s:current_turn()
            local view = session_view.new(s)
            assert.are.same(s:legal_cards(seat), view:legal_cards(seat))
            assert.is_true(#view:legal_cards(seat) > 0)
        end)

        it("forwards available_marriages(seat) during tricks", function()
            local s = drive_to_tricks()
            local seat = s:current_turn()
            local view = session_view.new(s)
            assert.are.same(s:available_marriages(seat), view:available_marriages(seat))
        end)

        it("forwards current_trick() — nil pre-tricks", function()
            local s = fresh_auction_session()
            local view = session_view.new(s)
            assert.is_nil(s:current_trick())
            assert.is_nil(view:current_trick())
        end)

        it("forwards current_trick() — table during tricks", function()
            local s = drive_to_tricks()
            local view = session_view.new(s)
            local trick = s:current_trick()
            assert.is_not_nil(trick)
            assert.are.same(trick, view:current_trick())
        end)

        it("forwards redeal_offer() — nil when no offer is pending", function()
            local s = fresh_auction_session()
            local view = session_view.new(s)
            assert.are.equal(s:redeal_offer(), view:redeal_offer())
        end)

        it("forwards bad_talon_offer_state() — nil when no offer is pending", function()
            local s = fresh_auction_session()
            local view = session_view.new(s)
            assert.are.equal(s:bad_talon_offer_state(), view:bad_talon_offer_state())
        end)

        it("forwards rebuy_offer_state() — nil when no offer is pending", function()
            local s = fresh_auction_session()
            local view = session_view.new(s)
            assert.are.equal(s:rebuy_offer_state(), view:rebuy_offer_state())
        end)
    end)

    describe("mutator rejection", function()
        it("does not expose Session:bid", function()
            local view = session_view.new(fresh_auction_session())
            assert.error_matches(function()
                view:bid(2, 100)
            end, "not exposed")
        end)

        it("does not expose Session:play", function()
            local view = session_view.new(fresh_auction_session())
            assert.error_matches(function()
                view:play(2, { suit = "hearts", rank = "A" })
            end, "not exposed")
        end)

        it("does not expose Session:take_talon", function()
            local view = session_view.new(fresh_auction_session())
            assert.error_matches(function()
                view:take_talon()
            end, "not exposed")
        end)

        it("does not expose Session:start_next_deal", function()
            local view = session_view.new(fresh_auction_session())
            assert.error_matches(function()
                view:start_next_deal()
            end, "not exposed")
        end)

        it("does not leak the underlying session via a field on the view", function()
            local view = session_view.new(fresh_auction_session())
            assert.error_matches(function()
                local _ = view._session
            end, "not exposed")
        end)
    end)
end)
