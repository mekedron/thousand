-- Phase 4.1: deterministic-legal chooser stubs used by the bot driver
-- until Phase 4.3 (baseline-legal play) replaces them per chooser.
-- Verifies (a) every chooser in the contract registry has a stub, (b)
-- each stub returns a descriptor whose kind is one of the registry's
-- declared returns and that the descriptor carries the fields the
-- corresponding Session mutator needs.

local stubs = require("app.bot.stubs")
local contract = require("app.bot.contract")
local Session = require("app.session")
local rule_config = require("core.rule_config")

local function fake_view(stubbed)
    local view = {}
    setmetatable(view, {
        __index = function(_, key)
            error("fake_view: '" .. tostring(key) .. "' not stubbed", 2)
        end,
    })
    for k, v in pairs(stubbed) do
        view[k] = v
    end
    return view
end

local function returns_set(name)
    for _, entry in ipairs(contract.CHOOSERS) do
        if entry.name == name then
            local s = {}
            for _, k in ipairs(entry.returns) do
                s[k] = true
            end
            return s
        end
    end
    error("unknown chooser: " .. name)
end

local function assert_kind_in_registry(name, kind)
    local set = returns_set(name)
    assert.is_true(set[kind], name .. " returned unexpected kind '" .. tostring(kind) .. "'")
end

