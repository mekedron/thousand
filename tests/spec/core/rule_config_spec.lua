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
        players = {
            count = 3,
            partnership_mode = "none",
            four_player_config = "dealer_plays_no_talon",
            two_player_config = "closed_talon_draw_stock",
        },
        dealing = {
            four_nine_redeal = "off",
            three_nine_redeal = "off",
            four_jack_redeal = "off",
            weak_hand_redeal = "off",
            misdeal_handling = "standard",
            all_pass_handling = "redeal",
        },
        talon = { size = 3 },
        bidding = {
            opening_min = 100,
            pre_talon_max = 120,
            increment_threshold = 200,
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
                "dealing",
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

        it("encodes the canonical players-section seating defaults", function()
            assert.are.equal("none", config.players.partnership_mode)
            assert.are.equal("dealer_plays_no_talon", config.players.four_player_config)
            assert.are.equal("closed_talon_draw_stock", config.players.two_player_config)
        end)

        it("encodes the canonical dealing-section defaults", function()
            assert.are.equal("off", config.dealing.four_nine_redeal)
            assert.are.equal("off", config.dealing.three_nine_redeal)
            assert.are.equal("off", config.dealing.four_jack_redeal)
            assert.are.equal("off", config.dealing.weak_hand_redeal)
            assert.are.equal("standard", config.dealing.misdeal_handling)
            assert.are.equal("redeal", config.dealing.all_pass_handling)
        end)

        it("encodes the canonical bidding rules", function()
            assert.are.equal(100, config.bidding.opening_min)
            assert.are.equal(120, config.bidding.pre_talon_max)
            assert.are.equal(200, config.bidding.increment_threshold)
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

    describe("schema_for", function()
        it("returns a leaf descriptor for a known field path", function()
            local d = rule_config.schema_for("bidding.opening_min")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("number", d.lua_type)
            assert.are.equal(100, d.default)
            assert.are.equal("implemented", d.status)
        end)

        it("returns a leaf descriptor for schema_version", function()
            local d = rule_config.schema_for("schema_version")
            assert.are.equal("leaf", d.kind)
            assert.are.equal(1, d.default)
            assert.are.equal("implemented", d.status)
        end)

        it("returns a section descriptor at the section level", function()
            local d = rule_config.schema_for("bidding")
            assert.are.equal("section", d.kind)
            assert.is_true(#d.fields > 0)
        end)

        it("returns nil for unknown or malformed paths", function()
            assert.is_nil(rule_config.schema_for("nope"))
            assert.is_nil(rule_config.schema_for("bidding.nope"))
            assert.is_nil(rule_config.schema_for("bidding.opening_min.deeper"))
            assert.is_nil(rule_config.schema_for(""))
            assert.is_nil(rule_config.schema_for(42))
        end)

        it("exposes lua_type, default, and a known status on every catalogued leaf", function()
            local catalogue = {
                { "cards", { "trick_rank_order", "point_values" } },
                {
                    "players",
                    {
                        "count",
                        "partnership_mode",
                        "four_player_config",
                        "two_player_config",
                    },
                },
                {
                    "dealing",
                    {
                        "four_nine_redeal",
                        "three_nine_redeal",
                        "four_jack_redeal",
                        "weak_hand_redeal",
                        "misdeal_handling",
                        "all_pass_handling",
                    },
                },
                { "talon", { "size" } },
                {
                    "bidding",
                    {
                        "opening_min",
                        "pre_talon_max",
                        "increment_threshold",
                        "increment_below_200",
                        "increment_from_200",
                    },
                },
                { "marriages", { "values" } },
                {
                    "tricks",
                    { "must_follow", "must_beat", "must_trump", "must_overtrump" },
                },
                { "scoring", { "round_to_nearest" } },
                { "barrel", { "threshold", "deal_count", "fall_off_penalty" } },
                { "endgame", { "target_score" } },
            }
            local known_status = {
                implemented = true,
                selectable = true,
                deferred = true,
            }
            for _, entry in ipairs(catalogue) do
                local section, fields = entry[1], entry[2]
                for _, name in ipairs(fields) do
                    local path = section .. "." .. name
                    local d = rule_config.schema_for(path)
                    assert.is_not_nil(d, path .. " has no descriptor")
                    assert.is_truthy(d.kind, path .. " missing kind")
                    assert.is_not_nil(d.default, path .. " missing default")
                    assert.is_true(
                        known_status[d.status] == true,
                        path .. " has unknown status: " .. tostring(d.status)
                    )
                end
            end
        end)
    end)

    describe("try_new", function()
        it("returns ok=true with a frozen config on the canonical input", function()
            local res = rule_config.try_new(valid_table())
            assert.is_true(res.ok)
            assert.is_true(rule_config.is_rule_config(res.config))
            assert.are.equal(100, res.config.bidding.opening_min)
        end)

        it("returns not_a_table for non-table input", function()
            local res = rule_config.try_new("not a table")
            assert.is_false(res.ok)
            assert.are.equal("not_a_table", res.error.code)
            assert.are.equal("string", res.error.actual)
        end)

        it("returns missing_field when a whole section is missing", function()
            local t = valid_table()
            t.players = nil
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("missing_field", res.error.code)
            assert.are.equal("players", res.error.path)
        end)

        it("returns missing_field when a leaf field is missing", function()
            local t = valid_table()
            t.bidding.opening_min = nil
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("missing_field", res.error.code)
            assert.are.equal("bidding.opening_min", res.error.path)
        end)

        it("returns missing_field when a marriage value is missing", function()
            local t = valid_table()
            t.marriages.values.hearts = nil
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("missing_field", res.error.code)
            assert.are.equal("marriages.values.hearts", res.error.path)
        end)

        it("returns type_mismatch for wrong-typed leaves", function()
            local t = valid_table()
            t.bidding.opening_min = "100"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("type_mismatch", res.error.code)
            assert.are.equal("bidding.opening_min", res.error.path)
            assert.are.equal("number", res.error.expected)
            assert.are.equal("string", res.error.actual)
        end)

        it("returns value_not_allowed when a leaf is outside the allowed set", function()
            local t = valid_table()
            t.scoring.round_to_nearest = 1
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("value_not_allowed", res.error.code)
            assert.are.equal("scoring.round_to_nearest", res.error.path)
            assert.are.equal(1, res.error.value)
        end)

        it("returns value_out_of_range when a leaf is below min", function()
            local t = valid_table()
            t.bidding.opening_min = 5
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("value_out_of_range", res.error.code)
            assert.are.equal("bidding.opening_min", res.error.path)
            assert.are.equal(5, res.error.value)
        end)
    end)

    describe("unknown_field rejection", function()
        it("rejects an unknown top-level key", function()
            local t = valid_table()
            t.bonus = true
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("unknown_field", res.error.code)
            assert.are.equal("bonus", res.error.path)
        end)

        it("rejects an unknown section-level key", function()
            local t = valid_table()
            t.bidding.surprise = 1
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("unknown_field", res.error.code)
            assert.are.equal("bidding.surprise", res.error.path)
        end)
    end)

    describe("schema_version handling", function()
        for _, version in ipairs({ 0, 2, "wrong" }) do
            it("rejects schema_version " .. tostring(version), function()
                local t = valid_table()
                t.schema_version = version
                local res = rule_config.try_new(t)
                assert.is_false(res.ok)
                assert.are.equal("unsupported_schema_version", res.error.code)
            end)
        end

        it("rejects a missing schema_version", function()
            local t = valid_table()
            t.schema_version = nil
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("unsupported_schema_version", res.error.code)
        end)
    end)

    describe("to_json / from_json round trip", function()
        it("encodes the canonical config and decodes back to a working RuleConfig", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            assert.is_string(s)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.is_true(rule_config.is_rule_config(res.config))
            assert.are.equal(100, res.config.bidding.opening_min)
            assert.are.equal(40, res.config.marriages.values.spades)
            assert.are.equal(-120, res.config.barrel.fall_off_penalty)
            assert.are.equal(1000, res.config.endgame.target_score)
        end)

        it("is byte-stable across a double round-trip", function()
            local first = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(first)
            assert.is_true(res.ok)
            local second = rule_config.to_json(res.config)
            assert.are.equal(first, second)
        end)

        it("rejects malformed JSON with json_decode_failed", function()
            local res = rule_config.from_json("{ not json }")
            assert.is_false(res.ok)
            assert.are.equal("json_decode_failed", res.error.code)
            assert.is_string(res.error.details)
        end)

        it("rejects non-string input to from_json", function()
            local res = rule_config.from_json(42)
            assert.is_false(res.ok)
            assert.are.equal("type_mismatch", res.error.code)
        end)

        it("propagates schema validation errors out of from_json", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local broken = s:gsub('"opening_min":100', '"opening_min":"100"')
            assert.are_not.equal(s, broken)
            local res = rule_config.from_json(broken)
            assert.is_false(res.ok)
            assert.are.equal("type_mismatch", res.error.code)
        end)

        it("to_json rejects a non-config argument", function()
            assert.has_error(function()
                rule_config.to_json({})
            end)
        end)
    end)

    describe("bidding.increment_threshold", function()
        it("exposes a leaf descriptor with the canonical default", function()
            local d = rule_config.schema_for("bidding.increment_threshold")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("number", d.lua_type)
            assert.are.equal(200, d.default)
            assert.are.equal(1, d.min)
            assert.are.equal("implemented", d.status)
        end)

        it("rejects a non-number value with type_mismatch", function()
            local t = valid_table()
            t.bidding.increment_threshold = "200"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("type_mismatch", res.error.code)
            assert.are.equal("bidding.increment_threshold", res.error.path)
        end)

        it("rejects a value below min with value_out_of_range", function()
            local t = valid_table()
            t.bidding.increment_threshold = 0
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("value_out_of_range", res.error.code)
            assert.are.equal("bidding.increment_threshold", res.error.path)
            assert.are.equal(0, res.error.value)
        end)

        it("survives a JSON round trip with a non-canonical value", function()
            local t = valid_table()
            t.bidding.increment_threshold = 150
            local config_in = rule_config.new(t)
            local s = rule_config.to_json(config_in)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal(150, res.config.bidding.increment_threshold)
        end)
    end)

    describe("players.count", function()
        it("exposes a leaf descriptor narrowed to {2, 3, 4} and selectable", function()
            local d = rule_config.schema_for("players.count")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("number", d.lua_type)
            assert.are.equal(3, d.default)
            assert.are.equal("selectable", d.status)
            assert.is_nil(d.min)
            assert.is_table(d.allowed)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed[2])
            assert.is_true(allowed[3])
            assert.is_true(allowed[4])
        end)

        it("rejects player counts outside {2, 3, 4} with value_not_allowed", function()
            for _, bad in ipairs({ 0, 1, 5, 99 }) do
                local t = valid_table()
                t.players.count = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "count=" .. bad .. " should be rejected")
                assert.are.equal("value_not_allowed", res.error.code)
                assert.are.equal("players.count", res.error.path)
                assert.are.equal(bad, res.error.value)
            end
        end)

        it("accepts each of 2, 3, 4 through try_new", function()
            for _, ok_count in ipairs({ 2, 3, 4 }) do
                local t = valid_table()
                t.players.count = ok_count
                local res = rule_config.try_new(t)
                assert.is_true(res.ok, "count=" .. ok_count .. " should be accepted")
                assert.are.equal(ok_count, res.config.players.count)
            end
        end)

        it("survives a JSON round trip with count = 2", function()
            local t = valid_table()
            t.players.count = 2
            local config_in = rule_config.new(t)
            local s = rule_config.to_json(config_in)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal(2, res.config.players.count)
        end)
    end)

    describe("players.partnership_mode", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("players.partnership_mode")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("none", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["none"])
            assert.is_true(allowed["fixed_across_table"])
        end)

        it("accepts the default value through try_new", function()
            local res = rule_config.try_new(valid_table())
            assert.is_true(res.ok)
            assert.are.equal("none", res.config.players.partnership_mode)
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            local t = valid_table()
            t.players.partnership_mode = "fixed_across_table"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("players.partnership_mode", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("none", res.config.players.partnership_mode)
        end)
    end)

    describe("players.four_player_config", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("players.four_player_config")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("dealer_plays_no_talon", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["dealer_plays_no_talon"])
            assert.is_true(allowed["dealer_sits_out"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            local t = valid_table()
            t.players.four_player_config = "dealer_sits_out"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("players.four_player_config", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("dealer_plays_no_talon", res.config.players.four_player_config)
        end)
    end)

    describe("players.two_player_config", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("players.two_player_config")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("closed_talon_draw_stock", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["closed_talon_draw_stock"])
            assert.is_true(allowed["fixed_deal_no_draw"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            local t = valid_table()
            t.players.two_player_config = "fixed_deal_no_draw"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("players.two_player_config", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("closed_talon_draw_stock", res.config.players.two_player_config)
        end)
    end)

    describe("dealing.four_nine_redeal", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("dealing.four_nine_redeal")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("off", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["off"])
            assert.is_true(allowed["optional"])
            assert.is_true(allowed["mandatory"])
        end)

        it("accepts the default value through try_new", function()
            local res = rule_config.try_new(valid_table())
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.dealing.four_nine_redeal)
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            for _, bad in ipairs({ "optional", "mandatory" }) do
                local t = valid_table()
                t.dealing.four_nine_redeal = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "value " .. bad .. " should be rejected")
                assert.are.equal("deferred_field_changed", res.error.code)
                assert.are.equal("dealing.four_nine_redeal", res.error.path)
            end
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.dealing.four_nine_redeal)
        end)
    end)

    describe("dealing.three_nine_redeal", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("dealing.three_nine_redeal")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("off", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["off"])
            assert.is_true(allowed["optional"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            local t = valid_table()
            t.dealing.three_nine_redeal = "optional"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("dealing.three_nine_redeal", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.dealing.three_nine_redeal)
        end)
    end)

    describe("dealing.four_jack_redeal", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("dealing.four_jack_redeal")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("off", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["off"])
            assert.is_true(allowed["on"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            local t = valid_table()
            t.dealing.four_jack_redeal = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("dealing.four_jack_redeal", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.dealing.four_jack_redeal)
        end)
    end)

    describe("dealing.weak_hand_redeal", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("dealing.weak_hand_redeal")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("off", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["off"])
            assert.is_true(allowed["strict"])
            assert.is_true(allowed["loose"])
            assert.is_true(allowed["counted"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            for _, bad in ipairs({ "strict", "loose", "counted" }) do
                local t = valid_table()
                t.dealing.weak_hand_redeal = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "value " .. bad .. " should be rejected")
                assert.are.equal("deferred_field_changed", res.error.code)
                assert.are.equal("dealing.weak_hand_redeal", res.error.path)
            end
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.dealing.weak_hand_redeal)
        end)
    end)

    describe("dealing.misdeal_handling", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("dealing.misdeal_handling")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("standard", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["standard"])
            assert.is_true(allowed["soft_penalty"])
            assert.is_true(allowed["flat_penalty"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            for _, bad in ipairs({ "soft_penalty", "flat_penalty" }) do
                local t = valid_table()
                t.dealing.misdeal_handling = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "value " .. bad .. " should be rejected")
                assert.are.equal("deferred_field_changed", res.error.code)
                assert.are.equal("dealing.misdeal_handling", res.error.path)
            end
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("standard", res.config.dealing.misdeal_handling)
        end)
    end)

    describe("dealing.all_pass_handling", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("dealing.all_pass_handling")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("redeal", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["redeal"])
            assert.is_true(allowed["pass_out"])
            assert.is_true(allowed["raspassy"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            for _, bad in ipairs({ "pass_out", "raspassy" }) do
                local t = valid_table()
                t.dealing.all_pass_handling = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "value " .. bad .. " should be rejected")
                assert.are.equal("deferred_field_changed", res.error.code)
                assert.are.equal("dealing.all_pass_handling", res.error.path)
            end
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("redeal", res.config.dealing.all_pass_handling)
        end)
    end)

    describe("cross-field invariants", function()
        it("rejects pre_talon_max below opening_min", function()
            local t = valid_table()
            t.bidding.pre_talon_max = 50
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("incompatible_combination", res.error.code)
            assert.are.equal("pre_talon_max_ge_opening_min", res.error.invariant)
            assert.are.equal(50, res.error.pre_talon_max)
            assert.are.equal(100, res.error.opening_min)
        end)

        it("rejects barrel threshold at or above target score", function()
            local t = valid_table()
            t.barrel.threshold = 1100
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("incompatible_combination", res.error.code)
            assert.are.equal("barrel_threshold_below_target", res.error.invariant)
            assert.are.equal(1100, res.error.threshold)
            assert.are.equal(1000, res.error.target_score)
        end)
    end)

    describe("status enforcement (via _validate)", function()
        -- Synthetic schema with one deferred field — exercises the
        -- deferred_field_changed path without mutating the production SCHEMA.
        local synth_schema = {
            _section_order = { "test_section" },
            schema_version = {
                kind = "leaf",
                lua_type = "number",
                allowed = { 1 },
                default = 1,
                status = "implemented",
            },
            test_section = {
                kind = "section",
                field_order = { "deferred_field" },
                fields = {
                    deferred_field = {
                        kind = "leaf",
                        lua_type = "number",
                        default = 42,
                        status = "deferred",
                    },
                },
            },
        }

        it("accepts a deferred field at its default value", function()
            local res = rule_config._validate({
                schema_version = 1,
                test_section = { deferred_field = 42 },
            }, synth_schema)
            assert.is_true(res.ok)
        end)

        it("rejects a deferred field that has been changed", function()
            local res = rule_config._validate({
                schema_version = 1,
                test_section = { deferred_field = 99 },
            }, synth_schema)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("test_section.deferred_field", res.error.path)
        end)
    end)

    describe("partnership_mode_requires_four_players invariant", function()
        -- partnership_mode is deferred in production, so the invariant can't
        -- fire through try_new today. Exercise its predicate against a
        -- synthetic schema where the field is selectable, and pass the
        -- invariant in explicitly so the production INVARIANTS list does not
        -- have to be reachable from the test.
        local synth_schema = {
            _section_order = { "players" },
            schema_version = {
                kind = "leaf",
                lua_type = "number",
                allowed = { 1 },
                default = 1,
                status = "implemented",
            },
            players = {
                kind = "section",
                field_order = { "count", "partnership_mode" },
                fields = {
                    count = {
                        kind = "leaf",
                        lua_type = "number",
                        allowed = { 2, 3, 4 },
                        default = 3,
                        status = "selectable",
                    },
                    partnership_mode = {
                        kind = "leaf",
                        lua_type = "string",
                        allowed = { "none", "fixed_across_table" },
                        default = "none",
                        status = "selectable",
                    },
                },
            },
        }

        local function find_invariant(name)
            for _, inv in ipairs(rule_config._invariants()) do
                if inv.name == name then
                    return inv
                end
            end
            return nil
        end

        it("is registered on the production INVARIANTS list", function()
            assert.is_not_nil(find_invariant("partnership_mode_requires_four_players"))
        end)

        it("accepts partnership_mode=none with any selectable player count", function()
            local invariants = { find_invariant("partnership_mode_requires_four_players") }
            for _, count in ipairs({ 2, 3, 4 }) do
                local res = rule_config._validate({
                    schema_version = 1,
                    players = { count = count, partnership_mode = "none" },
                }, synth_schema, invariants)
                assert.is_true(res.ok, "count=" .. count .. " with mode=none should pass")
            end
        end)

        it("accepts partnership_mode=fixed_across_table when count == 4", function()
            local invariants = { find_invariant("partnership_mode_requires_four_players") }
            local res = rule_config._validate({
                schema_version = 1,
                players = { count = 4, partnership_mode = "fixed_across_table" },
            }, synth_schema, invariants)
            assert.is_true(res.ok)
        end)

        it("rejects partnership_mode=fixed_across_table when count != 4", function()
            local invariants = { find_invariant("partnership_mode_requires_four_players") }
            for _, count in ipairs({ 2, 3 }) do
                local res = rule_config._validate({
                    schema_version = 1,
                    players = { count = count, partnership_mode = "fixed_across_table" },
                }, synth_schema, invariants)
                assert.is_false(res.ok, "count=" .. count .. " should be rejected")
                assert.are.equal("incompatible_combination", res.error.code)
                assert.are.equal("partnership_mode_requires_four_players", res.error.invariant)
                assert.are.equal("fixed_across_table", res.error.partnership_mode)
                assert.are.equal(count, res.error.count)
            end
        end)
    end)
end)
