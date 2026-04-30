local card = require("core.card")
local rule_config = require("core.rule_config")

local config = rule_config.canonical_russian

describe("core.card", function()
    describe("SUITS", function()
        it("lists the four canonical suits in the documented order", function()
            local expected = { "spades", "clubs", "diamonds", "hearts" }
            assert.are.equal(#expected, #card.SUITS)
            for i, suit in ipairs(expected) do
                assert.are.equal(suit, card.SUITS[i])
            end
        end)
    end)

    describe("RANKS", function()
        it("lists the six canonical ranks in trick-rank order", function()
            local expected = { "9", "J", "Q", "K", "10", "A" }
            assert.are.equal(#expected, #card.RANKS)
            for i, rank in ipairs(expected) do
                assert.are.equal(rank, card.RANKS[i])
            end
        end)
    end)

    describe("new()", function()
        it("constructs a card with the requested suit and rank", function()
            local c = card.new("hearts", "A")
            assert.are.equal("hearts", c.suit)
            assert.are.equal("A", c.rank)
        end)

        it("accepts every legal suit and rank combination", function()
            for _, suit in ipairs(card.SUITS) do
                for _, rank in ipairs(card.RANKS) do
                    local c = card.new(suit, rank)
                    assert.are.equal(suit, c.suit)
                    assert.are.equal(rank, c.rank)
                end
            end
        end)

        it("rejects an unknown suit", function()
            assert.has_error(function()
                card.new("stars", "A")
            end)
        end)

        it("rejects an unknown rank", function()
            assert.has_error(function()
                card.new("hearts", "8")
            end)
        end)

        it("rejects a non-string suit", function()
            assert.has_error(function()
                card.new(nil, "A")
            end)
            assert.has_error(function()
                card.new(42, "A")
            end)
        end)

        it("rejects a non-string rank", function()
            assert.has_error(function()
                card.new("hearts", nil)
            end)
            assert.has_error(function()
                card.new("hearts", 10)
            end)
        end)

        it("returns a frozen card", function()
            local c = card.new("hearts", "A")
            assert.has_error(function()
                c.suit = "spades"
            end)
            assert.has_error(function()
                c.rank = "K"
            end)
            assert.has_error(function()
                c.extra = true
            end)
        end)
    end)

    describe("equals()", function()
        it("returns true for cards with the same suit and rank", function()
            assert.is_true(card.equals(card.new("hearts", "A"), card.new("hearts", "A")))
        end)

        it("returns false for cards with different suits", function()
            assert.is_false(card.equals(card.new("hearts", "A"), card.new("spades", "A")))
        end)

        it("returns false for cards with different ranks", function()
            assert.is_false(card.equals(card.new("hearts", "A"), card.new("hearts", "K")))
        end)
    end)

    describe("tostring()", function()
        it("formats a card with rank and Unicode suit glyph", function()
            assert.are.equal("A♥", card.tostring(card.new("hearts", "A")))
            assert.are.equal("10♠", card.tostring(card.new("spades", "10")))
            assert.are.equal("9♣", card.tostring(card.new("clubs", "9")))
            assert.are.equal("Q♦", card.tostring(card.new("diamonds", "Q")))
        end)
    end)

    describe("point_value()", function()
        it("returns the documented value for every rank", function()
            local expected = {
                ["A"] = 11,
                ["10"] = 10,
                ["K"] = 4,
                ["Q"] = 3,
                ["J"] = 2,
                ["9"] = 0,
            }
            for rank, value in pairs(expected) do
                assert.are.equal(value, card.point_value(rank, config))
                assert.are.equal(value, card.point_value(card.new("hearts", rank), config))
            end
        end)

        it("rejects an unknown rank", function()
            assert.has_error(function()
                card.point_value("8", config)
            end)
        end)

        it("rejects a non-RuleConfig second argument", function()
            assert.has_error(function()
                card.point_value("A", {})
            end)
            assert.has_error(function()
                card.point_value("A", nil)
            end)
        end)
    end)

    describe("trick_rank()", function()
        it("returns 1..6 in canonical order under the canonical config", function()
            local expected = {
                ["9"] = 1,
                ["J"] = 2,
                ["Q"] = 3,
                ["K"] = 4,
                ["10"] = 5,
                ["A"] = 6,
            }
            for rank, index in pairs(expected) do
                assert.are.equal(index, card.trick_rank(rank, config))
                assert.are.equal(index, card.trick_rank(card.new("clubs", rank), config))
            end
        end)

        it("is strictly monotonic across RANKS", function()
            local previous = 0
            for _, rank in ipairs(card.RANKS) do
                local index = card.trick_rank(rank, config)
                assert.is_true(index > previous)
                previous = index
            end
        end)

        it("rejects an unknown rank", function()
            assert.has_error(function()
                card.trick_rank("8", config)
            end)
        end)

        it("rejects a non-RuleConfig second argument", function()
            assert.has_error(function()
                card.trick_rank("A", {})
            end)
            assert.has_error(function()
                card.trick_rank("A", nil)
            end)
        end)
    end)
end)
