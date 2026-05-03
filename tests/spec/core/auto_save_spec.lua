-- Unit coverage for the auto-save serializer. Pure-Lua round-trip
-- tests at every Phase 2 phase: auction, talon, tricks (with a played
-- card and a declared marriage / set trump), and deal_done after a
-- full eight-trick deal scores.

local auto_save = require("core.auto_save")
local Session = require("app.session")
local rule_config = require("core.rule_config")
local auction_module = require("core.auction")
local talon_module = require("core.talon")
local marriages_module = require("core.marriages")
local tricks_module = require("core.tricks")
local json = require("app.json")

local SEED_NO_MARRIAGE = 42
local SEED_SPADES_MARRIAGE = 1

local function find_safe_pass(hand, marriage_suit)
    for _, c in ipairs(hand) do
        if not (c.suit == marriage_suit and (c.rank == "K" or c.rank == "Q")) then
            return c
        end
    end
    error("no safe pass card available")
end

-- The auto-save round-trip exercises a marriage declaration at the
-- start of the tricks phase. The canonical
-- `marriages.trick_required = "on"` rule would gate it; the spec
-- drives the deal under a config with the gate off (the gate behaviour
-- itself is covered by tests/spec/core/marriages_spec.lua).
local function trickless_canonical()
    local rc = require("core.rule_config")
    local jsmod = require("app.json")
    local blob = jsmod.decode(rc.to_json(rc.canonical_russian))
    blob.marriages.trick_required = "off"
    return rc.new(blob)
end

local function drive_to_talon(seed)
    local s = Session.new({ seed = seed, dealer = 1, config = trickless_canonical() })
    assert(s:bid(2, 100).ok)
    assert(s:pass(3).ok)
    assert(s:pass(1).ok)
    return s
end

local function drive_to_tricks(seed, marriage_suit)
    local s = drive_to_talon(seed)
    assert(s:take_talon().ok)
    -- Phase 3.9: trickless_canonical inherits write_off = "on" from
    -- canonical_russian, so the take opens the pre-tricks prompt. Decline
    -- it to flow into the pass step.
    if s:current_phase() == "awaiting_write_off_decision" then
        assert(s:accept_play().ok)
    end
    local hand = s:hands()[2]
    assert(s:pass_talon(1, find_safe_pass(hand, marriage_suit)).ok)
    hand = s:hands()[2]
    assert(s:pass_talon(3, find_safe_pass(hand, marriage_suit)).ok)
    assert(s:skip_raise().ok)
    return s
end

