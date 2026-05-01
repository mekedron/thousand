-- Unit coverage for the in-memory session. Pure Lua — no love.* — so the
-- spec runs under plain busted with the project's standard config.

local Session = require("app.session")
local rule_config = require("core.rule_config")

local config = rule_config.canonical_russian

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
end)