describe("app.bot.stubs", function()
    it("provides a stub for every chooser in the contract registry", function()
        for _, entry in ipairs(contract.CHOOSERS) do
            assert.is_function(stubs[entry.name], "missing stub for chooser: " .. entry.name)
        end
    end)

    it("does not expose extra functions beyond the registry", function()
        local registered = {}
        for _, entry in ipairs(contract.CHOOSERS) do
            registered[entry.name] = true
        end
        for k, v in pairs(stubs) do
            if type(v) == "function" then
                assert.is_true(registered[k], "stubs exports an unregistered chooser: " .. k)
            end
        end
    end)

    describe("choose_bid", function()
        it("passes during the auction", function()
            local action = stubs.choose_bid(fake_view({}), 2)
            assert.are.equal("pass", action.kind)
            assert_kind_in_registry("choose_bid", action.kind)
        end)
    end)

    describe("choose_contra", function()
        it("skips the contra/redouble window", function()
            local action = stubs.choose_contra(fake_view({}), 2)
            assert.are.equal("skip_contra", action.kind)
            assert_kind_in_registry("choose_contra", action.kind)
        end)
    end)

    describe("choose_redeal", function()
        it("declines the redeal offer", function()
            local action = stubs.choose_redeal(fake_view({}), 2)
            assert.are.equal("decline_redeal", action.kind)
            assert_kind_in_registry("choose_redeal", action.kind)
        end)
    end)

    describe("choose_bad_talon_redeal", function()
        it("declines the bad-talon redeal", function()
            local action = stubs.choose_bad_talon_redeal(fake_view({}), 2)
            assert.are.equal("decline_bad_talon_redeal", action.kind)
            assert_kind_in_registry("choose_bad_talon_redeal", action.kind)
        end)
    end)

    describe("choose_rebuy", function()
        it("declines the rebuy claim", function()
            local action = stubs.choose_rebuy(fake_view({}), 2)
            assert.are.equal("decline_rebuy", action.kind)
            assert_kind_in_registry("choose_rebuy", action.kind)
        end)
    end)

    describe("choose_forced_bid_concession", function()
        it("declines the forced-bid concession", function()
            local action = stubs.choose_forced_bid_concession(fake_view({}), 2)
            assert.are.equal("decline_forced_bid", action.kind)
            assert_kind_in_registry("choose_forced_bid_concession", action.kind)
        end)
    end)

    describe("choose_write_off", function()
        it("accepts play (does not write off)", function()
            local action = stubs.choose_write_off(fake_view({}), 2)
            assert.are.equal("accept_play", action.kind)
            assert_kind_in_registry("choose_write_off", action.kind)
        end)
    end)

    describe("choose_marriage", function()
        it("skips the in-trick marriage announcement", function()
            local action = stubs.choose_marriage(fake_view({}), 2)
            assert.are.equal("skip_announce_marriage", action.kind)
        end)
    end)

    describe("choose_pre_first_trick_marriage", function()
        it("skips the pre-first-trick marriage announcement", function()
            local action = stubs.choose_pre_first_trick_marriage(fake_view({}), 2)
            assert.are.equal("skip_announce_marriage", action.kind)
            assert_kind_in_registry("choose_pre_first_trick_marriage", action.kind)
        end)
    end)

    describe("choose_card", function()
        it("plays the first legal card", function()
            local card = { suit = "hearts", rank = "A" }
            local view = fake_view({
                legal_cards = function(_, seat)
                    assert.are.equal(2, seat)
                    return { card }
                end,
            })
            local action = stubs.choose_card(view, 2)
            assert.are.equal("play", action.kind)
            assert.are.equal(card, action.card)
            assert_kind_in_registry("choose_card", action.kind)
        end)
    end)

    describe("choose_talon_action", function()
        it("takes the talon", function()
            local action = stubs.choose_talon_action(fake_view({}), 2)
            assert.are.equal("take_talon", action.kind)
            assert_kind_in_registry("choose_talon_action", action.kind)
        end)
    end)

    describe("choose_raise", function()
        it("skips the raise window", function()
            local action = stubs.choose_raise(fake_view({}), 2)
            assert.are.equal("skip_raise", action.kind)
            assert_kind_in_registry("choose_raise", action.kind)
        end)
    end)

    describe("choose_next_deal", function()
        it("starts the next deal", function()
            local action = stubs.choose_next_deal(fake_view({}), 2)
            assert.are.equal("start_next_deal", action.kind)
            assert_kind_in_registry("choose_next_deal", action.kind)
        end)
    end)

    describe("choose_talon_pass", function()
        local card = { suit = "hearts", rank = "A" }

        it("passes the first hand card to the first opponent (regular flow)", function()
            local view = fake_view({
                talon_substate = function()
                    return "pass"
                end,
                hands = function()
                    return { {}, { card }, {} }
                end,
                config = function()
                    return rule_config.canonical_russian
                end,
            })
            local action = stubs.choose_talon_pass(view, 2)
            assert.are.equal("pass_talon", action.kind)
            assert.are.equal(card, action.card)
            assert.is_true(action.target == 1 or action.target == 3)
            assert.are_not.equal(2, action.target)
            assert_kind_in_registry("choose_talon_pass", action.kind)
        end)

        it("uses pass_polish_talon under Polish distribution", function()
            local view = fake_view({
                talon_substate = function()
                    return "polish_pass"
                end,
                hands = function()
                    return { {}, { card }, {} }
                end,
                config = function()
                    return rule_config.builtins.polish
                end,
            })
            local action = stubs.choose_talon_pass(view, 2)
            assert.are.equal("pass_polish_talon", action.kind)
            assert.are.equal(1, action.talon_index)
            assert.is_true(action.target == 1 or action.target == 3)
            assert_kind_in_registry("choose_talon_pass", action.kind)
        end)

        it("uses discard_talon at the awaiting_discard sub-state", function()
            local view = fake_view({
                talon_substate = function()
                    return "discard"
                end,
                hands = function()
                    return { {}, { card }, {} }
                end,
                config = function()
                    return rule_config.canonical_russian
                end,
            })
            local action = stubs.choose_talon_pass(view, 2)
            assert.are.equal("discard_talon", action.kind)
            assert.are.equal(card, action.card)
            assert_kind_in_registry("choose_talon_pass", action.kind)
        end)
    end)

    describe("end-to-end legality", function()
        it("choose_card returns a card from view:legal_cards()", function()
            local s = Session.new({ seed = 42, dealer = 1 })
            assert(s:bid(2, 100).ok)
            assert(s:pass(3).ok)
            assert(s:pass(1).ok)
            assert(s:take_talon().ok)
            if s:current_phase() == "awaiting_write_off_decision" then
                assert(s:accept_play().ok)
            end
            local hand = s:hands()[2]
            assert(s:pass_talon(1, hand[1]).ok)
            hand = s:hands()[2]
            assert(s:pass_talon(3, hand[1]).ok)
            assert(s:skip_raise().ok)
            assert.are.equal("tricks", s:current_phase())

            local seat = s:current_turn()
            local view = contract.make_view(s)
            local action = stubs.choose_card(view, seat)
            assert.are.equal("play", action.kind)
            assert(s:play(seat, action.card).ok)
        end)
    end)
end)
