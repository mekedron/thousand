-- Surface tripwire for the core engine.
--
-- Three of the per-module specs already include a "module shape" block
-- (scoring_spec, tricks_spec, marriages_spec); this file consolidates
-- the pattern across all nine `core/` modules so a future refactor
-- cannot silently drop a public function.
--
-- Anything documented in Phase 1.8 of docs/development/task-list.md as
-- "every public function in core/" is asserted here. SCHEMA_VERSION
-- values are pinned to 1 — a silent bump would break Phase 2's save
-- format and every downstream consumer.

local card = require("core.card")
local deck = require("core.deck")
local rule_config = require("core.rule_config")
local dealing = require("core.dealing")
local auction = require("core.auction")
local talon = require("core.talon")
local marriages = require("core.marriages")
local tricks = require("core.tricks")
local scoring = require("core.scoring")

describe("core public surface", function()
    it("core.card exposes its documented surface", function()
        assert.is_table(card.SUITS)
        assert.are.equal(4, #card.SUITS)
        assert.is_table(card.RANKS)
        assert.are.equal(6, #card.RANKS)
        assert.is_function(card.new)
        assert.is_function(card.equals)
        assert.is_function(card.tostring)
        assert.is_function(card.point_value)
        assert.is_function(card.trick_rank)
    end)

    it("core.deck exposes its documented surface", function()
        assert.is_function(deck.build)
        assert.is_function(deck.shuffle)
    end)

    it("core.rule_config exposes its documented surface", function()
        assert.is_number(rule_config.SCHEMA_VERSION)
        assert.are.equal(1, rule_config.SCHEMA_VERSION)
        assert.is_table(rule_config.canonical_russian)
        assert.is_function(rule_config.new)
        assert.is_function(rule_config.is_rule_config)
        assert.is_true(rule_config.is_rule_config(rule_config.canonical_russian))
    end)

    it("core.dealing exposes its documented surface", function()
        assert.is_function(dealing.deal)
    end)

    it("core.auction exposes its documented surface", function()
        assert.is_number(auction.SCHEMA_VERSION)
        assert.are.equal(1, auction.SCHEMA_VERSION)
        assert.is_function(auction.new)
        assert.is_function(auction.is_auction)
        assert.is_function(auction.bid)
        assert.is_function(auction.pass)
    end)

    it("core.talon exposes its documented surface", function()
        assert.is_number(talon.SCHEMA_VERSION)
        assert.are.equal(1, talon.SCHEMA_VERSION)
        assert.is_function(talon.new)
        assert.is_function(talon.is_talon)
        assert.is_function(talon.take)
        assert.is_function(talon.pass)
        assert.is_function(talon.raise)
        assert.is_function(talon.skip_raise)
    end)

    it("core.marriages exposes its documented surface", function()
        assert.is_number(marriages.SCHEMA_VERSION)
        assert.are.equal(1, marriages.SCHEMA_VERSION)
        assert.is_table(marriages.SUITS)
        assert.are.equal(4, #marriages.SUITS)
        assert.is_function(marriages.new)
        assert.is_function(marriages.is_marriages)
        assert.is_function(marriages.detect)
        assert.is_function(marriages.declare)
    end)

    it("core.tricks exposes its documented surface", function()
        assert.is_number(tricks.SCHEMA_VERSION)
        assert.are.equal(1, tricks.SCHEMA_VERSION)
        assert.is_function(tricks.new)
        assert.is_function(tricks.is_tricks)
        assert.is_function(tricks.set_trump)
        assert.is_function(tricks.legal_cards)
        assert.is_function(tricks.play)
    end)

    it("core.scoring exposes its documented surface", function()
        assert.is_number(scoring.SCHEMA_VERSION)
        assert.are.equal(1, scoring.SCHEMA_VERSION)
        assert.is_function(scoring.score_deal)
        assert.is_function(scoring.is_scoring)
        assert.is_function(scoring.advance_game)
        assert.is_function(scoring.is_game)
        assert.is_function(scoring.initial_barrel_state)
    end)
end)
