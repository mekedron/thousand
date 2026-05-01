-- Unit coverage for the table view-model. Pure Lua — no love.* — so the
-- spec runs under plain busted.

local view_model = require("app.table_view_model")
local Session = require("app.session")
local rule_config = require("core.rule_config")

local config = rule_config.canonical_russian

describe("app.table_view_model", function()
    describe("from_session — fresh session", function()
        local view

        before_each(function()
            local s = Session.new({ seed = 42, dealer = 1 })
            view = view_model.from_session(s)
        end)

        it("derives the auction phase with the forehand on turn", function()
            assert.are.equal("auction", view.phase)
            assert.are.equal(2, view.turn_player)
            assert.are.equal(1, view.dealer)
        end)

        it("flags seat 1 as self and seats 2 and 3 as other", function()
            assert.are.equal("self", view.hands[1].perspective)
            assert.are.equal("other", view.hands[2].perspective)
            assert.are.equal("other", view.hands[3].perspective)
        end)

        it("annotates dealer and turn flags on the hands", function()
            assert.is_true(view.hands[1].is_dealer)
            assert.is_false(view.hands[2].is_dealer)
            assert.is_false(view.hands[1].is_turn)
            assert.is_true(view.hands[2].is_turn)
        end)

        it("renders the talon face-down with three cards in the auction", function()
            assert.is_true(view.talon.face_down)
            assert.are.equal(3, view.talon.count)
        end)

        it("reports no bid, no leader, no trump, no winner pre-action", function()
            assert.is_nil(view.current_bid)
            assert.is_nil(view.leader)
            assert.is_nil(view.trump)
            assert.is_nil(view.winner)
            assert.is_nil(view.final_scores)
        end)

        it("zeros the scoreboard with all seats off the barrel", function()
            for _, entry in ipairs(view.scoreboard) do
                assert.are.equal(0, entry.total)
                assert.is_false(entry.barrel.on_barrel)
                assert.is_false(entry.is_winner)
            end
        end)

        it("includes the player count for downstream layout choices", function()
            assert.are.equal(3, view.player_count)
        end)
    end)

    describe("from_session — finished session", function()
        local view

        before_each(function()
            local s = Session.from_state({
                config = config,
                dealer = 2,
                running_totals = { 1010, 720, 540 },
                winner = 1,
            })
            view = view_model.from_session(s)
        end)

        it("reports the done phase with no actor on turn", function()
            assert.are.equal("done", view.phase)
            assert.is_nil(view.turn_player)
        end)

        it("populates winner and final scores", function()
            assert.are.equal(1, view.winner)
            assert.are.same({ 1010, 720, 540 }, view.final_scores)
        end)

        it("flags the winning seat in the scoreboard", function()
            assert.is_true(view.scoreboard[1].is_winner)
            assert.is_false(view.scoreboard[2].is_winner)
            assert.is_false(view.scoreboard[3].is_winner)
        end)
    end)

    it("never returns the engine's hand list directly so the renderer cannot mutate it", function()
        local s = Session.new({ seed = 1 })
        local engine_hands = s:hands()
        local view = view_model.from_session(s)
        view.hands[1].cards[1] = { suit = "spades", rank = "A" } -- bogus tamper
        -- Engine's list still untouched.
        assert.are_not.equal(view.hands[1].cards, engine_hands[1])
    end)
end)
