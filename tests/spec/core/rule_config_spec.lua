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
            weak_hand_threshold = 14,
            misdeal_handling = "standard",
            misdeal_flat_penalty = 20,
            all_pass_handling = "redeal",
        },
        talon = {
            size = 3,
            distribution = "declarer_takes_then_passes",
            flip_after_first_round = "off",
            pass_the_talon = "off",
            buyback = "off",
            hidden_on_minimum_100 = "off",
            bad_talon_redeal = "off",
            rebuy = "off",
            open_discard = "off",
        },
        bidding = {
            opening_min = 100,
            pre_talon_max = 120,
            increment_threshold = 200,
            increment_below_200 = 5,
            increment_from_200 = 10,
            forced_opening = "off",
            forced_dealer_bid = "off",
            blind_bid = "off",
            re_entry_after_pass = "off",
            contra = "off",
            forced_bid_concession = "off",
            no_contract_without_marriage = "off",
            negative_score_restriction = "off",
            named_contracts = "off",
        },
        marriages = {
            values = { hearts = 100, diamonds = 80, clubs = 60, spades = 40 },
            half_marriage_capture_bonus = "off",
            trump_activation_timing = "next_trick",
            marriage_announcement_timing = "on_lead",
            drowned_marriage = "off",
            ace_marriage = "off",
            one_trump_per_deal = "off",
        },
        tricks = {
            must_follow = true,
            must_beat = true,
            must_trump = true,
            must_overtrump = true,
            must_overtake_strictness = "standard",
            must_trump_strictness = "standard",
            defender_must_overtrump_declarer = "off",
            lazy_revoke = "off",
            partial_trumping = "off",
            last_trick_bonus = "off",
            slam_bonus = "off",
            slam_against_penalty = "off",
            lead_trump_after_marriage = "off",
        },
        scoring = {
            round_to_nearest = 5,
            actual_points_on_success = "off",
            defender_contributions = "standard",
            failed_contract_distribution = "lost",
            declarer_rounding_before_contract_check = "off",
        },
        opening_game = { golden_deal = "off" },
        barrel = {
            threshold = 880,
            deal_count = 3,
            fall_off_penalty = -120,
            pit_lock_in = "off",
            collision_rule = "last_mounter",
            overshoot_penalty = "off",
            reverse_barrel = "off",
        },
        endgame = {
            target_score = 1000,
            going_over_target = "win_immediately",
            tiebreaker = "declarer_wins",
            dump_truck = "off",
        },
        specials = {
            mizere = "off",
            slam_contract = "off",
            open_hand = "off",
        },
        penalties = {
            revoke = "standard",
            talon_look = "standard",
            showing_hand = "standard",
            zero_tricks = "off",
            cross = "off",
        },
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
                "opening_game",
                "barrel",
                "endgame",
                "specials",
                "penalties",
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
            assert.are.equal(14, config.dealing.weak_hand_threshold)
            assert.are.equal("standard", config.dealing.misdeal_handling)
            assert.are.equal(20, config.dealing.misdeal_flat_penalty)
            assert.are.equal("redeal", config.dealing.all_pass_handling)
        end)

        it("encodes the canonical talon-section defaults", function()
            assert.are.equal("declarer_takes_then_passes", config.talon.distribution)
            assert.are.equal("off", config.talon.flip_after_first_round)
            assert.are.equal("off", config.talon.pass_the_talon)
            assert.are.equal("off", config.talon.buyback)
            assert.are.equal("off", config.talon.hidden_on_minimum_100)
            assert.are.equal("off", config.talon.bad_talon_redeal)
            assert.are.equal("off", config.talon.rebuy)
            assert.are.equal("off", config.talon.open_discard)
        end)

        it("encodes the canonical bidding rules", function()
            assert.are.equal(100, config.bidding.opening_min)
            assert.are.equal(120, config.bidding.pre_talon_max)
            assert.are.equal(200, config.bidding.increment_threshold)
            assert.are.equal(5, config.bidding.increment_below_200)
            assert.are.equal(10, config.bidding.increment_from_200)
            assert.are.equal("off", config.bidding.forced_opening)
            assert.are.equal("off", config.bidding.forced_dealer_bid)
            assert.are.equal("off", config.bidding.blind_bid)
            assert.are.equal("off", config.bidding.re_entry_after_pass)
            assert.are.equal("off", config.bidding.contra)
            assert.are.equal("off", config.bidding.forced_bid_concession)
            assert.are.equal("off", config.bidding.no_contract_without_marriage)
            assert.are.equal("off", config.bidding.negative_score_restriction)
            assert.are.equal("off", config.bidding.named_contracts)
        end)

        it("encodes the canonical marriage values", function()
            assert.are.equal(100, config.marriages.values.hearts)
            assert.are.equal(80, config.marriages.values.diamonds)
            assert.are.equal(60, config.marriages.values.clubs)
            assert.are.equal(40, config.marriages.values.spades)
        end)

        it("encodes the canonical marriage toggles at their defaults", function()
            assert.are.equal("off", config.marriages.half_marriage_capture_bonus)
            assert.are.equal("next_trick", config.marriages.trump_activation_timing)
            assert.are.equal("on_lead", config.marriages.marriage_announcement_timing)
            assert.are.equal("off", config.marriages.drowned_marriage)
            assert.are.equal("off", config.marriages.ace_marriage)
            assert.are.equal("off", config.marriages.one_trump_per_deal)
        end)

        it("encodes the canonical strict trick rules", function()
            assert.is_true(config.tricks.must_follow)
            assert.is_true(config.tricks.must_beat)
            assert.is_true(config.tricks.must_trump)
            assert.is_true(config.tricks.must_overtrump)
        end)

        it("encodes the canonical trick-play toggles at their defaults", function()
            assert.are.equal("standard", config.tricks.must_overtake_strictness)
            assert.are.equal("standard", config.tricks.must_trump_strictness)
            assert.are.equal("off", config.tricks.defender_must_overtrump_declarer)
            assert.are.equal("off", config.tricks.lazy_revoke)
            assert.are.equal("off", config.tricks.partial_trumping)
            assert.are.equal("off", config.tricks.last_trick_bonus)
            assert.are.equal("off", config.tricks.slam_bonus)
            assert.are.equal("off", config.tricks.slam_against_penalty)
            assert.are.equal("off", config.tricks.lead_trump_after_marriage)
        end)

        it("encodes the canonical scoring rounding", function()
            assert.are.equal(5, config.scoring.round_to_nearest)
        end)

        it("encodes the canonical scoring toggles at their defaults", function()
            assert.are.equal("off", config.scoring.actual_points_on_success)
            assert.are.equal("standard", config.scoring.defender_contributions)
            assert.are.equal("lost", config.scoring.failed_contract_distribution)
            assert.are.equal("off", config.scoring.declarer_rounding_before_contract_check)
        end)

        it("encodes the canonical barrel rules", function()
            assert.are.equal(880, config.barrel.threshold)
            assert.are.equal(3, config.barrel.deal_count)
            assert.are.equal(-120, config.barrel.fall_off_penalty)
        end)

        it("encodes the canonical opening-game toggle at its default", function()
            assert.are.equal("off", config.opening_game.golden_deal)
        end)

        it("encodes the canonical barrel toggles at their defaults", function()
            assert.are.equal("off", config.barrel.pit_lock_in)
            assert.are.equal("last_mounter", config.barrel.collision_rule)
            assert.are.equal("off", config.barrel.overshoot_penalty)
            assert.are.equal("off", config.barrel.reverse_barrel)
        end)

        it("encodes the canonical target score", function()
            assert.are.equal(1000, config.endgame.target_score)
        end)

        it("encodes the canonical endgame toggles at their defaults", function()
            assert.are.equal("win_immediately", config.endgame.going_over_target)
            assert.are.equal("declarer_wins", config.endgame.tiebreaker)
            assert.are.equal("off", config.endgame.dump_truck)
        end)

        it("encodes the canonical special-contract toggles at their defaults", function()
            assert.are.equal("off", config.specials.mizere)
            assert.are.equal("off", config.specials.slam_contract)
            assert.are.equal("off", config.specials.open_hand)
        end)

        it("encodes the canonical penalty toggles at their defaults", function()
            assert.are.equal("standard", config.penalties.revoke)
            assert.are.equal("standard", config.penalties.talon_look)
            assert.are.equal("standard", config.penalties.showing_hand)
            assert.are.equal("off", config.penalties.zero_tricks)
            assert.are.equal("off", config.penalties.cross)
        end)
    end)

    describe("builtins (3-player regional templates)", function()
        it("exposes a builtins registry table", function()
            assert.is_table(rule_config.builtins)
        end)

        describe("russian", function()
            it("aliases canonical_russian", function()
                assert.are.equal(rule_config.canonical_russian, rule_config.builtins.russian)
            end)
        end)

        describe("polish", function()
            local config = rule_config.builtins.polish

            it("is a frozen RuleConfig", function()
                assert.is_true(rule_config.is_rule_config(config))
            end)

            it("declares schema_version 1", function()
                assert.are.equal(1, config.schema_version)
            end)

            it("uses the Polish 2-card talon", function()
                assert.are.equal(2, config.talon.size)
            end)

            it("uses 10-step bid increments throughout the auction", function()
                assert.are.equal(10, config.bidding.increment_below_200)
                assert.are.equal(10, config.bidding.increment_from_200)
            end)

            it("keeps the canonical Russian shape elsewhere", function()
                local canonical = rule_config.canonical_russian
                assert.are.equal(canonical.players.count, config.players.count)
                assert.are.equal(canonical.bidding.opening_min, config.bidding.opening_min)
                assert.are.equal(canonical.bidding.pre_talon_max, config.bidding.pre_talon_max)
                assert.are.equal(canonical.marriages.values.hearts, config.marriages.values.hearts)
                assert.are.equal(canonical.marriages.values.spades, config.marriages.values.spades)
                assert.are.equal(canonical.barrel.threshold, config.barrel.threshold)
                assert.are.equal(canonical.barrel.deal_count, config.barrel.deal_count)
                assert.are.equal(canonical.endgame.target_score, config.endgame.target_score)
            end)

            it("round-trips through JSON", function()
                local round_trip = rule_config.from_json(rule_config.to_json(config))
                assert.is_true(round_trip.ok)
                assert.are.equal(2, round_trip.config.talon.size)
                assert.are.equal(10, round_trip.config.bidding.increment_below_200)
            end)
        end)

        describe("ukrainian", function()
            local config = rule_config.builtins.ukrainian

            it("is a frozen RuleConfig", function()
                assert.is_true(rule_config.is_rule_config(config))
            end)

            it("declares schema_version 1", function()
                assert.are.equal(1, config.schema_version)
            end)

            it("tightens the barrel to two deals", function()
                assert.are.equal(2, config.barrel.deal_count)
            end)

            it("keeps the canonical Russian shape elsewhere", function()
                local canonical = rule_config.canonical_russian
                assert.are.equal(canonical.players.count, config.players.count)
                assert.are.equal(canonical.talon.size, config.talon.size)
                assert.are.equal(canonical.bidding.opening_min, config.bidding.opening_min)
                assert.are.equal(
                    canonical.bidding.increment_below_200,
                    config.bidding.increment_below_200
                )
                assert.are.equal(canonical.barrel.threshold, config.barrel.threshold)
                assert.are.equal(canonical.barrel.fall_off_penalty, config.barrel.fall_off_penalty)
                assert.are.equal(canonical.endgame.target_score, config.endgame.target_score)
            end)

            it("round-trips through JSON", function()
                local round_trip = rule_config.from_json(rule_config.to_json(config))
                assert.is_true(round_trip.ok)
                assert.are.equal(2, round_trip.config.barrel.deal_count)
            end)
        end)

        it("is_rule_config recognises every regional builtin", function()
            for id, config in pairs(rule_config.builtins) do
                assert.is_true(
                    rule_config.is_rule_config(config),
                    "builtins." .. id .. " must be a RuleConfig"
                )
            end
        end)
    end)

    describe("builtins (2-player and 4-player templates)", function()
        describe("two_player_a", function()
            local config = rule_config.builtins.two_player_a

            it("is a frozen RuleConfig", function()
                assert.is_true(rule_config.is_rule_config(config))
            end)

            it("uses 2 players", function()
                assert.are.equal(2, config.players.count)
            end)

            it("disables the talon (the 6-card stock is dealt separately)", function()
                assert.are.equal(0, config.talon.size)
            end)

            it("selects the closed-talon-with-draw-stock layout", function()
                assert.are.equal("closed_talon_draw_stock", config.players.two_player_config)
            end)

            it("round-trips through JSON", function()
                local round_trip = rule_config.from_json(rule_config.to_json(config))
                assert.is_true(round_trip.ok)
                assert.are.equal(2, round_trip.config.players.count)
                assert.are.equal(0, round_trip.config.talon.size)
            end)
        end)

        describe("two_player_b", function()
            local config = rule_config.builtins.two_player_b

            it("is a frozen RuleConfig", function()
                assert.is_true(rule_config.is_rule_config(config))
            end)

            it("uses 2 players", function()
                assert.are.equal(2, config.players.count)
            end)

            it("uses the standard 3-card talon", function()
                assert.are.equal(3, config.talon.size)
            end)

            it("selects the fixed-deal-no-draw layout", function()
                assert.are.equal("fixed_deal_no_draw", config.players.two_player_config)
            end)

            it("round-trips through JSON", function()
                local round_trip = rule_config.from_json(rule_config.to_json(config))
                assert.is_true(round_trip.ok)
                assert.are.equal(2, round_trip.config.players.count)
                assert.are.equal(3, round_trip.config.talon.size)
            end)
        end)

        describe("four_player_a", function()
            local config = rule_config.builtins.four_player_a

            it("is a frozen RuleConfig", function()
                assert.is_true(rule_config.is_rule_config(config))
            end)

            it("uses 4 players", function()
                assert.are.equal(4, config.players.count)
            end)

            it("disables the talon entirely", function()
                assert.are.equal(0, config.talon.size)
            end)

            it("keeps the dealer-plays-no-talon configuration", function()
                assert.are.equal("dealer_plays_no_talon", config.players.four_player_config)
            end)

            it("plays in fixed across-the-table partnerships", function()
                assert.are.equal("fixed_across_table", config.players.partnership_mode)
            end)

            it("round-trips through JSON", function()
                local round_trip = rule_config.from_json(rule_config.to_json(config))
                assert.is_true(round_trip.ok)
                assert.are.equal(4, round_trip.config.players.count)
                assert.are.equal(0, round_trip.config.talon.size)
            end)
        end)

        describe("four_player_b", function()
            local config = rule_config.builtins.four_player_b

            it("is a frozen RuleConfig", function()
                assert.is_true(rule_config.is_rule_config(config))
            end)

            it("uses 4 players", function()
                assert.are.equal(4, config.players.count)
            end)

            it("uses the standard 3-card talon", function()
                assert.are.equal(3, config.talon.size)
            end)

            it("selects the dealer-sits-out configuration", function()
                assert.are.equal("dealer_sits_out", config.players.four_player_config)
            end)

            it("plays in fixed across-the-table partnerships", function()
                assert.are.equal("fixed_across_table", config.players.partnership_mode)
            end)

            it("round-trips through JSON", function()
                local round_trip = rule_config.from_json(rule_config.to_json(config))
                assert.is_true(round_trip.ok)
                assert.are.equal(4, round_trip.config.players.count)
                assert.are.equal(3, round_trip.config.talon.size)
            end)
        end)

        it("registers every player-count variant under builtins", function()
            local ids = { "two_player_a", "two_player_b", "four_player_a", "four_player_b" }
            for _, id in ipairs(ids) do
                assert.is_true(
                    rule_config.is_rule_config(rule_config.builtins[id]),
                    "builtins." .. id .. " must be a RuleConfig"
                )
            end
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
    end)

    describe("sections", function()
        it("returns the canonical section traversal order", function()
            local sections = rule_config.sections()
            assert.are.same({
                "cards",
                "players",
                "dealing",
                "talon",
                "bidding",
                "marriages",
                "tricks",
                "scoring",
                "opening_game",
                "barrel",
                "endgame",
                "specials",
                "penalties",
            }, sections)
        end)

        it("returns a fresh copy that callers can mutate without affecting the schema", function()
            local first = rule_config.sections()
            first[1] = "tampered"
            local second = rule_config.sections()
            assert.are.equal("cards", second[1])
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
                        "weak_hand_threshold",
                        "misdeal_handling",
                        "misdeal_flat_penalty",
                        "all_pass_handling",
                    },
                },
                {
                    "talon",
                    {
                        "size",
                        "distribution",
                        "flip_after_first_round",
                        "pass_the_talon",
                        "buyback",
                        "hidden_on_minimum_100",
                        "bad_talon_redeal",
                        "rebuy",
                        "open_discard",
                    },
                },
                {
                    "bidding",
                    {
                        "opening_min",
                        "pre_talon_max",
                        "increment_threshold",
                        "increment_below_200",
                        "increment_from_200",
                        "forced_opening",
                        "forced_dealer_bid",
                        "blind_bid",
                        "re_entry_after_pass",
                        "contra",
                        "forced_bid_concession",
                        "no_contract_without_marriage",
                        "negative_score_restriction",
                        "named_contracts",
                    },
                },
                {
                    "marriages",
                    {
                        "values",
                        "half_marriage_capture_bonus",
                        "trump_activation_timing",
                        "marriage_announcement_timing",
                        "drowned_marriage",
                        "ace_marriage",
                        "one_trump_per_deal",
                    },
                },
                {
                    "tricks",
                    {
                        "must_follow",
                        "must_beat",
                        "must_trump",
                        "must_overtrump",
                        "must_overtake_strictness",
                        "must_trump_strictness",
                        "defender_must_overtrump_declarer",
                        "lazy_revoke",
                        "partial_trumping",
                        "last_trick_bonus",
                        "slam_bonus",
                        "slam_against_penalty",
                        "lead_trump_after_marriage",
                    },
                },
                {
                    "scoring",
                    {
                        "round_to_nearest",
                        "actual_points_on_success",
                        "defender_contributions",
                        "failed_contract_distribution",
                        "declarer_rounding_before_contract_check",
                    },
                },
                { "opening_game", { "golden_deal" } },
                {
                    "barrel",
                    {
                        "threshold",
                        "deal_count",
                        "fall_off_penalty",
                        "pit_lock_in",
                        "collision_rule",
                        "overshoot_penalty",
                        "reverse_barrel",
                    },
                },
                {
                    "endgame",
                    {
                        "target_score",
                        "going_over_target",
                        "tiebreaker",
                        "dump_truck",
                    },
                },
                { "specials", { "mizere", "slam_contract", "open_hand" } },
                {
                    "penalties",
                    {
                        "revoke",
                        "talon_look",
                        "showing_hand",
                        "zero_tricks",
                        "cross",
                    },
                },
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
            -- The Phase 3.6 layout-consistency invariants force a specific
            -- (count, talon.size, *_config) combination. Each accepted
            -- count therefore needs the matching layout selector and
            -- talon size; otherwise the invariant fires.
            local cases = {
                {
                    count = 2,
                    overrides = {
                        players = { two_player_config = "fixed_deal_no_draw" },
                        talon = { size = 3 },
                    },
                },
                { count = 3, overrides = {} },
                {
                    count = 4,
                    overrides = {
                        players = { four_player_config = "dealer_sits_out" },
                        talon = { size = 3 },
                    },
                },
            }
            for _, case in ipairs(cases) do
                local t = valid_table()
                t.players.count = case.count
                for section, fields in pairs(case.overrides) do
                    for k, v in pairs(fields) do
                        t[section][k] = v
                    end
                end
                local res = rule_config.try_new(t)
                assert.is_true(res.ok, "count=" .. case.count .. " should be accepted")
                assert.are.equal(case.count, res.config.players.count)
            end
        end)

        it("survives a JSON round trip with count = 2", function()
            local t = valid_table()
            t.players.count = 2
            t.players.two_player_config = "fixed_deal_no_draw"
            t.talon.size = 3
            local config_in = rule_config.new(t)
            local s = rule_config.to_json(config_in)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal(2, res.config.players.count)
        end)
    end)

    describe("players.partnership_mode", function()
        it("exposes a selectable string-leaf descriptor", function()
            local d = rule_config.schema_for("players.partnership_mode")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("none", d.default)
            assert.are.equal("selectable", d.status)
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

        it("rejects fixed_across_table with non-4-player counts", function()
            local t = valid_table()
            t.players.partnership_mode = "fixed_across_table"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("incompatible_combination", res.error.code)
            assert.are.equal("partnership_mode_requires_four_players", res.error.invariant)
        end)

        it("accepts fixed_across_table with count = 4 in a valid layout", function()
            local t = valid_table()
            t.players.count = 4
            t.players.partnership_mode = "fixed_across_table"
            t.players.four_player_config = "dealer_sits_out"
            local res = rule_config.try_new(t)
            assert.is_true(res.ok)
            assert.are.equal("fixed_across_table", res.config.players.partnership_mode)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("none", res.config.players.partnership_mode)
        end)
    end)

    describe("players.four_player_config", function()
        it("exposes a selectable string-leaf descriptor", function()
            local d = rule_config.schema_for("players.four_player_config")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("dealer_plays_no_talon", d.default)
            assert.are.equal("selectable", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["dealer_plays_no_talon"])
            assert.is_true(allowed["dealer_sits_out"])
        end)

        it("accepts dealer_sits_out under count = 3 (silently ignored)", function()
            -- The four_player_b consistency invariant only fires when
            -- count == 4; for canonical 3-player the field is inert.
            local t = valid_table()
            t.players.four_player_config = "dealer_sits_out"
            local res = rule_config.try_new(t)
            assert.is_true(res.ok)
            assert.are.equal("dealer_sits_out", res.config.players.four_player_config)
        end)

        it("rejects dealer_plays_no_talon under count = 4 with talon.size = 3", function()
            local t = valid_table()
            t.players.count = 4
            -- four_player_config stays at the default "dealer_plays_no_talon"
            -- but talon.size = 3 contradicts the no-talon spec.
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("incompatible_combination", res.error.code)
            assert.are.equal("four_player_a_requires_no_talon", res.error.invariant)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("dealer_plays_no_talon", res.config.players.four_player_config)
        end)
    end)

    describe("players.two_player_config", function()
        it("exposes a selectable string-leaf descriptor", function()
            local d = rule_config.schema_for("players.two_player_config")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("closed_talon_draw_stock", d.default)
            assert.are.equal("selectable", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["closed_talon_draw_stock"])
            assert.is_true(allowed["fixed_deal_no_draw"])
        end)

        it("accepts fixed_deal_no_draw under count = 3 (silently ignored)", function()
            local t = valid_table()
            t.players.two_player_config = "fixed_deal_no_draw"
            local res = rule_config.try_new(t)
            assert.is_true(res.ok)
            assert.are.equal("fixed_deal_no_draw", res.config.players.two_player_config)
        end)

        it("rejects closed_talon_draw_stock under count = 2 with talon.size = 3", function()
            local t = valid_table()
            t.players.count = 2
            -- two_player_config stays at the default "closed_talon_draw_stock"
            -- but talon.size = 3 contradicts the stock-draw spec.
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("incompatible_combination", res.error.code)
            assert.are.equal("two_player_a_requires_no_talon", res.error.invariant)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("closed_talon_draw_stock", res.config.players.two_player_config)
        end)
    end)

    describe("dealing.four_nine_redeal", function()
        it("exposes a selectable string-leaf descriptor", function()
            local d = rule_config.schema_for("dealing.four_nine_redeal")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("off", d.default)
            assert.are.equal("selectable", d.status)
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

        it("accepts every allowed value through try_new", function()
            for _, ok_value in ipairs({ "off", "optional", "mandatory" }) do
                local t = valid_table()
                t.dealing.four_nine_redeal = ok_value
                local res = rule_config.try_new(t)
                assert.is_true(res.ok, "value " .. ok_value .. " should be accepted")
                assert.are.equal(ok_value, res.config.dealing.four_nine_redeal)
            end
        end)

        it("rejects an unknown value with value_not_allowed", function()
            local t = valid_table()
            t.dealing.four_nine_redeal = "always"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("value_not_allowed", res.error.code)
            assert.are.equal("dealing.four_nine_redeal", res.error.path)
        end)

        it("survives a JSON round trip at mandatory", function()
            local t = valid_table()
            t.dealing.four_nine_redeal = "mandatory"
            local config_in = rule_config.new(t)
            local s = rule_config.to_json(config_in)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("mandatory", res.config.dealing.four_nine_redeal)
        end)
    end)

    describe("dealing.three_nine_redeal", function()
        it("exposes a selectable string-leaf descriptor", function()
            local d = rule_config.schema_for("dealing.three_nine_redeal")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("off", d.default)
            assert.are.equal("selectable", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["off"])
            assert.is_true(allowed["optional"])
            assert.is_true(allowed["mandatory"])
        end)

        it("accepts every allowed value through try_new", function()
            for _, ok_value in ipairs({ "off", "optional", "mandatory" }) do
                local t = valid_table()
                t.dealing.three_nine_redeal = ok_value
                local res = rule_config.try_new(t)
                assert.is_true(res.ok, "value " .. ok_value .. " should be accepted")
                assert.are.equal(ok_value, res.config.dealing.three_nine_redeal)
            end
        end)

        it("rejects an unknown value with value_not_allowed", function()
            local t = valid_table()
            t.dealing.three_nine_redeal = "always"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("value_not_allowed", res.error.code)
            assert.are.equal("dealing.three_nine_redeal", res.error.path)
        end)

        it("survives a JSON round trip at mandatory", function()
            local t = valid_table()
            t.dealing.three_nine_redeal = "mandatory"
            local config_in = rule_config.new(t)
            local s = rule_config.to_json(config_in)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("mandatory", res.config.dealing.three_nine_redeal)
        end)
    end)

    describe("dealing.four_jack_redeal", function()
        it("exposes a selectable string-leaf descriptor", function()
            local d = rule_config.schema_for("dealing.four_jack_redeal")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("off", d.default)
            assert.are.equal("selectable", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["off"])
            assert.is_true(allowed["optional"])
            assert.is_true(allowed["mandatory"])
        end)

        it("accepts every allowed value through try_new", function()
            for _, ok_value in ipairs({ "off", "optional", "mandatory" }) do
                local t = valid_table()
                t.dealing.four_jack_redeal = ok_value
                local res = rule_config.try_new(t)
                assert.is_true(res.ok, "value " .. ok_value .. " should be accepted")
                assert.are.equal(ok_value, res.config.dealing.four_jack_redeal)
            end
        end)

        it("rejects an unknown value with value_not_allowed", function()
            local t = valid_table()
            t.dealing.four_jack_redeal = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("value_not_allowed", res.error.code)
            assert.are.equal("dealing.four_jack_redeal", res.error.path)
        end)

        it("survives a JSON round trip at mandatory", function()
            local t = valid_table()
            t.dealing.four_jack_redeal = "mandatory"
            local config_in = rule_config.new(t)
            local s = rule_config.to_json(config_in)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("mandatory", res.config.dealing.four_jack_redeal)
        end)
    end)

    describe("dealing.weak_hand_redeal", function()
        it("exposes a selectable string-leaf descriptor", function()
            local d = rule_config.schema_for("dealing.weak_hand_redeal")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("off", d.default)
            assert.are.equal("selectable", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["off"])
            assert.is_true(allowed["strict"])
            assert.is_true(allowed["loose"])
            assert.is_true(allowed["counted"])
        end)

        it("accepts every allowed value through try_new", function()
            for _, ok_value in ipairs({ "off", "strict", "loose", "counted" }) do
                local t = valid_table()
                t.dealing.weak_hand_redeal = ok_value
                local res = rule_config.try_new(t)
                assert.is_true(res.ok, "value " .. ok_value .. " should be accepted")
                assert.are.equal(ok_value, res.config.dealing.weak_hand_redeal)
            end
        end)

        it("rejects an unknown value with value_not_allowed", function()
            local t = valid_table()
            t.dealing.weak_hand_redeal = "permissive"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("value_not_allowed", res.error.code)
            assert.are.equal("dealing.weak_hand_redeal", res.error.path)
        end)

        it("survives a JSON round trip at counted with a custom threshold", function()
            local t = valid_table()
            t.dealing.weak_hand_redeal = "counted"
            t.dealing.weak_hand_threshold = 12
            local config_in = rule_config.new(t)
            local s = rule_config.to_json(config_in)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("counted", res.config.dealing.weak_hand_redeal)
            assert.are.equal(12, res.config.dealing.weak_hand_threshold)
        end)
    end)

    describe("dealing.weak_hand_threshold", function()
        it("exposes a selectable number-leaf descriptor with a 0..120 range", function()
            local d = rule_config.schema_for("dealing.weak_hand_threshold")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("number", d.lua_type)
            assert.are.equal(14, d.default)
            assert.are.equal(0, d.min)
            assert.are.equal(120, d.max)
            assert.are.equal("selectable", d.status)
        end)

        it("accepts the default value through try_new", function()
            local res = rule_config.try_new(valid_table())
            assert.is_true(res.ok)
            assert.are.equal(14, res.config.dealing.weak_hand_threshold)
        end)

        it("accepts both range endpoints", function()
            for _, ok_value in ipairs({ 0, 1, 14, 60, 120 }) do
                local t = valid_table()
                t.dealing.weak_hand_threshold = ok_value
                local res = rule_config.try_new(t)
                assert.is_true(res.ok, "threshold=" .. ok_value .. " should be accepted")
                assert.are.equal(ok_value, res.config.dealing.weak_hand_threshold)
            end
        end)

        it("rejects out-of-range values with value_out_of_range", function()
            for _, bad in ipairs({ -1, 121, 9999 }) do
                local t = valid_table()
                t.dealing.weak_hand_threshold = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "threshold=" .. bad .. " should be rejected")
                assert.are.equal("value_out_of_range", res.error.code)
                assert.are.equal("dealing.weak_hand_threshold", res.error.path)
            end
        end)
    end)

    describe("dealing.misdeal_handling", function()
        it("exposes a selectable string-leaf descriptor", function()
            local d = rule_config.schema_for("dealing.misdeal_handling")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("standard", d.default)
            assert.are.equal("selectable", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["standard"])
            assert.is_true(allowed["soft_penalty"])
            assert.is_true(allowed["flat_penalty"])
        end)

        it("accepts every allowed value through try_new", function()
            for _, ok_value in ipairs({ "standard", "soft_penalty", "flat_penalty" }) do
                local t = valid_table()
                t.dealing.misdeal_handling = ok_value
                local res = rule_config.try_new(t)
                assert.is_true(res.ok, "value " .. ok_value .. " should be accepted")
                assert.are.equal(ok_value, res.config.dealing.misdeal_handling)
            end
        end)

        it("rejects an unknown value with value_not_allowed", function()
            local t = valid_table()
            t.dealing.misdeal_handling = "harsh"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("value_not_allowed", res.error.code)
            assert.are.equal("dealing.misdeal_handling", res.error.path)
        end)

        it("survives a JSON round trip at flat_penalty with a custom amount", function()
            local t = valid_table()
            t.dealing.misdeal_handling = "flat_penalty"
            t.dealing.misdeal_flat_penalty = 60
            local config_in = rule_config.new(t)
            local s = rule_config.to_json(config_in)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("flat_penalty", res.config.dealing.misdeal_handling)
            assert.are.equal(60, res.config.dealing.misdeal_flat_penalty)
        end)
    end)

    describe("dealing.misdeal_flat_penalty", function()
        it("exposes a selectable number-leaf descriptor with a 0..240 range", function()
            local d = rule_config.schema_for("dealing.misdeal_flat_penalty")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("number", d.lua_type)
            assert.are.equal(20, d.default)
            assert.are.equal(0, d.min)
            assert.are.equal(240, d.max)
            assert.are.equal("selectable", d.status)
        end)

        it("accepts the default value through try_new", function()
            local res = rule_config.try_new(valid_table())
            assert.is_true(res.ok)
            assert.are.equal(20, res.config.dealing.misdeal_flat_penalty)
        end)

        it("accepts both range endpoints", function()
            for _, ok_value in ipairs({ 0, 20, 60, 120, 240 }) do
                local t = valid_table()
                t.dealing.misdeal_flat_penalty = ok_value
                local res = rule_config.try_new(t)
                assert.is_true(res.ok, "penalty=" .. ok_value .. " should be accepted")
                assert.are.equal(ok_value, res.config.dealing.misdeal_flat_penalty)
            end
        end)

        it("rejects out-of-range values with value_out_of_range", function()
            for _, bad in ipairs({ -1, 241, 9999 }) do
                local t = valid_table()
                t.dealing.misdeal_flat_penalty = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "penalty=" .. bad .. " should be rejected")
                assert.are.equal("value_out_of_range", res.error.code)
                assert.are.equal("dealing.misdeal_flat_penalty", res.error.path)
            end
        end)
    end)

    describe("dealing.all_pass_handling", function()
        it("exposes a selectable string-leaf descriptor", function()
            local d = rule_config.schema_for("dealing.all_pass_handling")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("redeal", d.default)
            assert.are.equal("selectable", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["redeal"])
            assert.is_true(allowed["pass_out"])
            assert.is_true(allowed["raspassy"])
        end)

        it("accepts every allowed value through try_new", function()
            for _, ok_value in ipairs({ "redeal", "pass_out", "raspassy" }) do
                local t = valid_table()
                t.dealing.all_pass_handling = ok_value
                local res = rule_config.try_new(t)
                assert.is_true(res.ok, "value " .. ok_value .. " should be accepted")
                assert.are.equal(ok_value, res.config.dealing.all_pass_handling)
            end
        end)

        it("rejects an unknown value with value_not_allowed", function()
            local t = valid_table()
            t.dealing.all_pass_handling = "redeal_with_bonus"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("value_not_allowed", res.error.code)
            assert.are.equal("dealing.all_pass_handling", res.error.path)
        end)

        it("survives a JSON round trip at raspassy", function()
            local t = valid_table()
            t.dealing.all_pass_handling = "raspassy"
            local config_in = rule_config.new(t)
            local s = rule_config.to_json(config_in)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("raspassy", res.config.dealing.all_pass_handling)
        end)
    end)

    describe("talon.size", function()
        it("exposes a selectable number-leaf descriptor with allowed = {0, 2, 3}", function()
            local d = rule_config.schema_for("talon.size")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("number", d.lua_type)
            assert.are.equal(3, d.default)
            assert.are.equal("selectable", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed[0])
            assert.is_true(allowed[2])
            assert.is_true(allowed[3])
        end)

        it("accepts the default value through try_new", function()
            local res = rule_config.try_new(valid_table())
            assert.is_true(res.ok)
            assert.are.equal(3, res.config.talon.size)
        end)

        it("accepts each of 0, 2, 3 through try_new (selectable, not deferred)", function()
            for _, ok_size in ipairs({ 0, 2, 3 }) do
                local t = valid_table()
                t.talon.size = ok_size
                local res = rule_config.try_new(t)
                assert.is_true(res.ok, "size=" .. ok_size .. " should be accepted")
                assert.are.equal(ok_size, res.config.talon.size)
            end
        end)

        it("rejects sizes outside {0, 2, 3} with value_not_allowed", function()
            for _, bad in ipairs({ -1, 1, 4, 5, 99 }) do
                local t = valid_table()
                t.talon.size = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "size=" .. bad .. " should be rejected")
                assert.are.equal("value_not_allowed", res.error.code)
                assert.are.equal("talon.size", res.error.path)
                assert.are.equal(bad, res.error.value)
            end
        end)

        it("survives a JSON round trip with size = 2", function()
            local t = valid_table()
            t.talon.size = 2
            local config_in = rule_config.new(t)
            local s = rule_config.to_json(config_in)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal(2, res.config.talon.size)
        end)
    end)

    describe("talon.distribution", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("talon.distribution")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("declarer_takes_then_passes", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["declarer_takes_then_passes"])
            assert.is_true(allowed["pass_without_taking"])
            assert.is_true(allowed["stock_draw"])
        end)

        it("accepts the default value through try_new", function()
            local res = rule_config.try_new(valid_table())
            assert.is_true(res.ok)
            assert.are.equal("declarer_takes_then_passes", res.config.talon.distribution)
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            for _, bad in ipairs({ "pass_without_taking", "stock_draw" }) do
                local t = valid_table()
                t.talon.distribution = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "value " .. bad .. " should be rejected")
                assert.are.equal("deferred_field_changed", res.error.code)
                assert.are.equal("talon.distribution", res.error.path)
            end
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("declarer_takes_then_passes", res.config.talon.distribution)
        end)
    end)

    describe("talon.flip_after_first_round", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("talon.flip_after_first_round")
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
            t.talon.flip_after_first_round = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("talon.flip_after_first_round", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.talon.flip_after_first_round)
        end)
    end)

    describe("talon.pass_the_talon", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("talon.pass_the_talon")
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
            t.talon.pass_the_talon = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("talon.pass_the_talon", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.talon.pass_the_talon)
        end)
    end)

    describe("talon.buyback", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("talon.buyback")
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
            t.talon.buyback = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("talon.buyback", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.talon.buyback)
        end)
    end)

    describe("talon.hidden_on_minimum_100", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("talon.hidden_on_minimum_100")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("off", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["off"])
            assert.is_true(allowed["minimum_100_only"])
            assert.is_true(allowed["any_forced_100"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            for _, bad in ipairs({ "minimum_100_only", "any_forced_100" }) do
                local t = valid_table()
                t.talon.hidden_on_minimum_100 = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "value " .. bad .. " should be rejected")
                assert.are.equal("deferred_field_changed", res.error.code)
                assert.are.equal("talon.hidden_on_minimum_100", res.error.path)
            end
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.talon.hidden_on_minimum_100)
        end)
    end)

    describe("talon.bad_talon_redeal", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("talon.bad_talon_redeal")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("off", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["off"])
            assert.is_true(allowed["any_contract"])
            assert.is_true(allowed["minimum_100_only"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            for _, bad in ipairs({ "any_contract", "minimum_100_only" }) do
                local t = valid_table()
                t.talon.bad_talon_redeal = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "value " .. bad .. " should be rejected")
                assert.are.equal("deferred_field_changed", res.error.code)
                assert.are.equal("talon.bad_talon_redeal", res.error.path)
            end
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.talon.bad_talon_redeal)
        end)
    end)

    describe("talon.rebuy", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("talon.rebuy")
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
            t.talon.rebuy = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("talon.rebuy", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.talon.rebuy)
        end)
    end)

    describe("talon.open_discard", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("talon.open_discard")
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
            t.talon.open_discard = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("talon.open_discard", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.talon.open_discard)
        end)
    end)

    describe("bidding.forced_opening", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("bidding.forced_opening")
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
            t.bidding.forced_opening = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("bidding.forced_opening", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.bidding.forced_opening)
        end)
    end)

    describe("bidding.forced_dealer_bid", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("bidding.forced_dealer_bid")
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
            t.bidding.forced_dealer_bid = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("bidding.forced_dealer_bid", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.bidding.forced_dealer_bid)
        end)
    end)

    describe("bidding.blind_bid", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("bidding.blind_bid")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("off", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["off"])
            assert.is_true(allowed["first_bid_double"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            local t = valid_table()
            t.bidding.blind_bid = "first_bid_double"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("bidding.blind_bid", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.bidding.blind_bid)
        end)
    end)

    describe("bidding.re_entry_after_pass", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("bidding.re_entry_after_pass")
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
            t.bidding.re_entry_after_pass = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("bidding.re_entry_after_pass", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.bidding.re_entry_after_pass)
        end)
    end)

    describe("bidding.contra", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("bidding.contra")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("off", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["off"])
            assert.is_true(allowed["contra_only"])
            assert.is_true(allowed["contra_and_redouble"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            for _, bad in ipairs({ "contra_only", "contra_and_redouble" }) do
                local t = valid_table()
                t.bidding.contra = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "value " .. bad .. " should be rejected")
                assert.are.equal("deferred_field_changed", res.error.code)
                assert.are.equal("bidding.contra", res.error.path)
            end
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.bidding.contra)
        end)
    end)

    describe("bidding.forced_bid_concession", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("bidding.forced_bid_concession")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("off", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["off"])
            assert.is_true(allowed["equal_split"])
            assert.is_true(allowed["each_full"])
            assert.is_true(allowed["preset_ratio"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            for _, bad in ipairs({ "equal_split", "each_full", "preset_ratio" }) do
                local t = valid_table()
                t.bidding.forced_bid_concession = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "value " .. bad .. " should be rejected")
                assert.are.equal("deferred_field_changed", res.error.code)
                assert.are.equal("bidding.forced_bid_concession", res.error.path)
            end
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.bidding.forced_bid_concession)
        end)
    end)

    describe("bidding.no_contract_without_marriage", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("bidding.no_contract_without_marriage")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("off", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["off"])
            assert.is_true(allowed["no_120_without_marriage"])
            assert.is_true(allowed["capped_by_marriages"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            for _, bad in ipairs({ "no_120_without_marriage", "capped_by_marriages" }) do
                local t = valid_table()
                t.bidding.no_contract_without_marriage = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "value " .. bad .. " should be rejected")
                assert.are.equal("deferred_field_changed", res.error.code)
                assert.are.equal("bidding.no_contract_without_marriage", res.error.path)
            end
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.bidding.no_contract_without_marriage)
        end)
    end)

    describe("bidding.negative_score_restriction", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("bidding.negative_score_restriction")
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
            t.bidding.negative_score_restriction = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("bidding.negative_score_restriction", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.bidding.negative_score_restriction)
        end)
    end)

    describe("bidding.named_contracts", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("bidding.named_contracts")
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
            t.bidding.named_contracts = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("bidding.named_contracts", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.bidding.named_contracts)
        end)
    end)

    describe("marriages.half_marriage_capture_bonus", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("marriages.half_marriage_capture_bonus")
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
            t.marriages.half_marriage_capture_bonus = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("marriages.half_marriage_capture_bonus", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.marriages.half_marriage_capture_bonus)
        end)
    end)

    describe("marriages.trump_activation_timing", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("marriages.trump_activation_timing")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("next_trick", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["next_trick"])
            assert.is_true(allowed["immediate"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            local t = valid_table()
            t.marriages.trump_activation_timing = "immediate"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("marriages.trump_activation_timing", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("next_trick", res.config.marriages.trump_activation_timing)
        end)
    end)

    describe("marriages.marriage_announcement_timing", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("marriages.marriage_announcement_timing")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("on_lead", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["on_lead"])
            assert.is_true(allowed["hand_announcement"])
            assert.is_true(allowed["pre_first_trick"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            for _, bad in ipairs({ "hand_announcement", "pre_first_trick" }) do
                local t = valid_table()
                t.marriages.marriage_announcement_timing = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "value " .. bad .. " should be rejected")
                assert.are.equal("deferred_field_changed", res.error.code)
                assert.are.equal("marriages.marriage_announcement_timing", res.error.path)
            end
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("on_lead", res.config.marriages.marriage_announcement_timing)
        end)
    end)

    describe("marriages.drowned_marriage", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("marriages.drowned_marriage")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("off", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["off"])
            assert.is_true(allowed["retroactive_cancel"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            local t = valid_table()
            t.marriages.drowned_marriage = "retroactive_cancel"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("marriages.drowned_marriage", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.marriages.drowned_marriage)
        end)
    end)

    describe("marriages.ace_marriage", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("marriages.ace_marriage")
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
            assert.is_true(allowed["sets_trump"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            for _, bad in ipairs({ "on", "sets_trump" }) do
                local t = valid_table()
                t.marriages.ace_marriage = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "value " .. bad .. " should be rejected")
                assert.are.equal("deferred_field_changed", res.error.code)
                assert.are.equal("marriages.ace_marriage", res.error.path)
            end
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.marriages.ace_marriage)
        end)
    end)

    describe("marriages.one_trump_per_deal", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("marriages.one_trump_per_deal")
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
            t.marriages.one_trump_per_deal = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("marriages.one_trump_per_deal", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.marriages.one_trump_per_deal)
        end)
    end)

    describe("tricks.must_follow", function()
        it("is locked to the guarded constant `true`", function()
            local d = rule_config.schema_for("tricks.must_follow")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("boolean", d.lua_type)
            assert.are.equal(true, d.default)
            assert.are.equal("implemented", d.status)
            assert.is_table(d.allowed)
            assert.are.equal(1, #d.allowed)
            assert.are.equal(true, d.allowed[1])
        end)

        it("rejects must_follow = false with value_not_allowed", function()
            local t = valid_table()
            t.tricks.must_follow = false
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("value_not_allowed", res.error.code)
            assert.are.equal("tricks.must_follow", res.error.path)
            assert.are.equal(false, res.error.value)
        end)
    end)

    describe("tricks.must_overtake_strictness", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("tricks.must_overtake_strictness")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("standard", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["standard"])
            assert.is_true(allowed["polish_strict"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            local t = valid_table()
            t.tricks.must_overtake_strictness = "polish_strict"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("tricks.must_overtake_strictness", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("standard", res.config.tricks.must_overtake_strictness)
        end)
    end)

    describe("tricks.must_trump_strictness", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("tricks.must_trump_strictness")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("standard", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["standard"])
            assert.is_true(allowed["polish_strict"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            local t = valid_table()
            t.tricks.must_trump_strictness = "polish_strict"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("tricks.must_trump_strictness", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("standard", res.config.tricks.must_trump_strictness)
        end)
    end)

    describe("tricks.defender_must_overtrump_declarer", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("tricks.defender_must_overtrump_declarer")
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
            t.tricks.defender_must_overtrump_declarer = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("tricks.defender_must_overtrump_declarer", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.tricks.defender_must_overtrump_declarer)
        end)
    end)

    describe("tricks.lazy_revoke", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("tricks.lazy_revoke")
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
            t.tricks.lazy_revoke = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("tricks.lazy_revoke", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.tricks.lazy_revoke)
        end)
    end)

    describe("tricks.partial_trumping", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("tricks.partial_trumping")
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
            t.tricks.partial_trumping = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("tricks.partial_trumping", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.tricks.partial_trumping)
        end)
    end)

    describe("tricks.last_trick_bonus", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("tricks.last_trick_bonus")
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
            t.tricks.last_trick_bonus = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("tricks.last_trick_bonus", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.tricks.last_trick_bonus)
        end)
    end)

    describe("tricks.slam_bonus", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("tricks.slam_bonus")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("off", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["off"])
            assert.is_true(allowed["fixed"])
            assert.is_true(allowed["doubled_bid"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            for _, bad in ipairs({ "fixed", "doubled_bid" }) do
                local t = valid_table()
                t.tricks.slam_bonus = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "value " .. bad .. " should be rejected")
                assert.are.equal("deferred_field_changed", res.error.code)
                assert.are.equal("tricks.slam_bonus", res.error.path)
            end
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.tricks.slam_bonus)
        end)
    end)

    describe("tricks.slam_against_penalty", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("tricks.slam_against_penalty")
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
            t.tricks.slam_against_penalty = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("tricks.slam_against_penalty", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.tricks.slam_against_penalty)
        end)
    end)

    describe("tricks.lead_trump_after_marriage", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("tricks.lead_trump_after_marriage")
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
            t.tricks.lead_trump_after_marriage = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("tricks.lead_trump_after_marriage", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.tricks.lead_trump_after_marriage)
        end)
    end)

    describe("scoring.round_to_nearest", function()
        it("exposes a selectable number-leaf descriptor with allowed = {5, 10}", function()
            local d = rule_config.schema_for("scoring.round_to_nearest")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("number", d.lua_type)
            assert.are.equal(5, d.default)
            assert.are.equal("selectable", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed[5])
            assert.is_true(allowed[10])
        end)

        it("accepts each of 5, 10 through try_new (selectable, not deferred)", function()
            for _, ok_value in ipairs({ 5, 10 }) do
                local t = valid_table()
                t.scoring.round_to_nearest = ok_value
                local res = rule_config.try_new(t)
                assert.is_true(res.ok, "round_to_nearest=" .. ok_value .. " should be accepted")
                assert.are.equal(ok_value, res.config.scoring.round_to_nearest)
            end
        end)

        it("rejects values outside {5, 10} with value_not_allowed", function()
            for _, bad in ipairs({ 0, 1, 3, 7, 20 }) do
                local t = valid_table()
                t.scoring.round_to_nearest = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "round_to_nearest=" .. bad .. " should be rejected")
                assert.are.equal("value_not_allowed", res.error.code)
                assert.are.equal("scoring.round_to_nearest", res.error.path)
                assert.are.equal(bad, res.error.value)
            end
        end)

        it("survives a JSON round trip with round_to_nearest = 10", function()
            local t = valid_table()
            t.scoring.round_to_nearest = 10
            local config_in = rule_config.new(t)
            local s = rule_config.to_json(config_in)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal(10, res.config.scoring.round_to_nearest)
        end)
    end)

    describe("scoring.actual_points_on_success", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("scoring.actual_points_on_success")
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
            t.scoring.actual_points_on_success = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("scoring.actual_points_on_success", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.scoring.actual_points_on_success)
        end)
    end)

    describe("scoring.defender_contributions", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("scoring.defender_contributions")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("standard", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["standard"])
            assert.is_true(allowed["pooled"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            local t = valid_table()
            t.scoring.defender_contributions = "pooled"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("scoring.defender_contributions", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("standard", res.config.scoring.defender_contributions)
        end)
    end)

    describe("scoring.failed_contract_distribution", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("scoring.failed_contract_distribution")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("lost", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["lost"])
            assert.is_true(allowed["split_among_defenders"])
            assert.is_true(allowed["each_defender_full"])
            assert.is_true(allowed["mirrors_forced_concession"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            for _, bad in ipairs({
                "split_among_defenders",
                "each_defender_full",
                "mirrors_forced_concession",
            }) do
                local t = valid_table()
                t.scoring.failed_contract_distribution = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "value " .. bad .. " should be rejected")
                assert.are.equal("deferred_field_changed", res.error.code)
                assert.are.equal("scoring.failed_contract_distribution", res.error.path)
            end
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("lost", res.config.scoring.failed_contract_distribution)
        end)
    end)

    describe("opening_game.golden_deal", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("opening_game.golden_deal")
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
            t.opening_game.golden_deal = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("opening_game.golden_deal", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.opening_game.golden_deal)
        end)
    end)

    describe("barrel.pit_lock_in", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("barrel.pit_lock_in")
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
            t.barrel.pit_lock_in = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("barrel.pit_lock_in", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.barrel.pit_lock_in)
        end)
    end)

    describe("barrel.collision_rule", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("barrel.collision_rule")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("last_mounter", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["last_mounter"])
            assert.is_true(allowed["first_mounter"])
            assert.is_true(allowed["all_collide_fall_off"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            for _, bad in ipairs({ "first_mounter", "all_collide_fall_off" }) do
                local t = valid_table()
                t.barrel.collision_rule = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "value " .. bad .. " should be rejected")
                assert.are.equal("deferred_field_changed", res.error.code)
                assert.are.equal("barrel.collision_rule", res.error.path)
            end
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("last_mounter", res.config.barrel.collision_rule)
        end)
    end)

    describe("barrel.overshoot_penalty", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("barrel.overshoot_penalty")
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
            t.barrel.overshoot_penalty = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("barrel.overshoot_penalty", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.barrel.overshoot_penalty)
        end)
    end)

    describe("barrel.reverse_barrel", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("barrel.reverse_barrel")
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
            t.barrel.reverse_barrel = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("barrel.reverse_barrel", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.barrel.reverse_barrel)
        end)
    end)

    describe("endgame.going_over_target", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("endgame.going_over_target")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("win_immediately", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["win_immediately"])
            assert.is_true(allowed["exact_only"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            local t = valid_table()
            t.endgame.going_over_target = "exact_only"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("endgame.going_over_target", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("win_immediately", res.config.endgame.going_over_target)
        end)
    end)

    describe("endgame.tiebreaker", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("endgame.tiebreaker")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("declarer_wins", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["declarer_wins"])
            assert.is_true(allowed["high_score"])
            assert.is_true(allowed["continuation"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            for _, bad in ipairs({ "high_score", "continuation" }) do
                local t = valid_table()
                t.endgame.tiebreaker = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "value " .. bad .. " should be rejected")
                assert.are.equal("deferred_field_changed", res.error.code)
                assert.are.equal("endgame.tiebreaker", res.error.path)
            end
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("declarer_wins", res.config.endgame.tiebreaker)
        end)
    end)

    describe("endgame.dump_truck", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("endgame.dump_truck")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("off", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["off"])
            assert.is_true(allowed["positive_only"])
            assert.is_true(allowed["both_signs"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            for _, bad in ipairs({ "positive_only", "both_signs" }) do
                local t = valid_table()
                t.endgame.dump_truck = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "value " .. bad .. " should be rejected")
                assert.are.equal("deferred_field_changed", res.error.code)
                assert.are.equal("endgame.dump_truck", res.error.path)
            end
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.endgame.dump_truck)
        end)
    end)

    describe("scoring.declarer_rounding_before_contract_check", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("scoring.declarer_rounding_before_contract_check")
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
            t.scoring.declarer_rounding_before_contract_check = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("scoring.declarer_rounding_before_contract_check", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.scoring.declarer_rounding_before_contract_check)
        end)
    end)

    describe("specials.mizere", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("specials.mizere")
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
            t.specials.mizere = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("specials.mizere", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.specials.mizere)
        end)
    end)

    describe("specials.slam_contract", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("specials.slam_contract")
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
            t.specials.slam_contract = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("specials.slam_contract", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.specials.slam_contract)
        end)
    end)

    describe("specials.open_hand", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("specials.open_hand")
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
            t.specials.open_hand = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("specials.open_hand", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.specials.open_hand)
        end)
    end)

    describe("penalties.revoke", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("penalties.revoke")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("standard", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["standard"])
            assert.is_true(allowed["flat"])
            assert.is_true(allowed["configurable"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            for _, bad in ipairs({ "flat", "configurable" }) do
                local t = valid_table()
                t.penalties.revoke = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "value " .. bad .. " should be rejected")
                assert.are.equal("deferred_field_changed", res.error.code)
                assert.are.equal("penalties.revoke", res.error.path)
            end
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("standard", res.config.penalties.revoke)
        end)
    end)

    describe("penalties.talon_look", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("penalties.talon_look")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("standard", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["standard"])
            assert.is_true(allowed["stricter"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            local t = valid_table()
            t.penalties.talon_look = "stricter"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("penalties.talon_look", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("standard", res.config.penalties.talon_look)
        end)
    end)

    describe("penalties.showing_hand", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("penalties.showing_hand")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("standard", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["standard"])
            assert.is_true(allowed["strict"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            local t = valid_table()
            t.penalties.showing_hand = "strict"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("penalties.showing_hand", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("standard", res.config.penalties.showing_hand)
        end)
    end)

    describe("penalties.zero_tricks", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("penalties.zero_tricks")
            assert.are.equal("leaf", d.kind)
            assert.are.equal("string", d.lua_type)
            assert.are.equal("off", d.default)
            assert.are.equal("deferred", d.status)
            local allowed = {}
            for _, v in ipairs(d.allowed) do
                allowed[v] = true
            end
            assert.is_true(allowed["off"])
            assert.is_true(allowed["consecutive_three"])
            assert.is_true(allowed["any_three"])
        end)

        it("rejects any non-default value with deferred_field_changed", function()
            for _, bad in ipairs({ "consecutive_three", "any_three" }) do
                local t = valid_table()
                t.penalties.zero_tricks = bad
                local res = rule_config.try_new(t)
                assert.is_false(res.ok, "value " .. bad .. " should be rejected")
                assert.are.equal("deferred_field_changed", res.error.code)
                assert.are.equal("penalties.zero_tricks", res.error.path)
            end
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.penalties.zero_tricks)
        end)
    end)

    describe("penalties.cross", function()
        it("exposes a deferred string-leaf descriptor", function()
            local d = rule_config.schema_for("penalties.cross")
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
            t.penalties.cross = "on"
            local res = rule_config.try_new(t)
            assert.is_false(res.ok)
            assert.are.equal("deferred_field_changed", res.error.code)
            assert.are.equal("penalties.cross", res.error.path)
        end)

        it("survives a JSON round trip at its default", function()
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            assert.are.equal("off", res.config.penalties.cross)
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
