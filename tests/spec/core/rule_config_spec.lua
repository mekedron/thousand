local rule_config = require("core.rule_config")

-- A minimal valid table that mirrors the canonical schema. Specs that probe
-- a single missing/wrong field clone this and mutate one cell, so the rest
-- of the structure stays identical to the canonical baseline.
local function valid_table()
    return {
        schema_version = 1,
        cards = {
            point_values = {
                ["A"] = 11,
                ["10"] = 10,
                ["K"] = 4,
                ["Q"] = 3,
                ["J"] = 2,
                ["9"] = 0,
            },
            trick_rank_order = { "9", "J", "Q", "K", "10", "A" },
        },
        players = { count = 3 },
        talon = { size = 3 },
        bidding = {
            opening_min = 100,
            pre_talon_max = 120,
            increment_below_200 = 5,
            increment_from_200 = 10,
        },
        marriages = {
            values = { hearts = 100, diamonds = 80, clubs = 60, spades = 40 },
        },
        tricks = {
            must_follow = true,
            must_beat = true,
            must_trump = true,
            must_overtrump = true,
        },
        scoring = { round_to_nearest = 5 },
        barrel = {
            threshold = 880,
            deal_count = 3,
            fall_off_penalty = -120,
        },
        endgame = { target_score = 1000 },
    }
end

describe("core.rule_config", function()
    describe("SCHEMA_VERSION", function()
        it("is the integer 1", function()
            assert.are.equal(1, rule_config.SCHEMA_VERSION)
        end)
    end)

    describe("new()", function()
        it("returns a config that round-trips representative reads", function()
            local config = rule_config.new(valid_table())
            assert.are.equal(1, config.schema_version)
            assert.are.equal(11, config.cards.point_values["A"])
            assert.are.equal(100, config.bidding.opening_min)
            assert.are.equal(40, config.marriages.values.spades)
            assert.is_true(config.tricks.must_overtrump)
            assert.are.equal(-120, config.barrel.fall_off_penalty)
            assert.are.equal(1000, config.endgame.target_score)
        end)

        it("rejects a non-table argument", function()
            assert.has_error(function()
                rule_config.new(nil)
            end)
            assert.has_error(function()
                rule_config.new(42)
            end)
            assert.has_error(function()
                rule_config.new("not a table")
            end)
        end)

        it("rejects a missing schema_version", function()
            local t = valid_table()
            t.schema_version = nil
            assert.has_error(function()
                rule_config.new(t)
            end)
        end)

        it("rejects a non-integer schema_version", function()
            local t = valid_table()
            t.schema_version = "1"
            assert.has_error(function()
                rule_config.new(t)
            end)
        end)

        it("rejects an unknown schema_version", function()
            local t = valid_table()
            t.schema_version = 999
            assert.has_error(function()
                rule_config.new(t)
            end)
        end)

        it("rejects a missing required section", function()
            local sections = {
                "cards",
                "players",
                "talon",
                "bidding",
                "marriages",
                "tricks",
                "scoring",
                "barrel",
                "endgame",
            }
            for _, name in ipairs(sections) do
                local t = valid_table()
                t[name] = nil
                local ok = pcall(rule_config.new, t)
                assert.is_false(ok, "removing section " .. name .. " should raise")
            end
        end)

        it("rejects a wrong-typed primitive field", function()
            local t = valid_table()
            t.bidding.opening_min = "100"
            assert.has_error(function()
                rule_config.new(t)
            end)
        end)

        it("rejects a missing nested field", function()
            local t = valid_table()
            t.marriages.values.hearts = nil
            assert.has_error(function()
                rule_config.new(t)
            end)
        end)

        it("rejects a missing point value", function()
            local t = valid_table()
            t.cards.point_values["A"] = nil
            assert.has_error(function()
                rule_config.new(t)
            end)
        end)
    end)

    describe("frozen guard", function()
        it("rejects assignment to a top-level key", function()
            local config = rule_config.new(valid_table())
            assert.has_error(function()
                config.bidding = nil
            end)
        end)

        it("rejects assignment to a section field", function()
            local config = rule_config.new(valid_table())
            assert.has_error(function()
                config.bidding.opening_min = 1
            end)
        end)

        it("rejects assignment of a brand-new key", function()
            local config = rule_config.new(valid_table())
            assert.has_error(function()
                config.surprise = true
            end)
        end)
    end)

    describe("canonical_russian", function()
        local config = rule_config.canonical_russian

        it("is a frozen RuleConfig", function()
            assert.is_true(rule_config.is_rule_config(config))
        end)

        it("declares schema_version 1", function()
            assert.are.equal(1, config.schema_version)
        end)

        it("encodes the canonical card point values", function()
            assert.are.equal(11, config.cards.point_values["A"])
            assert.are.equal(10, config.cards.point_values["10"])
            assert.are.equal(4, config.cards.point_values["K"])
            assert.are.equal(3, config.cards.point_values["Q"])
            assert.are.equal(2, config.cards.point_values["J"])
            assert.are.equal(0, config.cards.point_values["9"])
        end)

        it("encodes the canonical trick rank order", function()
            local expected = { "9", "J", "Q", "K", "10", "A" }
            assert.are.equal(#expected, #config.cards.trick_rank_order)
            for i, rank in ipairs(expected) do
                assert.are.equal(rank, config.cards.trick_rank_order[i])
            end
        end)

        it("encodes the canonical Russian player count and talon size", function()
            assert.are.equal(3, config.players.count)
            assert.are.equal(3, config.talon.size)
        end)

        it("encodes the canonical bidding rules", function()
            assert.are.equal(100, config.bidding.opening_min)
            assert.are.equal(120, config.bidding.pre_talon_max)
            assert.are.equal(5, config.bidding.increment_below_200)
            assert.are.equal(10, config.bidding.increment_from_200)
        end)

        it("encodes the canonical marriage values", function()
            assert.are.equal(100, config.marriages.values.hearts)
            assert.are.equal(80, config.marriages.values.diamonds)
            assert.are.equal(60, config.marriages.values.clubs)
            assert.are.equal(40, config.marriages.values.spades)
        end)

        it("encodes the canonical strict trick rules", function()
            assert.is_true(config.tricks.must_follow)
            assert.is_true(config.tricks.must_beat)
            assert.is_true(config.tricks.must_trump)
            assert.is_true(config.tricks.must_overtrump)
        end)

        it("encodes the canonical scoring rounding", function()
            assert.are.equal(5, config.scoring.round_to_nearest)
        end)

        it("encodes the canonical barrel rules", function()
            assert.are.equal(880, config.barrel.threshold)
            assert.are.equal(3, config.barrel.deal_count)
            assert.are.equal(-120, config.barrel.fall_off_penalty)
        end)

        it("encodes the canonical target score", function()
            assert.are.equal(1000, config.endgame.target_score)
        end)
    end)

    describe("is_rule_config", function()
        it("returns true for canonical_russian", function()
            assert.is_true(rule_config.is_rule_config(rule_config.canonical_russian))
        end)

        it("returns true for any new()-built instance", function()
            assert.is_true(rule_config.is_rule_config(rule_config.new(valid_table())))
        end)

        it("returns false for a plain table", function()
            assert.is_false(rule_config.is_rule_config({}))
            assert.is_false(rule_config.is_rule_config(valid_table()))
        end)

        it("returns false for a non-table value", function()
            assert.is_false(rule_config.is_rule_config(nil))
            assert.is_false(rule_config.is_rule_config(42))
            assert.is_false(rule_config.is_rule_config("config"))
            assert.is_false(rule_config.is_rule_config(true))
        end)
    end)
end)