local function drive_full_deal(seed)
    local s = drive_to_tricks(seed, nil)
    while s:current_phase() == "tricks" do
        local p = s:current_turn()
        local legal = s:legal_cards(p)
        assert(#legal > 0)
        assert(s:play(p, legal[1]).ok)
    end
    return s
end

-- Round-trip helper: serialize, JSON-encode, JSON-decode, deserialize.
-- Catches both pure Lua issues and JSON encoding subtleties (eg cards
-- losing data through the frozen-proxy + json round trip).
local function round_trip(session)
    local blob = auto_save.serialize(session)
    assert.is_table(blob)
    local encoded = json.encode(blob)
    assert.is_string(encoded)
    local decoded, err = json.decode(encoded)
    assert.is_nil(err)
    assert.is_table(decoded)
    return auto_save.deserialize(decoded)
end

describe("core.auto_save", function()
    describe("schema metadata", function()
        it("exposes its schema version", function()
            assert.are.equal(2, auto_save.schema_version())
        end)

        it("exposes its template name", function()
            assert.are.equal("canonical_russian", auto_save.template_name())
        end)
    end)

    describe("serialize", function()
        it("returns nil for non-table inputs", function()
            assert.is_nil(auto_save.serialize(nil))
            assert.is_nil(auto_save.serialize(42))
            assert.is_nil(auto_save.serialize("session"))
        end)

        it("stamps the current schemaVersion and templateName", function()
            local s = Session.new({ seed = 7, dealer = 1 })
            local blob = auto_save.serialize(s)
            assert.are.equal(2, blob.schemaVersion)
            assert.are.equal("canonical_russian", blob.templateName)
        end)

        it("strips the engine config field from each engine state", function()
            local s = drive_to_talon(SEED_NO_MARRIAGE)
            local blob = auto_save.serialize(s)
            assert.is_nil(blob.auction.config)
            assert.is_nil(blob.talon.config)
            assert.is_nil(blob.marriages.config)
        end)

        it("materialises frozen cards into plain { suit, rank } tables", function()
            local s = Session.new({ seed = 3, dealer = 1 })
            local blob = auto_save.serialize(s)
            local first = blob.hands[1][1]
            assert.are.equal("table", type(first))
            assert.is_string(first.suit)
            assert.is_string(first.rank)
            -- Plain table — no metatable redirection.
            assert.is_nil(getmetatable(first))
        end)
    end)

    describe("deserialize", function()
        it("returns nil for non-table input", function()
            assert.is_nil(auto_save.deserialize(nil))
            assert.is_nil(auto_save.deserialize(42))
            assert.is_nil(auto_save.deserialize("blob"))
        end)

        it("returns nil when schemaVersion is missing", function()
            assert.is_nil(auto_save.deserialize({ templateName = "canonical_russian" }))
        end)

        it("returns nil when schemaVersion is wrong", function()
            assert.is_nil(auto_save.deserialize({
                schemaVersion = 99,
                templateName = "canonical_russian",
            }))
        end)

        it("returns nil for an unknown templateName", function()
            assert.is_nil(auto_save.deserialize({
                schemaVersion = 2,
                templateName = "made_up_template",
            }))
        end)

        it("re-attaches the canonical config to the top-level state", function()
            local s = Session.new({ seed = 5, dealer = 2 })
            local restored = round_trip(s)
            assert.are.equal(rule_config.canonical_russian, restored.config)
        end)

        it("re-tags the auction state so is_auction succeeds", function()
            local s = Session.new({ seed = 9, dealer = 1 })
            local restored = round_trip(s)
            assert.is_true(auction_module.is_auction(restored.auction))
        end)
    end)

    describe("round-trip via Session.from_state", function()
        it("preserves the auction phase", function()
            local original = Session.new({ seed = 7, dealer = 1 })
            local restored = Session.from_state(round_trip(original))
            assert.are.equal("auction", restored:current_phase())
            assert.are.equal(original:current_turn(), restored:current_turn())
            assert.are.equal(original:dealer(), restored:dealer())
            assert.are.same(original:running_totals(), restored:running_totals())
        end)

        it("preserves a mid-auction state with a recorded bid", function()
            local s = Session.new({ seed = 7, dealer = 1 })
            assert(s:bid(2, 100).ok)
            local restored = Session.from_state(round_trip(s))
            assert.are.equal("auction", restored:current_phase())
            assert.are.equal(100, restored:current_bid())
            assert.are.equal(2, restored:current_leader())
            assert.are.equal(s:current_turn(), restored:current_turn())
        end)

        it("preserves the talon phase mid-pass", function()
            local s = drive_to_talon(SEED_NO_MARRIAGE)
            assert(s:take_talon().ok)
            -- Phase 3.9: clear the pre-tricks write-off prompt before
            -- the snapshot so this test still asserts the talon phase
            -- round-trips. The new prompt has its own coverage below.
            if s:current_phase() == "awaiting_write_off_decision" then
                assert(s:accept_play().ok)
            end
            local restored = Session.from_state(round_trip(s))
            assert.are.equal("talon", restored:current_phase())
            assert.are.equal(s:current_bid(), restored:current_bid())
            assert.are.equal(s:current_leader(), restored:current_leader())
            -- Restored state must accept the next mutator (talon pass) — the
            -- engine call would refuse if we'd lost the talon's metatable.
            assert.is_true(talon_module.is_talon(restored._talon))
            local hand = restored:hands()[2]
            local r = restored:pass_talon(1, hand[1])
            assert.is_true(r.ok)
        end)

        it("preserves the awaiting_write_off_decision phase", function()
            local s = drive_to_talon(SEED_NO_MARRIAGE)
            assert(s:take_talon().ok)
            assert.are.equal("awaiting_write_off_decision", s:current_phase())
            local restored = Session.from_state(round_trip(s))
            assert.are.equal("awaiting_write_off_decision", restored:current_phase())
            local offer = restored:write_off_offer_state()
            assert.is_table(offer)
            assert.are.equal(s:write_off_offer_state().declarer, offer.declarer)
            assert.are.equal(s:write_off_offer_state().bid, offer.bid)
            -- Round-tripped session must still accept either branch.
            assert.is_true(restored:accept_play().ok)
            assert.are.equal("talon", restored:current_phase())
        end)

        it("preserves an in-progress tricks state with a played card", function()
            local s = drive_to_tricks(SEED_NO_MARRIAGE, nil)
            local p = s:current_turn()
            local legal = s:legal_cards(p)
            assert(s:play(p, legal[1]).ok)
            local restored = Session.from_state(round_trip(s))
            assert.are.equal("tricks", restored:current_phase())
            local trick = restored:current_trick()
            assert.is_table(trick)
            assert.are.equal(1, #trick.plays)
            assert.are.equal(legal[1].suit, trick.plays[1].card.suit)
            assert.are.equal(legal[1].rank, trick.plays[1].card.rank)
            -- Engine still recognises the rebuilt tricks state.
            assert.is_true(tricks_module.is_tricks(restored._tricks))
        end)

        it("preserves a declared marriage and trump suit", function()
            local s = drive_to_tricks(SEED_SPADES_MARRIAGE, "spades")
            -- Player 2 leads, declares spades marriage on the first trick lead.
            local lead = s:current_turn()
            assert(s:declare_marriage(lead, "spades").ok)
            -- Play one trick to flip the trump.
            local hand = s:hands()[lead]
            local king_spades
            for _, c in ipairs(hand) do
                if c.suit == "spades" and c.rank == "K" then
                    king_spades = c
                    break
                end
            end
            assert.is_table(king_spades)
            assert(s:play(lead, king_spades).ok)
            -- Two more plays to close the trick and apply trump.
            while s:current_trick() and #s:current_trick().plays > 0 do
                local p = s:current_turn()
                local legal = s:legal_cards(p)
                assert(s:play(p, legal[1]).ok)
                if not s:current_trick() then
                    break
                end
            end

            local restored = Session.from_state(round_trip(s))
            assert.are.equal("spades", restored:trump())
            assert.is_true(marriages_module.is_marriages(restored._marriages))
            assert.are.equal(1, #restored._marriages.declarations)
            assert.are.equal("spades", restored._marriages.declarations[1].suit)
        end)

        it("preserves running totals after a full deal scores", function()
            local s = drive_full_deal(SEED_NO_MARRIAGE)
            assert.are.equal("deal_done", s:current_phase())
            local restored = Session.from_state(round_trip(s))
            assert.are.equal("deal_done", restored:current_phase())
            assert.are.same(s:running_totals(), restored:running_totals())
            local rd = restored:deal_done()
            local sd = s:deal_done()
            assert.are.equal(sd.reason, rd.reason)
            assert.are.equal(sd.declarer, rd.declarer)
            assert.are.same(sd.deal_scores, rd.deal_scores)
        end)

        it("preserves write_off_counts across a round-trip", function()
            local s = Session.new({ seed = 7 })
            -- Test-only: prime the counter directly. The action path is
            -- exercised in tests/spec/app/session_write_off_spec.
            s._write_off_counts = { 1, 2, 0 }
            local restored = Session.from_state(round_trip(s))
            assert.are.same({ 1, 2, 0 }, restored:write_off_counts())
        end)

        it("defaults write_off_counts to zeros when missing from the blob", function()
            -- Simulates a save written before the field was added.
            local s = Session.new({ seed = 7 })
            local blob = auto_save.serialize(s)
            blob.write_off_counts = nil
            local encoded = json.encode(blob)
            local decoded = json.decode(encoded)
            local restored = Session.from_state(auto_save.deserialize(decoded))
            assert.are.same({ 0, 0, 0 }, restored:write_off_counts())
        end)

        it("preserves no_win_streak_counts across a round-trip", function()
            local s = Session.new({ seed = 7 })
            s._no_win_streak_counts = { 0, 1, 2 }
            local restored = Session.from_state(round_trip(s))
            assert.are.same({ 0, 1, 2 }, restored:no_win_streak_counts())
        end)

        it("defaults no_win_streak_counts to zeros when missing from the blob", function()
            local s = Session.new({ seed = 7 })
            local blob = auto_save.serialize(s)
            blob.no_win_streak_counts = nil
            local encoded = json.encode(blob)
            local decoded = json.decode(encoded)
            local restored = Session.from_state(auto_save.deserialize(decoded))
            assert.are.same({ 0, 0, 0 }, restored:no_win_streak_counts())
        end)

        it("preserves barrel_fall_counts across a round-trip", function()
            local s = Session.new({ seed = 7 })
            s._barrel_fall_counts = { 1, 0, 2 }
            local restored = Session.from_state(round_trip(s))
            assert.are.same({ 1, 0, 2 }, restored:barrel_fall_counts())
        end)

        it("defaults barrel_fall_counts to zeros when missing from the blob", function()
            local s = Session.new({ seed = 7 })
            local blob = auto_save.serialize(s)
            blob.barrel_fall_counts = nil
            local encoded = json.encode(blob)
            local decoded = json.decode(encoded)
            local restored = Session.from_state(auto_save.deserialize(decoded))
            assert.are.same({ 0, 0, 0 }, restored:barrel_fall_counts())
        end)

        -- Phase 3.8 cut-deck ritual: an in-progress cut phase must
        -- survive serialize / decode / deserialize so a player can
        -- suspend mid-ritual and resume without losing their place.
        it("preserves an in-progress cut_phase across a round-trip", function()
            local s = Session.new({ seed = 7 })
            s._cut_phase = {
                active_cutter = 2,
                bad_cut_count = 1,
                bottom_card = require("core.card").new("hearts", "J"),
            }
            s._cut_deck_log = {
                {
                    kind = "bad_cut",
                    seat = 3,
                    dealer = 1,
                    bad_cut_count = 1,
                    next_cutter = 2,
                },
            }
            local restored = Session.from_state(round_trip(s))
            local cut = restored:cut_phase()
            assert.is_not_nil(cut)
            assert.are.equal(2, cut.active_cutter)
            assert.are.equal(1, cut.bad_cut_count)
            assert.are.equal("hearts", cut.bottom_card.suit)
            assert.are.equal("J", cut.bottom_card.rank)
            assert.are.equal(1, #restored:cut_deck_log())
            assert.are.equal("bad_cut", restored:cut_deck_log()[1].kind)
        end)

        it("defaults cut_phase to nil and cut_deck_log to {} when missing", function()
            local s = Session.new({ seed = 7 })
            local blob = auto_save.serialize(s)
            blob.cut_phase = nil
            blob.cut_deck_log = nil
            local encoded = json.encode(blob)
            local decoded = json.decode(encoded)
            local restored = Session.from_state(auto_save.deserialize(decoded))
            assert.is_nil(restored:cut_phase())
            assert.are.same({}, restored:cut_deck_log())
        end)
    end)
end)
