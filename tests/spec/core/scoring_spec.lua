local scoring = require("core.scoring")
local rule_config = require("core.rule_config")

local config = rule_config.canonical_russian

local function score_ok(opts)
    local result = scoring.score_deal(config, opts)
    assert.is_true(
        result.ok,
        "fixture: score_deal must succeed (got "
            .. (result.error and result.error.code or "?")
            .. ")"
    )
    return result.scoring
end

-- Defaults that respect the deck-total invariant: card points sum to
-- 120 across all sides. Marriage bonuses default to zero so individual
-- tests can override the slice they care about.
local function default_opts(overrides)
    local opts = {
        declarer = 1,
        bid = 100,
        captured_points = { 75, 25, 20 },
        marriage_bonuses = { 0, 0, 0 },
        running_totals = { 0, 0, 0 },
    }
    if overrides then
        for k, v in pairs(overrides) do
            opts[k] = v
        end
    end
    return opts
end

describe("core.scoring", function()
    describe("module shape", function()
        it("exposes the documented public surface", function()
            assert.is_function(scoring.score_deal)
            assert.is_function(scoring.is_scoring)
            assert.is_function(scoring.advance_game)
            assert.is_function(scoring.is_game)
            assert.is_function(scoring.initial_barrel_state)
            assert.is_number(scoring.SCHEMA_VERSION)
        end)
    end)

    describe("score_deal() validation", function()
        it("rejects a non-RuleConfig", function()
            for _, bad in ipairs({ 42, "config", {}, true }) do
                local result = scoring.score_deal(bad, default_opts())
                assert.is_false(result.ok)
                assert.are.equal("not_a_rule_config", result.error.code)
            end
            local nil_result = scoring.score_deal(nil, default_opts())
            assert.is_false(nil_result.ok)
            assert.are.equal("not_a_rule_config", nil_result.error.code)
        end)

        it("rejects a non-table opts argument", function()
            for _, bad in ipairs({ 42, "opts", true }) do
                local result = scoring.score_deal(config, bad)
                assert.is_false(result.ok)
                assert.are.equal("bad_opts", result.error.code)
            end
            local nil_result = scoring.score_deal(config, nil)
            assert.is_false(nil_result.ok)
            assert.are.equal("bad_opts", nil_result.error.code)
        end)

        it("rejects a declarer outside the 1..N range", function()
            for _, bad in ipairs({ 0, 4, 1.5, "1", true, {} }) do
                local result = scoring.score_deal(config, default_opts({ declarer = bad }))
                assert.is_false(result.ok)
                assert.are.equal("bad_declarer", result.error.code)
            end
            -- A missing declarer key reads as nil and is rejected too.
            local nil_result = scoring.score_deal(config, {
                bid = 100,
                captured_points = { 75, 25, 20 },
                marriage_bonuses = { 0, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_false(nil_result.ok)
            assert.are.equal("bad_declarer", nil_result.error.code)
        end)

        it("rejects a non-integer bid", function()
            for _, bad in ipairs({ "100", true, {}, 1.5 }) do
                local result = scoring.score_deal(config, default_opts({ bid = bad }))
                assert.is_false(result.ok)
                assert.are.equal("bad_bid", result.error.code)
            end
            local nil_result = scoring.score_deal(config, {
                declarer = 1,
                captured_points = { 75, 25, 20 },
                marriage_bonuses = { 0, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_false(nil_result.ok)
            assert.are.equal("bad_bid", nil_result.error.code)
        end)

        it("rejects captured_points of the wrong shape", function()
            local r1 = scoring.score_deal(config, default_opts({ captured_points = { 50, 50 } }))
            assert.is_false(r1.ok)
            assert.are.equal("bad_captured_points", r1.error.code)

            local r2 = scoring.score_deal(config, default_opts({ captured_points = "bad" }))
            assert.is_false(r2.ok)
            assert.are.equal("bad_captured_points", r2.error.code)

            local r3 =
                scoring.score_deal(config, default_opts({ captured_points = { 50, "x", 50 } }))
            assert.is_false(r3.ok)
            assert.are.equal("bad_captured_points", r3.error.code)
        end)

        it("rejects marriage_bonuses of the wrong shape", function()
            local r1 = scoring.score_deal(config, default_opts({ marriage_bonuses = { 0 } }))
            assert.is_false(r1.ok)
            assert.are.equal("bad_marriage_bonuses", r1.error.code)

            local r2 = scoring.score_deal(config, default_opts({ marriage_bonuses = "bad" }))
            assert.is_false(r2.ok)
            assert.are.equal("bad_marriage_bonuses", r2.error.code)
        end)

        it("rejects running_totals of the wrong shape", function()
            local r1 = scoring.score_deal(config, default_opts({ running_totals = {} }))
            assert.is_false(r1.ok)
            assert.are.equal("bad_running_totals", r1.error.code)

            local r2 = scoring.score_deal(config, default_opts({ running_totals = "bad" }))
            assert.is_false(r2.ok)
            assert.are.equal("bad_running_totals", r2.error.code)
        end)

        it("rejects negative captured_points", function()
            local result =
                scoring.score_deal(config, default_opts({ captured_points = { -5, 50, 70 } }))
            assert.is_false(result.ok)
            assert.are.equal("bad_captured_points", result.error.code)
            assert.are.equal(1, result.error.player)
        end)

        it("rejects negative marriage_bonuses", function()
            local result =
                scoring.score_deal(config, default_opts({ marriage_bonuses = { 0, -10, 0 } }))
            assert.is_false(result.ok)
            assert.are.equal("bad_marriage_bonuses", result.error.code)
            assert.are.equal(2, result.error.player)
        end)

        it("rejects captured_points whose sum exceeds 120", function()
            local result =
                scoring.score_deal(config, default_opts({ captured_points = { 80, 30, 30 } }))
            assert.is_false(result.ok)
            assert.are.equal("captured_points_exceed_deck", result.error.code)
            assert.are.equal(140, result.error.actual)
            assert.are.equal(120, result.error.max)
        end)

        it("accepts captured_points whose sum is below 120", function()
            -- A real deal lands at exactly 120, but the engine should not
            -- enforce equality — only the at-most invariant.
            local s = score_ok(default_opts({ captured_points = { 50, 30, 30 } }))
            local total = s.captured_points[1] + s.captured_points[2] + s.captured_points[3]
            assert.are.equal(110, total)
        end)

        it("accepts captured_points summing to exactly 120 (canonical deck total)", function()
            -- Pins the boundary: the cap derived from canonical
            -- point_values × 4 suits is exactly 120.
            local s = score_ok(default_opts({ captured_points = { 120, 0, 0 } }))
            assert.are.equal(120, s.captured_points[1])
        end)

        it("rejects 121 with max=120 under the canonical config", function()
            local result =
                scoring.score_deal(config, default_opts({ captured_points = { 121, 0, 0 } }))
            assert.is_false(result.ok)
            assert.are.equal("captured_points_exceed_deck", result.error.code)
            assert.are.equal(121, result.error.actual)
            assert.are.equal(120, result.error.max)
        end)

        it("derives the cap from config.cards.point_values when a variant changes them", function()
            -- Variant: K is worth 5 instead of 4. Per-suit total is
            -- 11+10+5+3+2+0 = 31; deck total = 31 × 4 = 124.
            local variant = rule_config.new({
                schema_version = 1,
                cards = {
                    point_values = {
                        ["A"] = 11,
                        ["10"] = 10,
                        ["K"] = 5,
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
            })

            local accepted = scoring.score_deal(
                variant,
                default_opts({
                    captured_points = { 124, 0, 0 },
                })
            )
            assert.is_true(accepted.ok)

            local rejected = scoring.score_deal(
                variant,
                default_opts({
                    captured_points = { 125, 0, 0 },
                })
            )
            assert.is_false(rejected.ok)
            assert.are.equal("captured_points_exceed_deck", rejected.error.code)
            assert.are.equal(125, rejected.error.actual)
            assert.are.equal(124, rejected.error.max)
        end)
    end)

    describe("score_deal() rounding", function()
        it("rounds 73 up to 75 and 22 down to 20", function()
            local s = score_ok(default_opts({
                captured_points = { 73, 22, 25 },
                bid = 75,
            }))
            assert.are.equal(75, s.card_points_rounded[1])
            assert.are.equal(20, s.card_points_rounded[2])
            assert.are.equal(25, s.card_points_rounded[3])
        end)

        it("rounds 67 down to 65", function()
            local s = score_ok(default_opts({
                captured_points = { 67, 33, 20 },
                bid = 65,
            }))
            assert.are.equal(65, s.card_points_rounded[1])
        end)

        it("leaves multiples of 5 unchanged", function()
            local s = score_ok(default_opts({
                captured_points = { 70, 30, 20 },
                bid = 70,
            }))
            assert.are.equal(70, s.card_points_rounded[1])
            assert.are.equal(30, s.card_points_rounded[2])
            assert.are.equal(20, s.card_points_rounded[3])
        end)

        it("rounds 0 to 0 and 120 to 120", function()
            local s = score_ok(default_opts({
                captured_points = { 0, 0, 120 },
                bid = 100,
            }))
            assert.are.equal(0, s.card_points_rounded[1])
            assert.are.equal(0, s.card_points_rounded[2])
            assert.are.equal(120, s.card_points_rounded[3])
        end)

        it("does not round marriage bonuses", function()
            -- Marriage values include the spades bonus 40 and the clubs
            -- bonus 60 — both already multiples of 5. To prove rounding
            -- isn't applied, scoring would have to change them; instead
            -- we assert exact passthrough.
            local s = score_ok(default_opts({
                captured_points = { 75, 25, 20 },
                marriage_bonuses = { 100, 0, 80 },
                bid = 100,
            }))
            assert.are.equal(100, s.marriage_bonuses[1])
            assert.are.equal(0, s.marriage_bonuses[2])
            assert.are.equal(80, s.marriage_bonuses[3])
        end)
    end)

    describe("score_deal() deal_scores", function()
        it("sums rounded card points and exact marriage bonuses", function()
            local s = score_ok(default_opts({
                captured_points = { 73, 22, 25 },
                marriage_bonuses = { 100, 0, 0 },
                bid = 120,
            }))
            assert.are.equal(75 + 100, s.deal_scores[1])
            assert.are.equal(20, s.deal_scores[2])
            assert.are.equal(25, s.deal_scores[3])
        end)
    end)

    describe("score_deal() contract result — declarer made contract", function()
        it("flags made_contract when deal_score is at least the bid", function()
            -- 75 cards + 100 hearts marriage = 175 >= bid 120.
            local s = score_ok(default_opts({
                captured_points = { 73, 22, 25 },
                marriage_bonuses = { 100, 0, 0 },
                bid = 120,
            }))
            assert.is_true(s.made_contract)
        end)

        it("flags made_contract when deal_score equals the bid exactly", function()
            -- 70 + 30 marriage = 100 == bid 100.
            local s = score_ok(default_opts({
                declarer = 2,
                bid = 100,
                captured_points = { 25, 70, 25 },
                marriage_bonuses = { 0, 30, 0 },
            }))
            assert.is_true(s.made_contract)
        end)

        it("adds the bid to the declarer's running total on success", function()
            local s = score_ok(default_opts({
                captured_points = { 73, 22, 25 },
                marriage_bonuses = { 100, 0, 0 },
                bid = 120,
                running_totals = { 200, 100, 50 },
            }))
            assert.are.equal(120, s.deltas[1])
            assert.are.equal(320, s.running_totals[1])
        end)

        it("never adds more than the bid to a successful declarer", function()
            -- Declarer's deal_score is 175, bid is 120. Canonical Russian
            -- adds the bid, not the actual deal_score.
            local s = score_ok(default_opts({
                captured_points = { 73, 22, 25 },
                marriage_bonuses = { 100, 0, 0 },
                bid = 120,
                running_totals = { 0, 0, 0 },
            }))
            assert.are.equal(120, s.deltas[1])
            assert.are_not.equal(175, s.deltas[1])
        end)
    end)

    describe("score_deal() contract result — declarer failed contract", function()
        it("does not flag made_contract when deal_score is below bid", function()
            -- 75 cards + 0 marriages = 75, below bid 100.
            local s = score_ok(default_opts({
                captured_points = { 73, 22, 25 },
                bid = 100,
            }))
            assert.is_false(s.made_contract)
        end)

        it("subtracts the bid from the declarer's running total on failure", function()
            local s = score_ok(default_opts({
                declarer = 1,
                bid = 100,
                captured_points = { 73, 22, 25 },
                running_totals = { 200, 100, 50 },
            }))
            assert.are.equal(-100, s.deltas[1])
            assert.are.equal(100, s.running_totals[1])
        end)

        it("can drive the declarer's running total negative", function()
            local s = score_ok(default_opts({
                declarer = 1,
                bid = 100,
                captured_points = { 73, 22, 25 },
                running_totals = { 50, 0, 0 },
            }))
            assert.are.equal(-100, s.deltas[1])
            assert.are.equal(-50, s.running_totals[1])
        end)
    end)

    describe("score_deal() defenders", function()
        it("adds each defender's deal_score to their running total", function()
            local s = score_ok(default_opts({
                declarer = 1,
                bid = 100,
                captured_points = { 73, 22, 25 },
                marriage_bonuses = { 0, 80, 0 },
                running_totals = { 0, 100, 50 },
            }))
            -- Player 2 deal_score = 20 (rounded) + 80 = 100.
            -- Player 3 deal_score = 25 (rounded) + 0 = 25.
            assert.are.equal(100, s.deltas[2])
            assert.are.equal(25, s.deltas[3])
            assert.are.equal(200, s.running_totals[2])
            assert.are.equal(75, s.running_totals[3])
        end)

        it("credits defender deal_scores even when declarer fails", function()
            local s = score_ok(default_opts({
                declarer = 1,
                bid = 120,
                captured_points = { 73, 22, 25 },
                marriage_bonuses = { 0, 80, 0 },
                running_totals = { 200, 100, 50 },
            }))
            assert.is_false(s.made_contract)
            assert.are.equal(-120, s.deltas[1])
            assert.are.equal(100, s.deltas[2])
            assert.are.equal(25, s.deltas[3])
        end)
    end)

    describe("score_deal() marriage attribution", function()
        it("credits marriage bonuses only to the declaring player", function()
            -- Declarer (player 1) declared ♥ marriage worth 100; defender
            -- (player 3) declared ♣ marriage worth 60. Each appears only
            -- in that player's marriage_bonuses slot.
            local s = score_ok(default_opts({
                declarer = 1,
                bid = 100,
                captured_points = { 73, 22, 25 },
                marriage_bonuses = { 100, 0, 60 },
                running_totals = { 0, 0, 0 },
            }))
            assert.are.equal(100, s.marriage_bonuses[1])
            assert.are.equal(0, s.marriage_bonuses[2])
            assert.are.equal(60, s.marriage_bonuses[3])
            -- Declarer's deal_score uses their bonus, not the defenders'.
            assert.are.equal(75 + 100, s.deal_scores[1])
            assert.are.equal(20, s.deal_scores[2])
            assert.are.equal(25 + 60, s.deal_scores[3])
        end)
    end)

    describe("score_deal() result shape", function()
        it("tags the state so is_scoring recognises it", function()
            local s = score_ok(default_opts())
            assert.is_true(scoring.is_scoring(s))
        end)

        it("rejects plain tables for is_scoring", function()
            assert.is_false(scoring.is_scoring(nil))
            assert.is_false(scoring.is_scoring(42))
            assert.is_false(scoring.is_scoring("scoring"))
            assert.is_false(scoring.is_scoring({}))
            assert.is_false(scoring.is_scoring({ deal_scores = {} }))
        end)

        it("stamps the schema version", function()
            local s = score_ok(default_opts())
            assert.are.equal(scoring.SCHEMA_VERSION, s.schema_version)
        end)

        it("retains the config for later reads", function()
            local s = score_ok(default_opts())
            assert.are.equal(config, s.config)
        end)

        it("retains declarer and bid", function()
            local s = score_ok(default_opts({ declarer = 2, bid = 105 }))
            assert.are.equal(2, s.declarer)
            assert.are.equal(105, s.bid)
        end)

        it("includes pre- and post-deal running totals", function()
            local s = score_ok(default_opts({
                declarer = 1,
                bid = 100,
                captured_points = { 73, 22, 25 },
                running_totals = { 200, 100, 50 },
            }))
            assert.are.same({ 200, 100, 50 }, s.running_totals_before)
            assert.are.same({ 100, 120, 75 }, s.running_totals)
        end)
    end)

    describe("score_deal() immutability", function()
        it("does not mutate the input opts lists", function()
            local opts = default_opts({
                captured_points = { 73, 22, 25 },
                marriage_bonuses = { 100, 0, 0 },
                running_totals = { 200, 100, 50 },
            })
            score_ok(opts)
            assert.are.same({ 73, 22, 25 }, opts.captured_points)
            assert.are.same({ 100, 0, 0 }, opts.marriage_bonuses)
            assert.are.same({ 200, 100, 50 }, opts.running_totals)
        end)

        it("returns lists independent of the input lists", function()
            local opts = default_opts({
                captured_points = { 73, 22, 25 },
                marriage_bonuses = { 100, 0, 0 },
                running_totals = { 200, 100, 50 },
            })
            local s = score_ok(opts)
            assert.are_not.equal(opts.captured_points, s.captured_points)
            assert.are_not.equal(opts.marriage_bonuses, s.marriage_bonuses)
            assert.are_not.equal(opts.running_totals, s.running_totals_before)
        end)
    end)

    describe("rules-doc sample scoresheet", function()
        it("matches deal 1: F bids 120 hearts, makes it, score +120", function()
            -- From docs/rules/scoring.md: F (player 1) bids 120 hearts and
            -- makes it. The published delta is +120 / +35 / +25.
            -- Construct deal totals consistent with that delta:
            --   * F (declarer) made contract, so delta = +120.
            --   * Defenders add their deal_score (rounded card points +
            --     any marriages they declared). 35 = 35 cards (rounded);
            --     25 = 25 cards (rounded). Cards sum 60+35+25=120. F's
            --     deal_score is 60 cards + 100 hearts marriage = 160 ≥
            --     bid 120, so F made it.
            local s = score_ok({
                declarer = 1,
                bid = 120,
                captured_points = { 60, 35, 25 },
                marriage_bonuses = { 100, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(s.made_contract)
            assert.are.equal(120, s.deltas[1])
            assert.are.equal(35, s.deltas[2])
            assert.are.equal(25, s.deltas[3])
        end)

        it("matches deal 2: F bids 100, fails (cards 95), score -100", function()
            -- Sample row: F bids 100, captures 95 cards, fails. M and R
            -- pick up 60 / 50 — meaning M caught a marriage (e.g. 30
            -- cards + 30 (?)) etc. The spec just asserts F's failure
            -- delta -100 and defender deltas equal their rounded
            -- card+marriage totals.
            local s = score_ok({
                declarer = 1,
                bid = 100,
                captured_points = { 95, 15, 10 },
                -- Defender M declared ♠♣ for 40+60=100? Simpler: give M
                -- a hearts marriage (100). Total marriage bonus must be
                -- attributable exactly.
                marriage_bonuses = { 0, 100, 0 },
                running_totals = { 200, 0, 0 },
            })
            assert.is_false(s.made_contract)
            assert.are.equal(-100, s.deltas[1])
            -- Player 2 deal_score: 15 → 15 (already a multiple of 5) +
            -- 100 = 115.
            assert.are.equal(115, s.deltas[2])
            assert.are.equal(10, s.deltas[3])
            assert.are.equal(100, s.running_totals[1])
        end)
    end)

    -- Defaults shared across advance_game tests. The default barrel state
    -- has every player off barrel so individual tests can override the
    -- slice they care about, just like the score_deal defaults.
    local function default_advance_opts(overrides)
        local opts = {
            declarer = 1,
            deal_index = 1,
            deltas = { 0, 0, 0 },
            running_totals_before = { 0, 0, 0 },
            barrel_state_before = scoring.initial_barrel_state(config),
        }
        if overrides then
            for k, v in pairs(overrides) do
                opts[k] = v
            end
        end
        return opts
    end

    local function advance_ok(opts)
        local result = scoring.advance_game(config, opts)
        assert.is_true(
            result.ok,
            "fixture: advance_game must succeed (got "
                .. (result.error and result.error.code or "?")
                .. ")"
        )
        return result.game
    end

    describe("initial_barrel_state()", function()
        it("returns one entry per player, all off barrel", function()
            local state = scoring.initial_barrel_state(config)
            assert.are.equal(config.players.count, #state)
            for i = 1, config.players.count do
                assert.is_false(state[i].on_barrel)
                assert.is_nil(state[i].mounted_on_deal)
                assert.is_nil(state[i].deals_remaining)
            end
        end)

        it("rejects a non-RuleConfig", function()
            assert.has_error(function()
                scoring.initial_barrel_state({})
            end)
        end)
    end)

    describe("advance_game() validation", function()
        it("rejects a non-RuleConfig", function()
            for _, bad in ipairs({ 42, "config", {}, true }) do
                local result = scoring.advance_game(bad, default_advance_opts())
                assert.is_false(result.ok)
                assert.are.equal("not_a_rule_config", result.error.code)
            end
            local nil_result = scoring.advance_game(nil, default_advance_opts())
            assert.is_false(nil_result.ok)
            assert.are.equal("not_a_rule_config", nil_result.error.code)
        end)

        it("rejects a non-table opts argument", function()
            for _, bad in ipairs({ 42, "opts", true }) do
                local result = scoring.advance_game(config, bad)
                assert.is_false(result.ok)
                assert.are.equal("bad_opts", result.error.code)
            end
            local nil_result = scoring.advance_game(config, nil)
            assert.is_false(nil_result.ok)
            assert.are.equal("bad_opts", nil_result.error.code)
        end)

        it("rejects a declarer outside the 1..N range", function()
            for _, bad in ipairs({ 0, 4, 1.5, "1", true, {} }) do
                local result =
                    scoring.advance_game(config, default_advance_opts({ declarer = bad }))
                assert.is_false(result.ok)
                assert.are.equal("bad_declarer", result.error.code)
            end
        end)

        it("rejects a non-positive-integer deal_index", function()
            for _, bad in ipairs({ 0, -1, 1.5, "1", true, {} }) do
                local result =
                    scoring.advance_game(config, default_advance_opts({ deal_index = bad }))
                assert.is_false(result.ok)
                assert.are.equal("bad_deal_index", result.error.code)
            end
        end)

        it("rejects deltas of the wrong shape", function()
            local r1 = scoring.advance_game(config, default_advance_opts({ deltas = { 0, 0 } }))
            assert.is_false(r1.ok)
            assert.are.equal("bad_deltas", r1.error.code)

            local r2 = scoring.advance_game(config, default_advance_opts({ deltas = "bad" }))
            assert.is_false(r2.ok)
            assert.are.equal("bad_deltas", r2.error.code)

            local r3 =
                scoring.advance_game(config, default_advance_opts({ deltas = { 0, "x", 0 } }))
            assert.is_false(r3.ok)
            assert.are.equal("bad_deltas", r3.error.code)
        end)

        it("rejects running_totals_before of the wrong shape", function()
            local r1 =
                scoring.advance_game(config, default_advance_opts({ running_totals_before = {} }))
            assert.is_false(r1.ok)
            assert.are.equal("bad_running_totals_before", r1.error.code)

            local r2 = scoring.advance_game(
                config,
                default_advance_opts({ running_totals_before = "bad" })
            )
            assert.is_false(r2.ok)
            assert.are.equal("bad_running_totals_before", r2.error.code)
        end)

        it("rejects barrel_state_before of the wrong length", function()
            local result = scoring.advance_game(
                config,
                default_advance_opts({
                    barrel_state_before = {
                        { on_barrel = false },
                        { on_barrel = false },
                    },
                })
            )
            assert.is_false(result.ok)
            assert.are.equal("bad_barrel_state_before", result.error.code)
        end)

        it("rejects barrel_state_before entries that are not tables", function()
            local result = scoring.advance_game(
                config,
                default_advance_opts({
                    barrel_state_before = { { on_barrel = false }, "bad", { on_barrel = false } },
                })
            )
            assert.is_false(result.ok)
            assert.are.equal("bad_barrel_state_before", result.error.code)
        end)

        it("rejects barrel_state_before entries with non-boolean on_barrel", function()
            local result = scoring.advance_game(
                config,
                default_advance_opts({
                    barrel_state_before = {
                        { on_barrel = false },
                        { on_barrel = "yes" },
                        { on_barrel = false },
                    },
                })
            )
            assert.is_false(result.ok)
            assert.are.equal("bad_barrel_state_before", result.error.code)
        end)

        it("rejects on-barrel entries missing mounted_on_deal", function()
            local result = scoring.advance_game(
                config,
                default_advance_opts({
                    barrel_state_before = {
                        { on_barrel = true, deals_remaining = 3 },
                        { on_barrel = false },
                        { on_barrel = false },
                    },
                })
            )
            assert.is_false(result.ok)
            assert.are.equal("bad_barrel_state_before", result.error.code)
        end)

        it("rejects on-barrel entries with bad deals_remaining", function()
            local result = scoring.advance_game(
                config,
                default_advance_opts({
                    deal_index = 5,
                    barrel_state_before = {
                        { on_barrel = true, mounted_on_deal = 4, deals_remaining = 0 },
                        { on_barrel = false },
                        { on_barrel = false },
                    },
                })
            )
            assert.is_false(result.ok)
            assert.are.equal("bad_barrel_state_before", result.error.code)
        end)
    end)

    describe("advance_game() normal advancement", function()
        it("adds deltas to running totals when nobody is near the barrel", function()
            local g = advance_ok(default_advance_opts({
                deltas = { 60, 30, 25 },
                running_totals_before = { 100, 200, 50 },
            }))
            assert.are.same({ 160, 230, 75 }, g.running_totals)
            for i = 1, 3 do
                assert.is_false(g.barrel_state[i].on_barrel)
            end
            assert.is_nil(g.winner)
        end)

        it("can drive a non-barrel running total negative", function()
            local g = advance_ok(default_advance_opts({
                deltas = { -100, 30, 25 },
                running_totals_before = { 50, 0, 0 },
            }))
            assert.are.equal(-50, g.running_totals[1])
            assert.is_false(g.barrel_state[1].on_barrel)
        end)
    end)

    describe("advance_game() mounting the barrel", function()
        it("does not mount when the post-deal total stays below the threshold", function()
            local g = advance_ok(default_advance_opts({
                deltas = { 9, 0, 0 },
                running_totals_before = { 870, 0, 0 },
            }))
            assert.are.equal(879, g.running_totals[1])
            assert.is_false(g.barrel_state[1].on_barrel)
        end)

        it("mounts the barrel when the post-deal total reaches the threshold exactly", function()
            local g = advance_ok(default_advance_opts({
                deltas = { 10, 0, 0 },
                running_totals_before = { 870, 0, 0 },
                deal_index = 7,
            }))
            assert.are.equal(880, g.running_totals[1])
            assert.is_true(g.barrel_state[1].on_barrel)
            assert.are.equal(7, g.barrel_state[1].mounted_on_deal)
            assert.are.equal(config.barrel.deal_count, g.barrel_state[1].deals_remaining)
        end)

        it(
            "snaps the running total to the threshold even when the deal would have overshot",
            function()
                local g = advance_ok(default_advance_opts({
                    deltas = { 70, 0, 0 },
                    running_totals_before = { 850, 0, 0 },
                    deal_index = 4,
                }))
                assert.are.equal(880, g.running_totals[1])
                assert.is_true(g.barrel_state[1].on_barrel)
                assert.are.equal(4, g.barrel_state[1].mounted_on_deal)
            end
        )

        it("does not mount or win when the deal jumps directly past the target", function()
            -- Player at 800, delta 250 → 1050 ≥ target. Skip the barrel
            -- entirely and win on the spot.
            local g = advance_ok(default_advance_opts({
                deltas = { 250, 0, 0 },
                running_totals_before = { 800, 0, 0 },
                deal_index = 6,
            }))
            assert.are.equal(1050, g.running_totals[1])
            assert.is_false(g.barrel_state[1].on_barrel)
            assert.are.equal(1, g.winner)
        end)
    end)

    describe("advance_game() while on barrel", function()
        it(
            "freezes the running total and decrements deals_remaining when delta is below 120",
            function()
                local g = advance_ok(default_advance_opts({
                    deltas = { 50, 0, 0 },
                    running_totals_before = { 880, 0, 0 },
                    deal_index = 6,
                    barrel_state_before = {
                        { on_barrel = true, mounted_on_deal = 5, deals_remaining = 3 },
                        { on_barrel = false },
                        { on_barrel = false },
                    },
                }))
                assert.are.equal(880, g.running_totals[1])
                assert.is_true(g.barrel_state[1].on_barrel)
                assert.are.equal(5, g.barrel_state[1].mounted_on_deal)
                assert.are.equal(2, g.barrel_state[1].deals_remaining)
            end
        )

        it("ignores a negative delta — score stays frozen at the threshold", function()
            local g = advance_ok(default_advance_opts({
                deltas = { -100, 30, 25 },
                running_totals_before = { 880, 0, 0 },
                deal_index = 7,
                barrel_state_before = {
                    { on_barrel = true, mounted_on_deal = 5, deals_remaining = 2 },
                    { on_barrel = false },
                    { on_barrel = false },
                },
            }))
            assert.are.equal(880, g.running_totals[1])
            assert.is_true(g.barrel_state[1].on_barrel)
            assert.are.equal(1, g.barrel_state[1].deals_remaining)
        end)

        it("wins when delta on barrel is exactly 120", function()
            local g = advance_ok(default_advance_opts({
                deltas = { 120, 0, 0 },
                running_totals_before = { 880, 0, 0 },
                deal_index = 6,
                barrel_state_before = {
                    { on_barrel = true, mounted_on_deal = 5, deals_remaining = 3 },
                    { on_barrel = false },
                    { on_barrel = false },
                },
            }))
            assert.are.equal(config.endgame.target_score, g.running_totals[1])
            assert.is_false(g.barrel_state[1].on_barrel)
            assert.are.equal(1, g.winner)
        end)

        it("wins and caps the running total at the target when delta exceeds 120", function()
            -- Defender on barrel could in theory score cards + a hearts
            -- marriage in one deal (e.g. 60 cards + 100 = 160). The score
            -- was frozen at 880, so the win lands at exactly 1000 — not
            -- 880 + 160.
            local g = advance_ok(default_advance_opts({
                deltas = { 0, 160, 0 },
                running_totals_before = { 0, 880, 0 },
                deal_index = 8,
                barrel_state_before = {
                    { on_barrel = false },
                    { on_barrel = true, mounted_on_deal = 7, deals_remaining = 3 },
                    { on_barrel = false },
                },
            }))
            assert.are.equal(config.endgame.target_score, g.running_totals[2])
            assert.is_false(g.barrel_state[2].on_barrel)
            assert.are.equal(2, g.winner)
        end)

        it("falls off when deals_remaining reaches zero on a low-delta deal", function()
            local g = advance_ok(default_advance_opts({
                deltas = { 50, 30, 25 },
                running_totals_before = { 880, 100, 100 },
                deal_index = 8,
                barrel_state_before = {
                    { on_barrel = true, mounted_on_deal = 5, deals_remaining = 1 },
                    { on_barrel = false },
                    { on_barrel = false },
                },
            }))
            assert.are.equal(
                config.barrel.threshold + config.barrel.fall_off_penalty,
                g.running_totals[1]
            )
            assert.are.equal(760, g.running_totals[1])
            assert.is_false(g.barrel_state[1].on_barrel)
            assert.is_nil(g.barrel_state[1].mounted_on_deal)
            assert.is_nil(g.barrel_state[1].deals_remaining)
            assert.is_nil(g.winner)
        end)

        it("walks a full barrel run without any winning deal", function()
            -- Deal 5: mount.
            local g1 = advance_ok(default_advance_opts({
                deltas = { 30, 0, 0 },
                running_totals_before = { 870, 0, 0 },
                deal_index = 5,
            }))
            assert.are.equal(880, g1.running_totals[1])
            assert.is_true(g1.barrel_state[1].on_barrel)
            assert.are.equal(3, g1.barrel_state[1].deals_remaining)

            -- Deal 6: still on barrel.
            local g2 = advance_ok({
                declarer = 2,
                deal_index = 6,
                deltas = { 50, 0, 0 },
                running_totals_before = g1.running_totals,
                barrel_state_before = g1.barrel_state,
            })
            assert.are.equal(880, g2.running_totals[1])
            assert.are.equal(2, g2.barrel_state[1].deals_remaining)

            -- Deal 7: still on barrel.
            local g3 = advance_ok({
                declarer = 3,
                deal_index = 7,
                deltas = { 0, 0, 0 },
                running_totals_before = g2.running_totals,
                barrel_state_before = g2.barrel_state,
            })
            assert.are.equal(880, g3.running_totals[1])
            assert.are.equal(1, g3.barrel_state[1].deals_remaining)

            -- Deal 8: falls off.
            local g4 = advance_ok({
                declarer = 1,
                deal_index = 8,
                deltas = { 50, 0, 0 },
                running_totals_before = g3.running_totals,
                barrel_state_before = g3.barrel_state,
            })
            assert.are.equal(760, g4.running_totals[1])
            assert.is_false(g4.barrel_state[1].on_barrel)
            assert.is_nil(g4.winner)
        end)
    end)

    describe("advance_game() collision rule", function()
        it("knocks the earlier mounter off when a second player mounts the next deal", function()
            -- Player 1 was already on barrel from deal 5 with 3 deals
            -- remaining. Player 2 mounts in deal 6. After the deal, only
            -- player 2 stays on; player 1 falls off to 760.
            local g = advance_ok(default_advance_opts({
                declarer = 3,
                deal_index = 6,
                deltas = { 0, 30, 0 },
                running_totals_before = { 880, 870, 0 },
                barrel_state_before = {
                    { on_barrel = true, mounted_on_deal = 5, deals_remaining = 3 },
                    { on_barrel = false },
                    { on_barrel = false },
                },
            }))
            assert.is_false(g.barrel_state[1].on_barrel)
            assert.are.equal(760, g.running_totals[1])
            assert.is_true(g.barrel_state[2].on_barrel)
            assert.are.equal(880, g.running_totals[2])
            assert.are.equal(6, g.barrel_state[2].mounted_on_deal)
        end)

        it("breaks a same-deal mount tie in favour of the declarer", function()
            -- Players 1 and 2 both mount in deal 4. Player 2 is declarer
            -- → player 2 stays on; player 1 falls off.
            local g = advance_ok(default_advance_opts({
                declarer = 2,
                deal_index = 4,
                deltas = { 30, 30, 0 },
                running_totals_before = { 870, 870, 0 },
            }))
            assert.is_false(g.barrel_state[1].on_barrel)
            assert.are.equal(760, g.running_totals[1])
            assert.is_true(g.barrel_state[2].on_barrel)
            assert.are.equal(880, g.running_totals[2])
        end)

        it(
            "breaks a same-deal mount tie by lowest player index when no candidate is declarer",
            function()
                -- Players 2 and 3 both mount in deal 4; declarer is
                -- player 1. Lowest-indexed candidate (2) survives.
                local g = advance_ok(default_advance_opts({
                    declarer = 1,
                    deal_index = 4,
                    deltas = { 0, 30, 30 },
                    running_totals_before = { 0, 870, 870 },
                }))
                assert.is_true(g.barrel_state[2].on_barrel)
                assert.are.equal(880, g.running_totals[2])
                assert.is_false(g.barrel_state[3].on_barrel)
                assert.are.equal(760, g.running_totals[3])
            end
        )

        it("leaves the lone barrel survivor untouched when nobody else mounts", function()
            local g = advance_ok(default_advance_opts({
                declarer = 1,
                deal_index = 6,
                deltas = { 50, 30, 25 },
                running_totals_before = { 880, 200, 100 },
                barrel_state_before = {
                    { on_barrel = true, mounted_on_deal = 5, deals_remaining = 3 },
                    { on_barrel = false },
                    { on_barrel = false },
                },
            }))
            assert.is_true(g.barrel_state[1].on_barrel)
            assert.are.equal(880, g.running_totals[1])
            assert.are.equal(2, g.barrel_state[1].deals_remaining)
            assert.are.equal(230, g.running_totals[2])
            assert.are.equal(125, g.running_totals[3])
        end)
    end)

    describe("advance_game() winner determination", function()
        it("does not declare a winner during normal play", function()
            local g = advance_ok(default_advance_opts({
                deltas = { 60, 30, 25 },
                running_totals_before = { 100, 200, 50 },
            }))
            assert.is_nil(g.winner)
        end)

        it("declares a winner when a single player crosses the target", function()
            local g = advance_ok(default_advance_opts({
                declarer = 2,
                deltas = { 30, 100, 25 },
                running_totals_before = { 200, 920, 50 },
                deal_index = 9,
            }))
            assert.are.equal(2, g.winner)
            assert.are.equal(1020, g.running_totals[2])
        end)

        it("declares the declarer the winner on a same-deal tie at the target", function()
            -- Both player 1 (declarer) and player 2 (defender) finish
            -- exactly at 1000 after the deal. Declarer wins.
            local g = advance_ok(default_advance_opts({
                declarer = 1,
                deltas = { 100, 100, 25 },
                running_totals_before = { 900, 900, 50 },
                deal_index = 9,
            }))
            assert.are.equal(1, g.winner)
        end)

        it("breaks a non-declarer tie at the target by highest total then lowest index", function()
            -- Players 2 and 3 both cross 1000; declarer is 1 and did not.
            -- Player 3 has the higher post-deal total → wins.
            local g = advance_ok(default_advance_opts({
                declarer = 1,
                deltas = { -100, 100, 130 },
                running_totals_before = { 200, 900, 900 },
                deal_index = 9,
            }))
            assert.are.equal(3, g.winner)
        end)

        it(
            "falls back to the lowest player index when target-crossing totals are exactly tied",
            function()
                -- Both player 2 and player 3 land at exactly 1010, declarer
                -- is player 1 and did not cross. Lowest-indexed of the
                -- target-crossers (2) wins.
                local g = advance_ok(default_advance_opts({
                    declarer = 1,
                    deltas = { -100, 110, 110 },
                    running_totals_before = { 200, 900, 900 },
                    deal_index = 9,
                }))
                assert.are.equal(2, g.winner)
            end
        )

        it(
            "hands a higher-total non-barrel crosser the win over an on-barrel target-hitter",
            function()
                -- Player 1 was on barrel and scores 130 → wins at the
                -- target (capped at 1000). Player 2 was a defender at
                -- 800 and lands at 1100 in the same deal. Declarer is
                -- player 1, but there is no tie — the higher total
                -- wins outright. Declarer-wins-ties only kicks in when
                -- the totals match.
                local g = advance_ok(default_advance_opts({
                    declarer = 1,
                    deltas = { 130, 300, 0 },
                    running_totals_before = { 880, 800, 0 },
                    deal_index = 8,
                    barrel_state_before = {
                        { on_barrel = true, mounted_on_deal = 6, deals_remaining = 3 },
                        { on_barrel = false },
                        { on_barrel = false },
                    },
                }))
                assert.are.equal(2, g.winner)
                assert.are.equal(config.endgame.target_score, g.running_totals[1])
                assert.are.equal(1100, g.running_totals[2])
            end
        )

        it("breaks an on-barrel/non-barrel tie at the target in the declarer's favour", function()
            -- Player 1 (declarer) on barrel scores 120 → wins at the
            -- target (1000, capped from frozen 880). Player 2 was
            -- at 800 and lands at exactly 1000 in the same deal.
            -- Tie at 1000 → declarer wins.
            local g = advance_ok(default_advance_opts({
                declarer = 1,
                deltas = { 120, 200, 0 },
                running_totals_before = { 880, 800, 0 },
                deal_index = 8,
                barrel_state_before = {
                    { on_barrel = true, mounted_on_deal = 6, deals_remaining = 3 },
                    { on_barrel = false },
                    { on_barrel = false },
                },
            }))
            assert.are.equal(1, g.winner)
            assert.are.equal(config.endgame.target_score, g.running_totals[1])
            assert.are.equal(1000, g.running_totals[2])
        end)
    end)

    describe("advance_game() result shape", function()
        it("tags the state so is_game recognises it", function()
            local g = advance_ok(default_advance_opts())
            assert.is_true(scoring.is_game(g))
        end)

        it("rejects plain tables for is_game", function()
            assert.is_false(scoring.is_game(nil))
            assert.is_false(scoring.is_game(42))
            assert.is_false(scoring.is_game("game"))
            assert.is_false(scoring.is_game({}))
            assert.is_false(scoring.is_game({ running_totals = {} }))
        end)

        it("stamps the schema version", function()
            local g = advance_ok(default_advance_opts())
            assert.are.equal(scoring.SCHEMA_VERSION, g.schema_version)
        end)

        it("retains config, declarer and deal_index for later reads", function()
            local g = advance_ok(default_advance_opts({ declarer = 2, deal_index = 7 }))
            assert.are.equal(config, g.config)
            assert.are.equal(2, g.declarer)
            assert.are.equal(7, g.deal_index)
        end)
    end)

    describe("advance_game() immutability", function()
        it("does not mutate the input opts lists", function()
            local opts = default_advance_opts({
                deltas = { 30, 25, 60 },
                running_totals_before = { 200, 100, 50 },
                barrel_state_before = {
                    { on_barrel = true, mounted_on_deal = 5, deals_remaining = 2 },
                    { on_barrel = false },
                    { on_barrel = false },
                },
                running_totals_before_snapshot = nil,
            })
            advance_ok(opts)
            assert.are.same({ 30, 25, 60 }, opts.deltas)
            assert.are.same({ 200, 100, 50 }, opts.running_totals_before)
            assert.is_true(opts.barrel_state_before[1].on_barrel)
            assert.are.equal(5, opts.barrel_state_before[1].mounted_on_deal)
            assert.are.equal(2, opts.barrel_state_before[1].deals_remaining)
        end)

        it("returns lists independent of the input lists", function()
            local opts = default_advance_opts({
                deltas = { 30, 25, 60 },
                running_totals_before = { 200, 100, 50 },
            })
            local g = advance_ok(opts)
            assert.are_not.equal(opts.running_totals_before, g.running_totals)
            assert.are_not.equal(opts.barrel_state_before, g.barrel_state)
            assert.are_not.equal(opts.barrel_state_before[1], g.barrel_state[1])
        end)
    end)
end)
