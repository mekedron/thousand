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
            assert.is_function(scoring.score_raspassy)
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

        it("rejects negative half_marriage_capture_bonuses", function()
            local result = scoring.score_deal(
                config,
                default_opts({ half_marriage_capture_bonuses = { 0, -1, 0 } })
            )
            assert.is_false(result.ok)
            assert.are.equal("bad_half_marriage_capture_bonuses", result.error.code)
            assert.are.equal(2, result.error.player)
        end)

        it("rejects half_marriage_capture_bonuses of the wrong length", function()
            local result = scoring.score_deal(
                config,
                default_opts({ half_marriage_capture_bonuses = { 0, 0 } })
            )
            assert.is_false(result.ok)
            assert.are.equal("bad_half_marriage_capture_bonuses", result.error.code)
        end)

        it("rejects negative ace_marriage_bonuses", function()
            local result =
                scoring.score_deal(config, default_opts({ ace_marriage_bonuses = { 0, -200, 0 } }))
            assert.is_false(result.ok)
            assert.are.equal("bad_ace_marriage_bonuses", result.error.code)
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
                    weak_hand_threshold = 14,
                    two_nines_in_talon_redeal = "off",
                    misdeal_handling = "standard",
                    misdeal_flat_penalty = 20,
                    all_pass_handling = "redeal",
                    deck_size = "24",
                    cut_deck_nine_jack_penalty = "off",
                },
                talon = {
                    size = 3,
                    distribution = "declarer_takes_then_passes",
                    flip_after_first_round = "off",
                    pass_the_talon = "off",
                    buyback = "off",
                    buyback_penalty = 50,
                    hidden_on_minimum_100 = "off",
                    bad_talon_redeal = "off",
                    bad_talon_threshold = 5,
                    rebuy = "off",
                    rebuy_contract_value = 240,
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
                    blind_bid_success_multiplier = 2,
                    blind_bid_failure_multiplier = 2,
                    re_entry_after_pass = "off",
                    contra = "off",
                    contra_multiplier = 2,
                    redouble_multiplier = 2,
                    forced_bid_concession = "off",
                    forced_bid_concession_preset_ratio = { 0.5, 0.5 },
                    write_off = "off",
                    write_off_split = "half_to_each",
                    no_contract_without_marriage = "off",
                    negative_score_restriction = "off",
                    named_contracts = "off",
                    named_contracts_precedence = { "mizere", "open_hand", "slam" },
                },
                marriages = {
                    values = { hearts = 100, diamonds = 80, clubs = 60, spades = 40 },
                    half_marriage_capture_bonus = "off",
                    half_marriage_capture_bonus_value = 20,
                    trump_activation_timing = "next_trick",
                    marriage_announcement_timing = "on_lead",
                    drowned_marriage = "off",
                    ace_marriage = "off",
                    ace_marriage_value = 200,
                    one_trump_per_deal = "off",
                    trick_required = "on",
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
                    last_trick_bonus_value = 10,
                    slam_bonus = "off",
                    slam_bonus_value = 60,
                    slam_against_penalty = "off",
                    slam_against_penalty_value = 120,
                    lead_trump_after_marriage = "off",
                },
                scoring = {
                    round_to_nearest = 5,
                    actual_points_on_success = "off",
                    defender_contributions = "standard",
                    failed_contract_distribution = "lost",
                    declarer_rounding_before_contract_check = "on",
                },
                opening_game = {
                    golden_deal = "off",
                    golden_deal_count = 3,
                    golden_deal_marriages_doubled = "off",
                    golden_deal_blind_allowed = "off",
                    golden_deal_penalty_doubled = "off",
                    golden_deal_failure_handling = "continue",
                },
                barrel = {
                    threshold = 880,
                    deal_count = 3,
                    fall_off_penalty = -120,
                    pit_lock_in = "off",
                    pit_score = 700,
                    collision_rule = "last_mounter",
                    overshoot_penalty = "off",
                    fall_count_resets_to_zero = "off",
                    reverse_barrel = "off",
                    reverse_barrel_fallback = -760,
                },
                endgame = {
                    target_score = 1000,
                    going_over_target = "win_immediately",
                    tiebreaker = "declarer_wins",
                    dump_truck = "off",
                    dump_truck_threshold = 555,
                },
                specials = {
                    mizere = "off",
                    mizere_contract_value = 120,
                    slam_contract = "off",
                    slam_contract_value = 240,
                    open_hand = "off",
                },
                penalties = {
                    revoke = "standard",
                    revoke_configurable_amount = 120,
                    talon_look = "standard",
                    showing_hand = "standard",
                    zero_tricks = "off",
                    zero_tricks_threshold = 3,
                    zero_tricks_penalty_amount = 120,
                    zero_tricks_declarer_exempt = "off",
                    zero_tricks_golden_deal_doubled = "off",
                    zero_tricks_dark_game_doubled = "off",
                    write_off_streak = "off",
                    write_off_streak_threshold = 3,
                    write_off_streak_penalty_amount = 120,
                    no_win_streak = "off",
                    no_win_streak_threshold = 3,
                    no_win_streak_penalty_amount = 120,
                    cross = "off",
                    cross_penalty_amount = 120,
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

        it("adds half_marriage_capture_bonuses to deal_scores", function()
            local s = score_ok(default_opts({
                captured_points = { 75, 25, 20 },
                half_marriage_capture_bonuses = { 0, 20, 0 },
            }))
            assert.are.equal(0, s.half_marriage_capture_bonuses[1])
            assert.are.equal(20, s.half_marriage_capture_bonuses[2])
            assert.are.equal(0, s.half_marriage_capture_bonuses[3])
            assert.are.equal(25 + 20, s.deal_scores[2])
            assert.are.equal(20, s.deal_scores[3])
        end)

        it("adds ace_marriage_bonuses to deal_scores", function()
            local s = score_ok(default_opts({
                captured_points = { 75, 25, 20 },
                marriage_bonuses = { 0, 0, 0 },
                ace_marriage_bonuses = { 200, 0, 0 },
            }))
            assert.are.equal(200, s.ace_marriage_bonuses[1])
            assert.are.equal(75 + 200, s.deal_scores[1])
        end)

        it("defaults the new bonus arrays to zero when absent", function()
            local s = score_ok(default_opts({
                captured_points = { 75, 25, 20 },
                marriage_bonuses = { 0, 0, 0 },
            }))
            assert.are.same({ 0, 0, 0 }, s.half_marriage_capture_bonuses)
            assert.are.same({ 0, 0, 0 }, s.ace_marriage_bonuses)
        end)
    end)

    describe("score_deal() trick-play bonuses", function()
        it("adds last_trick_bonus to the winning seat's deal_score", function()
            local s = score_ok(default_opts({
                captured_points = { 75, 25, 20 },
                last_trick_bonus = { 0, 10, 0 },
            }))
            assert.are.same({ 0, 10, 0 }, s.last_trick_bonus)
            assert.are.equal(25 + 10, s.deal_scores[2])
        end)

        it("adds slam_bonus to the declarer's deal_score under fixed mode", function()
            local s = score_ok(default_opts({
                bid = 120,
                captured_points = { 120, 0, 0 },
                slam_bonus = { 60, 0, 0 },
            }))
            assert.are.same({ 60, 0, 0 }, s.slam_bonus)
            assert.are.equal(120 + 60, s.deal_scores[1])
        end)

        it("doubles the bid when bid_multiplier=2 (slam_bonus=doubled_bid path)", function()
            -- Declarer takes 120 captured points, bid was 100, multiplier 2.
            -- effective_bid = 200. Declarer made it (deal_scores[1] = 120 < 200
            -- → wait, made_contract should be false then). Let's check the
            -- doubled bid against a deal that *can* meet 2*bid: bid 60, mult 2,
            -- effective_bid 120, declarer deal_score 120 → made.
            local s = score_ok(default_opts({
                bid = 60,
                bid_multiplier = 2,
                captured_points = { 120, 0, 0 },
            }))
            assert.are.equal(2, s.bid_multiplier)
            assert.are.equal(120, s.effective_bid)
            assert.is_true(s.made_contract)
            assert.are.equal(120, s.deltas[1])
        end)

        it("doubles the failure penalty when bid_multiplier=2 fails", function()
            local s = score_ok(default_opts({
                bid = 100,
                bid_multiplier = 2,
                captured_points = { 75, 25, 20 },
            }))
            assert.are.equal(200, s.effective_bid)
            assert.is_false(s.made_contract)
            assert.are.equal(-200, s.deltas[1])
        end)

        it("subtracts slam_against_penalty from declarer when signed negative", function()
            local s = score_ok(default_opts({
                bid = 100,
                captured_points = { 0, 60, 60 },
                slam_against_penalty = { -120, 0, 0 },
            }))
            assert.are.same({ -120, 0, 0 }, s.slam_against_penalty)
            assert.are.equal(0 - 120, s.deal_scores[1])
        end)

        it("rejects bid_multiplier <= 0", function()
            local res = scoring.score_deal(config, default_opts({ bid_multiplier = 0 }))
            assert.is_false(res.ok)
            assert.are.equal("bad_bid_multiplier", res.error.code)
        end)

        it("defaults all three trick-play bonus arrays to zero when absent", function()
            local s = score_ok(default_opts())
            assert.are.same({ 0, 0, 0 }, s.last_trick_bonus)
            assert.are.same({ 0, 0, 0 }, s.slam_bonus)
            assert.are.same({ 0, 0, 0 }, s.slam_against_penalty)
            assert.are.equal(1, s.bid_multiplier)
            assert.are.equal(s.bid, s.effective_bid)
        end)
    end)

    describe("score_deal() penalty arrays", function()
        it("defaults the five penalty arrays to zero when absent", function()
            local s = score_ok(default_opts())
            assert.are.same({ 0, 0, 0 }, s.revoke_penalty)
            assert.are.same({ 0, 0, 0 }, s.talon_look_penalty)
            assert.are.same({ 0, 0, 0 }, s.showing_hand_penalty)
            assert.are.same({ 0, 0, 0 }, s.zero_tricks_penalty)
            assert.are.same({ 0, 0, 0 }, s.cross_penalty)
            assert.is_false(s.suppress_declarer_failed_bid_deduction)
        end)

        it("adds revoke_penalty straight to deltas without changing deal_scores", function()
            -- Declarer makes contract (75 captured >= 75 bid). With a
            -- revoke against the declarer (-120) and the bid
            -- redistributed across two defenders (+60 each), deltas
            -- carry the penalty while deal_scores stay clean.
            local s = score_ok(default_opts({
                bid = 75,
                captured_points = { 75, 25, 20 },
                revoke_penalty = { -120, 60, 60 },
            }))
            assert.are.same({ -120, 60, 60 }, s.revoke_penalty)
            -- deal_scores reflect the rounded captured + bonuses only.
            assert.are.equal(75, s.deal_scores[1])
            assert.are.equal(25, s.deal_scores[2])
            assert.are.equal(20, s.deal_scores[3])
            -- Declarer got +bid (75) on success, then -120 for the revoke.
            assert.are.equal(75 - 120, s.deltas[1])
            -- Defenders got their deal_score plus the revoke share.
            assert.are.equal(25 + 60, s.deltas[2])
            assert.are.equal(20 + 60, s.deltas[3])
        end)

        it("adds zero_tricks_penalty to a defender's delta", function()
            local s = score_ok(default_opts({
                bid = 100,
                captured_points = { 100, 0, 20 },
                zero_tricks_penalty = { 0, -120, 0 },
            }))
            -- Defender 2 took 0 captured + bolt threshold hit.
            assert.are.equal(0 - 120, s.deltas[2])
            assert.are.same({ 0, -120, 0 }, s.zero_tricks_penalty)
        end)

        it("suppresses the declarer's failed-bid deduction when cross is on", function()
            -- Declarer fails (60 < 100). Without suppression,
            -- delta[1] = -100. With suppression and a cross_penalty of
            -- 0 (counter under threshold), delta[1] = 0.
            local s = score_ok(default_opts({
                bid = 100,
                captured_points = { 60, 30, 30 },
                suppress_declarer_failed_bid_deduction = true,
            }))
            assert.is_false(s.made_contract)
            assert.is_true(s.suppress_declarer_failed_bid_deduction)
            assert.are.equal(0, s.deltas[1])
            -- Defender base remains in their deltas.
            assert.are.equal(30, s.deltas[2])
            assert.are.equal(30, s.deltas[3])
        end)

        it("applies cross_penalty on top of suppression when the threshold hits", function()
            -- Same shape but the session emits cross_penalty[1] = -120
            -- because the declarer's cross counter just hit two.
            local s = score_ok(default_opts({
                bid = 100,
                captured_points = { 60, 30, 30 },
                suppress_declarer_failed_bid_deduction = true,
                cross_penalty = { -120, 0, 0 },
            }))
            assert.are.equal(0 - 120, s.deltas[1])
            assert.are.equal(-120, s.running_totals[1] - s.running_totals_before[1])
        end)

        it(
            "preserves failed_contract_distribution for defenders under cross suppression",
            function()
                -- Build a Russian-derived config with split_among_defenders +
                -- cross = on so the defender share is exercised even with
                -- the declarer's side suppressed.
                local json = require("app.json")
                local blob = json.decode(rule_config.to_json(rule_config.canonical_russian))
                blob.scoring.failed_contract_distribution = "split_among_defenders"
                blob.penalties.cross = "on"
                local variant = rule_config.new(blob)
                local res = scoring.score_deal(
                    variant,
                    default_opts({
                        bid = 100,
                        captured_points = { 50, 30, 40 },
                        suppress_declarer_failed_bid_deduction = true,
                    })
                )
                assert.is_true(res.ok)
                local s = res.scoring
                -- Declarer's -bid is suppressed.
                assert.are.equal(0, s.deltas[1])
                -- Defenders get deal_score + their share of the bid.
                assert.are.equal(30 + 50, s.deltas[2])
                assert.are.equal(40 + 50, s.deltas[3])
            end
        )

        it("rejects non-list penalty arrays with bad_<field>", function()
            local res = scoring.score_deal(config, default_opts({ revoke_penalty = "not a list" }))
            assert.is_false(res.ok)
            assert.are.equal("bad_revoke_penalty", res.error.code)
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

    -- Phase 3.6 opening-game / barrel / endgame house-rule pins for
    -- advance_game. Each describe overrides one toggle on the canonical
    -- Russian config and pins the engine math against the documented
    -- rule from docs/variations/house-rules.md. The session-level
    -- integration spec (tests/spec/app/session_endgame_variants_spec)
    -- exercises the same toggles end-to-end through a full deal.
    local json = require("app.json")
    local function with_endgame_overrides(overrides)
        local blob = json.decode(rule_config.to_json(rule_config.canonical_russian))
        overrides = overrides or {}
        for section, fields in pairs(overrides) do
            blob[section] = blob[section] or {}
            for k, v in pairs(fields) do
                blob[section][k] = v
            end
        end
        return rule_config.new(blob)
    end

    local function advance_with(cfg, opts)
        opts = opts or {}
        local final = {
            declarer = opts.declarer or 1,
            deal_index = opts.deal_index or 1,
            deltas = opts.deltas or { 0, 0, 0 },
            running_totals_before = opts.running_totals_before or { 0, 0, 0 },
            barrel_state_before = opts.barrel_state_before or scoring.initial_barrel_state(cfg),
            bid = opts.bid,
            declarer_made_contract = opts.declarer_made_contract,
            effective_target_before = opts.effective_target_before,
            barrel_fall_counts_before = opts.barrel_fall_counts_before,
        }
        local r = scoring.advance_game(cfg, final)
        assert.is_true(
            r.ok,
            "advance_game must succeed (got " .. (r.error and r.error.code or "?") .. ")"
        )
        return r.game
    end

    describe("advance_game() dump_truck", function()
        it("resets a unit landing exactly on +555 to 0 under positive_only", function()
            local cfg = with_endgame_overrides({ endgame = { dump_truck = "positive_only" } })
            local g = advance_with(cfg, {
                deltas = { 25, 0, 0 },
                running_totals_before = { 530, 0, 0 },
            })
            assert.are.equal(0, g.running_totals[1])
            assert.is_true(g.dump_truck_events[1])
            assert.is_false(g.dump_truck_events[2])
        end)

        it("does not fire when total ends near but not on 555", function()
            local cfg = with_endgame_overrides({ endgame = { dump_truck = "positive_only" } })
            local g = advance_with(cfg, {
                deltas = { 24, 0, 0 },
                running_totals_before = { 530, 0, 0 },
            })
            assert.are.equal(554, g.running_totals[1])
            assert.is_false(g.dump_truck_events[1])
        end)

        it("ignores -555 under positive_only", function()
            local cfg = with_endgame_overrides({ endgame = { dump_truck = "positive_only" } })
            local g = advance_with(cfg, {
                deltas = { -25, 0, 0 },
                running_totals_before = { -530, 0, 0 },
            })
            assert.are.equal(-555, g.running_totals[1])
            assert.is_false(g.dump_truck_events[1])
        end)

        it("resets -555 to 0 under both_signs", function()
            local cfg = with_endgame_overrides({ endgame = { dump_truck = "both_signs" } })
            local g = advance_with(cfg, {
                deltas = { -25, 0, 0 },
                running_totals_before = { -530, 0, 0 },
            })
            assert.are.equal(0, g.running_totals[1])
            assert.is_true(g.dump_truck_events[1])
        end)
    end)

    describe("advance_game() pit_lock_in", function()
        it("caps the running total at pit_score on first crossing", function()
            local cfg = with_endgame_overrides({
                barrel = { pit_lock_in = "on", pit_score = 700 },
            })
            local g = advance_with(cfg, {
                deltas = { 200, 0, 0 },
                running_totals_before = { 600, 0, 0 },
            })
            assert.are.equal(700, g.running_totals[1])
            assert.is_true(g.barrel_state[1].pit_locked == true)
            assert.are.equal("pit_locked", g.pit_lock_in_state[1])
        end)

        it("clears the lock when the declarer makes their contract", function()
            local cfg = with_endgame_overrides({
                barrel = { pit_lock_in = "on", pit_score = 700 },
            })
            local g = advance_with(cfg, {
                deltas = { 100, 0, 0 },
                running_totals_before = { 700, 0, 0 },
                barrel_state_before = {
                    { on_barrel = false, pit_locked = true },
                    { on_barrel = false },
                    { on_barrel = false },
                },
                declarer = 1,
                declarer_made_contract = true,
            })
            assert.are.equal(800, g.running_totals[1])
            assert.is_nil(g.barrel_state[1].pit_locked)
            assert.are.equal("cleared_this_deal", g.pit_lock_in_state[1])
        end)

        it("stays capped at pit_score under a defender's positive delta", function()
            local cfg = with_endgame_overrides({
                barrel = { pit_lock_in = "on", pit_score = 700 },
            })
            local g = advance_with(cfg, {
                deltas = { 0, 60, 0 },
                running_totals_before = { 0, 700, 0 },
                barrel_state_before = {
                    { on_barrel = false },
                    { on_barrel = false, pit_locked = true },
                    { on_barrel = false },
                },
                declarer = 1,
                declarer_made_contract = true,
            })
            assert.are.equal(700, g.running_totals[2])
            assert.is_true(g.barrel_state[2].pit_locked == true)
        end)
    end)

    describe("advance_game() overshoot_penalty", function()
        it("replaces fall_off with -bid when bid > closing-gap and the contract failed", function()
            local cfg = with_endgame_overrides({ barrel = { overshoot_penalty = "on" } })
            local g = advance_with(cfg, {
                deltas = { -200, 0, 0 },
                running_totals_before = { 880, 0, 0 },
                barrel_state_before = {
                    { on_barrel = true, mounted_on_deal = 1, deals_remaining = 1 },
                    { on_barrel = false },
                    { on_barrel = false },
                },
                bid = 200,
                declarer_made_contract = false,
                deal_index = 4,
            })
            -- threshold (880) - bid (200) = 680.
            assert.are.equal(680, g.running_totals[1])
            assert.is_true(g.overshoot_penalty_applied[1])
        end)

        it("falls off at the standard rate when bid equals 120", function()
            local cfg = with_endgame_overrides({ barrel = { overshoot_penalty = "on" } })
            local g = advance_with(cfg, {
                deltas = { -120, 0, 0 },
                running_totals_before = { 880, 0, 0 },
                barrel_state_before = {
                    { on_barrel = true, mounted_on_deal = 1, deals_remaining = 1 },
                    { on_barrel = false },
                    { on_barrel = false },
                },
                bid = 120,
                declarer_made_contract = false,
                deal_index = 4,
            })
            assert.are.equal(760, g.running_totals[1])
            assert.is_false(g.overshoot_penalty_applied[1])
        end)
    end)

    describe("advance_game() fall_count tracking", function()
        it("returns zero counters and no fall events on a non-falling deal", function()
            local g = advance_ok(default_advance_opts({
                deltas = { 50, 0, 0 },
                running_totals_before = { 100, 0, 0 },
            }))
            assert.are.same({ false, false, false }, g.barrel_fall_events)
            assert.are.same({ false, false, false }, g.barrel_fall_resets)
            assert.are.same({ 0, 0, 0 }, g.barrel_fall_counts_after)
        end)

        it("increments the per-seat counter on a barrel fall-off", function()
            local g = advance_ok(default_advance_opts({
                deltas = { 50, 0, 0 },
                running_totals_before = { 880, 0, 0 },
                deal_index = 8,
                barrel_state_before = {
                    { on_barrel = true, mounted_on_deal = 5, deals_remaining = 1 },
                    { on_barrel = false },
                    { on_barrel = false },
                },
            }))
            assert.is_true(g.barrel_fall_events[1])
            assert.is_false(g.barrel_fall_events[2])
            assert.is_false(g.barrel_fall_events[3])
            assert.are.same({ false, false, false }, g.barrel_fall_resets)
            assert.are.same({ 1, 0, 0 }, g.barrel_fall_counts_after)
            -- Standard fall-off behaviour preserved when reset toggle is off.
            assert.are.equal(760, g.running_totals[1])
        end)

        it("threads barrel_fall_counts_before through unchanged for non-falling seats", function()
            local g = advance_ok(default_advance_opts({
                deltas = { 50, 0, 0 },
                running_totals_before = { 100, 0, 0 },
                barrel_fall_counts_before = { 2, 1, 0 },
            }))
            assert.are.same({ 2, 1, 0 }, g.barrel_fall_counts_after)
        end)

        it("defaults barrel_fall_counts_before to zeros when missing", function()
            local g = advance_ok(default_advance_opts({
                deltas = { 50, 0, 0 },
                running_totals_before = { 100, 0, 0 },
                -- no barrel_fall_counts_before field
            }))
            assert.are.same({ 0, 0, 0 }, g.barrel_fall_counts_after)
        end)
    end)

    describe("advance_game() fall_count_resets_to_zero", function()
        it("leaves fall behaviour unchanged under 'off' even when the counter is high", function()
            local g = advance_ok(default_advance_opts({
                deltas = { 50, 0, 0 },
                running_totals_before = { 880, 0, 0 },
                deal_index = 8,
                barrel_state_before = {
                    { on_barrel = true, mounted_on_deal = 5, deals_remaining = 1 },
                    { on_barrel = false },
                    { on_barrel = false },
                },
                barrel_fall_counts_before = { 2, 0, 0 },
            }))
            assert.are.equal(760, g.running_totals[1])
            assert.are.same({ 3, 0, 0 }, g.barrel_fall_counts_after)
            assert.are.same({ false, false, false }, g.barrel_fall_resets)
        end)

        it("first and second falls under 'on' behave as standard fall-off", function()
            local cfg = with_endgame_overrides({
                barrel = { fall_count_resets_to_zero = "on" },
            })
            local g1 = advance_with(cfg, {
                deltas = { 50, 0, 0 },
                running_totals_before = { 880, 0, 0 },
                deal_index = 8,
                barrel_state_before = {
                    { on_barrel = true, mounted_on_deal = 5, deals_remaining = 1 },
                    { on_barrel = false },
                    { on_barrel = false },
                },
                barrel_fall_counts_before = { 0, 0, 0 },
            })
            assert.are.equal(760, g1.running_totals[1])
            assert.is_false(g1.barrel_fall_resets[1])
            assert.are.same({ 1, 0, 0 }, g1.barrel_fall_counts_after)

            local g2 = advance_with(cfg, {
                deltas = { 50, 0, 0 },
                running_totals_before = { 880, 0, 0 },
                deal_index = 12,
                barrel_state_before = {
                    { on_barrel = true, mounted_on_deal = 9, deals_remaining = 1 },
                    { on_barrel = false },
                    { on_barrel = false },
                },
                barrel_fall_counts_before = { 1, 0, 0 },
            })
            assert.are.equal(760, g2.running_totals[1])
            assert.is_false(g2.barrel_fall_resets[1])
            assert.are.same({ 2, 0, 0 }, g2.barrel_fall_counts_after)
        end)

        it("zeroes the running total and resets the counter on the third fall", function()
            local cfg = with_endgame_overrides({
                barrel = { fall_count_resets_to_zero = "on" },
            })
            local g = advance_with(cfg, {
                deltas = { 50, 0, 0 },
                running_totals_before = { 880, 0, 0 },
                deal_index = 16,
                barrel_state_before = {
                    { on_barrel = true, mounted_on_deal = 13, deals_remaining = 1 },
                    { on_barrel = false },
                    { on_barrel = false },
                },
                barrel_fall_counts_before = { 2, 0, 0 },
            })
            assert.are.equal(0, g.running_totals[1])
            assert.is_false(g.barrel_state[1].on_barrel)
            assert.is_true(g.barrel_fall_resets[1])
            assert.are.same({ 0, 0, 0 }, g.barrel_fall_counts_after)
        end)

        it("third-fall reset takes precedence over overshoot_penalty for the declarer", function()
            local cfg = with_endgame_overrides({
                barrel = {
                    overshoot_penalty = "on",
                    fall_count_resets_to_zero = "on",
                },
            })
            local g = advance_with(cfg, {
                deltas = { -200, 0, 0 },
                running_totals_before = { 880, 0, 0 },
                barrel_state_before = {
                    { on_barrel = true, mounted_on_deal = 13, deals_remaining = 1 },
                    { on_barrel = false },
                    { on_barrel = false },
                },
                bid = 200,
                declarer_made_contract = false,
                deal_index = 16,
                barrel_fall_counts_before = { 2, 0, 0 },
            })
            -- Third-fall reset wins → running total zeroed; overshoot
            -- penalty NOT applied.
            assert.are.equal(0, g.running_totals[1])
            assert.is_true(g.barrel_fall_resets[1])
            assert.is_false(g.overshoot_penalty_applied[1])
            assert.are.same({ 0, 0, 0 }, g.barrel_fall_counts_after)
        end)

        it(
            "increments both partners' counters and resets together when their unit falls",
            function()
                local cfg = rule_config.builtins.four_player_a
                cfg = (function()
                    local blob = require("dkjson").decode(rule_config.to_json(cfg))
                    blob.barrel.fall_count_resets_to_zero = "on"
                    return rule_config.new(blob)
                end)()
                local g = advance_with(cfg, {
                    deltas = { 50, 0, 0, 0 },
                    running_totals_before = { 880, 880, 0, 0 },
                    deal_index = 8,
                    barrel_state_before = {
                        { on_barrel = true, mounted_on_deal = 5, deals_remaining = 1 },
                        { on_barrel = true, mounted_on_deal = 5, deals_remaining = 1 },
                        { on_barrel = false },
                        { on_barrel = false },
                    },
                    barrel_fall_counts_before = { 2, 2, 0, 0 },
                })
                -- Partnership: seats 1 & 3 vs 2 & 4 in four_player_a.
                -- The unit holding seats 1+3 falls; both partners' counts
                -- reset and their shared running total zeros.
                assert.are.equal(0, g.running_totals[1])
                assert.are.equal(0, g.running_totals[3])
                assert.is_true(g.barrel_fall_resets[1])
                assert.is_true(g.barrel_fall_resets[3])
                assert.are.equal(0, g.barrel_fall_counts_after[1])
                assert.are.equal(0, g.barrel_fall_counts_after[3])
            end
        )
    end)

    describe("advance_game() collision_rule", function()
        it("first_mounter keeps the earliest mount and falls the rest off", function()
            local cfg = with_endgame_overrides({ barrel = { collision_rule = "first_mounter" } })
            local g = advance_with(cfg, {
                deltas = { 0, 0, 80 },
                running_totals_before = { 880, 880, 800 },
                barrel_state_before = {
                    { on_barrel = true, mounted_on_deal = 1, deals_remaining = 2 },
                    { on_barrel = true, mounted_on_deal = 2, deals_remaining = 1 },
                    { on_barrel = false },
                },
                deal_index = 3,
                declarer = 3,
            })
            -- Seat 1 mounted first → survives. Seat 2 falls off (760).
            -- Seat 3 mounts now → falls off too (only first mounter
            -- survives).
            assert.is_true(g.barrel_state[1].on_barrel)
            assert.are.equal(880, g.running_totals[1])
            assert.is_false(g.barrel_state[2].on_barrel)
            assert.are.equal(760, g.running_totals[2])
            assert.is_false(g.barrel_state[3].on_barrel)
            assert.are.equal(760, g.running_totals[3])
        end)

        it("all_collide_fall_off knocks every colliding unit off", function()
            local cfg = with_endgame_overrides({
                barrel = { collision_rule = "all_collide_fall_off" },
            })
            local g = advance_with(cfg, {
                deltas = { 0, 80, 0 },
                running_totals_before = { 880, 800, 0 },
                barrel_state_before = {
                    { on_barrel = true, mounted_on_deal = 1, deals_remaining = 2 },
                    { on_barrel = false },
                    { on_barrel = false },
                },
                deal_index = 2,
                declarer = 2,
            })
            assert.is_false(g.barrel_state[1].on_barrel)
            assert.are.equal(760, g.running_totals[1])
            assert.is_false(g.barrel_state[2].on_barrel)
            assert.are.equal(760, g.running_totals[2])
        end)

        it("coexist leaves every on-barrel unit mounted with its own countdown", function()
            local cfg = with_endgame_overrides({
                barrel = { collision_rule = "coexist" },
            })
            local g = advance_with(cfg, {
                deltas = { 0, 80, 80 },
                running_totals_before = { 880, 800, 800 },
                barrel_state_before = {
                    { on_barrel = true, mounted_on_deal = 1, deals_remaining = 2 },
                    { on_barrel = false },
                    { on_barrel = false },
                },
                deal_index = 2,
                declarer = 1,
            })
            -- Seat 1 was already on the barrel; seats 2 and 3 reach
            -- 880 in this deal. Under `coexist` no eviction happens —
            -- all three stay mounted, each with its own countdown.
            assert.is_true(g.barrel_state[1].on_barrel)
            assert.are.equal(880, g.running_totals[1])
            assert.is_true(g.barrel_state[2].on_barrel)
            assert.are.equal(880, g.running_totals[2])
            assert.is_true(g.barrel_state[3].on_barrel)
            assert.are.equal(880, g.running_totals[3])
        end)
    end)

    describe("advance_game() dump_truck_threshold", function()
        it("fires at the configured threshold instead of the default 555", function()
            local cfg = with_endgame_overrides({
                endgame = { dump_truck = "positive_only", dump_truck_threshold = 550 },
            })
            local g = advance_with(cfg, {
                deltas = { 50, 0, 0 },
                running_totals_before = { 500, 0, 0 },
            })
            assert.are.equal(0, g.running_totals[1])
            assert.is_true(g.dump_truck_events[1])
        end)

        it("does not fire on the legacy 555 when the threshold has moved", function()
            local cfg = with_endgame_overrides({
                endgame = { dump_truck = "positive_only", dump_truck_threshold = 550 },
            })
            local g = advance_with(cfg, {
                deltas = { 55, 0, 0 },
                running_totals_before = { 500, 0, 0 },
            })
            assert.are.equal(555, g.running_totals[1])
            assert.is_false(g.dump_truck_events[1] or false)
        end)

        it("both_signs branch zeroes on the negative threshold mirror", function()
            local cfg = with_endgame_overrides({
                endgame = { dump_truck = "both_signs", dump_truck_threshold = 700 },
            })
            local g = advance_with(cfg, {
                deltas = { 0, 0, -100 },
                running_totals_before = { 0, 0, -600 },
                declarer = 3,
                declarer_made_contract = false,
            })
            assert.are.equal(0, g.running_totals[3])
            assert.is_true(g.dump_truck_events[3])
        end)
    end)

    describe("advance_game() going_over_target", function()
        it("exact_only caps a unit that overshoots target at target - 1", function()
            local cfg = with_endgame_overrides({ endgame = { going_over_target = "exact_only" } })
            local g = advance_with(cfg, {
                deltas = { 30, 0, 0 },
                running_totals_before = { 990, 0, 0 },
            })
            assert.are.equal(999, g.running_totals[1])
            assert.is_nil(g.winner)
            assert.is_true(g.going_over_target_capped[1])
        end)

        it("exact_only declares a winner on an exact landing", function()
            local cfg = with_endgame_overrides({ endgame = { going_over_target = "exact_only" } })
            local g = advance_with(cfg, {
                deltas = { 10, 0, 0 },
                running_totals_before = { 990, 0, 0 },
            })
            assert.are.equal(1000, g.running_totals[1])
            assert.are.equal(1, g.winner)
        end)
    end)

    describe("advance_game() tiebreaker", function()
        it("high_score breaks a tie by lowest seat (no declarer favouritism)", function()
            local cfg = with_endgame_overrides({ endgame = { tiebreaker = "high_score" } })
            local g = advance_with(cfg, {
                declarer = 3,
                deltas = { 60, 60, 60 },
                running_totals_before = { 950, 950, 940 },
            })
            -- Seats 1 and 2 both end at 1010, declarer (3) ends at
            -- 1000. Highest is 1010 (seats 1 and 2 tied); under
            -- high_score the lowest seat (1) wins, NOT the declarer.
            assert.are.equal(1, g.winner)
        end)

        it("continuation suppresses the winner and bumps the target by +500", function()
            local cfg = with_endgame_overrides({ endgame = { tiebreaker = "continuation" } })
            local g = advance_with(cfg, {
                declarer = 1,
                deltas = { 60, 60, 0 },
                running_totals_before = { 950, 950, 0 },
            })
            assert.is_nil(g.winner)
            assert.is_true(g.tiebreaker_continuation_event)
            assert.are.equal(1000, g.effective_target_before)
            assert.are.equal(1500, g.effective_target_after)
            -- Tied units capped at target - 1 = 999.
            assert.are.equal(999, g.running_totals[1])
            assert.are.equal(999, g.running_totals[2])
        end)
    end)

    describe("advance_game() reverse_barrel", function()
        it("mounts a unit dropping to -threshold or below", function()
            local cfg = with_endgame_overrides({ barrel = { reverse_barrel = "on" } })
            local g = advance_with(cfg, {
                deltas = { -80, 0, 0 },
                running_totals_before = { -800, 0, 0 },
            })
            assert.are.equal(-880, g.running_totals[1])
            assert.is_true(g.barrel_state[1].on_reverse_barrel == true)
            assert.are.equal(3, g.barrel_state[1].reverse_deals_remaining)
        end)

        it("falls back to reverse_barrel_fallback after deals_remaining hits 0", function()
            local cfg = with_endgame_overrides({
                barrel = { reverse_barrel = "on", reverse_barrel_fallback = -760 },
            })
            local g = advance_with(cfg, {
                deltas = { 0, 0, 0 },
                running_totals_before = { -880, 0, 0 },
                barrel_state_before = {
                    {
                        on_barrel = false,
                        on_reverse_barrel = true,
                        reverse_mounted_on_deal = 1,
                        reverse_deals_remaining = 1,
                    },
                    { on_barrel = false },
                    { on_barrel = false },
                },
                deal_index = 4,
            })
            assert.are.equal(-760, g.running_totals[1])
            assert.is_nil(g.barrel_state[1].on_reverse_barrel)
        end)

        it("eliminates a unit that drops to -target", function()
            local cfg = with_endgame_overrides({ barrel = { reverse_barrel = "on" } })
            local g = advance_with(cfg, {
                deltas = { -120, 0, 0 },
                running_totals_before = { -880, 0, 0 },
                barrel_state_before = {
                    {
                        on_barrel = false,
                        on_reverse_barrel = true,
                        reverse_mounted_on_deal = 1,
                        reverse_deals_remaining = 2,
                    },
                    { on_barrel = false },
                    { on_barrel = false },
                },
                deal_index = 3,
            })
            assert.are.equal(-1000, g.running_totals[1])
            assert.is_true(g.eliminated[1])
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

    describe("score_raspassy()", function()
        it("rejects a non-RuleConfig", function()
            for _, bad in ipairs({ 42, "config", {}, true }) do
                local result = scoring.score_raspassy(bad, {
                    captured_points = { 0, 0, 0 },
                    running_totals = { 0, 0, 0 },
                })
                assert.is_false(result.ok)
                assert.are.equal("not_a_rule_config", result.error.code)
            end
        end)

        it("rejects a non-table opts", function()
            local result = scoring.score_raspassy(config, "nope")
            assert.is_false(result.ok)
            assert.are.equal("bad_opts", result.error.code)
        end)

        it("rejects negative captured_points entries", function()
            local result = scoring.score_raspassy(config, {
                captured_points = { 50, -1, 50 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_false(result.ok)
            assert.are.equal("bad_captured_points", result.error.code)
        end)

        it("rejects captured-point sums that exceed the deck total", function()
            local result = scoring.score_raspassy(config, {
                captured_points = { 60, 60, 60 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_false(result.ok)
            assert.are.equal("captured_points_exceed_deck", result.error.code)
        end)

        it("negates each rounded captured-points total at zero captures", function()
            local result = scoring.score_raspassy(config, {
                captured_points = { 0, 0, 0 },
                running_totals = { 100, 50, 0 },
            })
            assert.is_true(result.ok)
            assert.are.same({ 0, 0, 0 }, result.scoring.deltas)
            assert.are.same({ 100, 50, 0 }, result.scoring.running_totals)
            assert.are.same({ 0, 0, 0 }, result.scoring.deal_scores)
        end)

        it("negates each rounded captured-points total at a mixed split", function()
            -- 73 rounds to 75; 22 rounds to 20; 25 stays at 25. Sum 120.
            local result = scoring.score_raspassy(config, {
                captured_points = { 73, 22, 25 },
                running_totals = { 200, 200, 200 },
            })
            assert.is_true(result.ok)
            assert.are.same({ -75, -20, -25 }, result.scoring.deltas)
            assert.are.same({ 75, 20, 25 }, result.scoring.deal_scores)
            assert.are.same({ 125, 180, 175 }, result.scoring.running_totals)
        end)

        it("negates the full deck when one player took every trick", function()
            local result = scoring.score_raspassy(config, {
                captured_points = { 120, 0, 0 },
                running_totals = { 500, 500, 500 },
            })
            assert.is_true(result.ok)
            assert.are.same({ -120, 0, 0 }, result.scoring.deltas)
            assert.are.same({ 380, 500, 500 }, result.scoring.running_totals)
        end)

        it("respects scoring.round_to_nearest = 10 (coarse house rule)", function()
            -- Build a config with round_to_nearest = 10. 73 rounds to 70.
            local s = rule_config.to_json(config)
            local res = rule_config.from_json(s)
            assert.is_true(res.ok)
            local sc = res.config.scoring
            local round_before_check = sc.declarer_rounding_before_contract_check
            local blob = {
                schema_version = 1,
                cards = res.config.cards,
                players = res.config.players,
                dealing = res.config.dealing,
                talon = res.config.talon,
                bidding = res.config.bidding,
                marriages = res.config.marriages,
                tricks = res.config.tricks,
                scoring = {
                    round_to_nearest = 10,
                    actual_points_on_success = sc.actual_points_on_success,
                    defender_contributions = sc.defender_contributions,
                    failed_contract_distribution = sc.failed_contract_distribution,
                    declarer_rounding_before_contract_check = round_before_check,
                },
                opening_game = res.config.opening_game,
                barrel = res.config.barrel,
                endgame = res.config.endgame,
                specials = res.config.specials,
                penalties = res.config.penalties,
            }
            local coarse_config = rule_config.new(blob)
            local result = scoring.score_raspassy(coarse_config, {
                captured_points = { 73, 22, 25 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(result.ok)
            -- 73 → 70; 22 → 20; 25 → 30 (half-up rounding).
            assert.are.same({ -70, -20, -30 }, result.scoring.deltas)
        end)

        it("zeroes the marriage_bonuses and made_contract fields", function()
            local result = scoring.score_raspassy(config, {
                captured_points = { 40, 40, 40 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(result.ok)
            assert.are.same({ 0, 0, 0 }, result.scoring.marriage_bonuses)
            assert.is_nil(result.scoring.declarer)
            assert.is_nil(result.scoring.made_contract)
            assert.is_true(result.scoring.raspassy)
        end)

        it("pools partner deltas under partnership_mode = fixed_across_table", function()
            local partnership_config = rule_config.builtins.four_player_b
            local result = scoring.score_raspassy(partnership_config, {
                captured_points = { 30, 30, 30, 30 },
                running_totals = { 0, 0, 0, 0 },
            })
            assert.is_true(result.ok)
            local s = result.scoring
            assert.are.same({ 1, 2, 1, 2 }, s.sides)
            assert.are.same({ -30, -30, -30, -30 }, s.deltas)
            assert.are.same({ -60, -60 }, s.side_deltas)
        end)
    end)

    describe("partnership_mode = fixed_across_table", function()
        local partnership_config = rule_config.builtins.four_player_b

        it("pools captured points and bonuses by side for the contract check", function()
            -- Declarer is seat 1 (side 1). Side 1 deal-pool is 50 + 20 =
            -- 70 captured points. Bid is 100. The pool falls short →
            -- contract failed.
            local result = scoring.score_deal(partnership_config, {
                declarer = 1,
                bid = 100,
                captured_points = { 50, 30, 20, 20 },
                marriage_bonuses = { 0, 0, 0, 0 },
                running_totals = { 0, 0, 0, 0 },
            })
            assert.is_true(result.ok)
            local s = result.scoring
            assert.is_table(s.sides)
            assert.are.equal(1, s.sides[1])
            assert.are.equal(2, s.sides[2])
            assert.are.equal(70, s.side_deal_scores[1])
            assert.are.equal(50, s.side_deal_scores[2])
            assert.is_false(s.made_contract)
            assert.are.equal(-100, s.deltas[1])
            assert.are.equal(0, s.deltas[3]) -- partner contributes 0 at the seat level
        end)

        it("credits the side with +bid when the partnership pool meets the bid", function()
            -- Side 1 pool = 60 + 60 = 120 ≥ 100. Contract made.
            local result = scoring.score_deal(partnership_config, {
                declarer = 1,
                bid = 100,
                captured_points = { 60, 0, 60, 0 },
                marriage_bonuses = { 0, 0, 0, 0 },
                running_totals = { 0, 0, 0, 0 },
            })
            assert.is_true(result.ok)
            local s = result.scoring
            assert.is_true(s.made_contract)
            assert.are.equal(100, s.deltas[1])
            assert.are.equal(0, s.deltas[3])
            assert.are.equal(100, s.side_deltas[1])
        end)

        it("propagates side-level barrel and winner through advance_game", function()
            local g = scoring.advance_game(partnership_config, {
                declarer = 1,
                deal_index = 1,
                deltas = { 100, 0, 0, 0 },
                running_totals_before = { 900, 900, 900, 900 },
                barrel_state_before = scoring.initial_barrel_state(partnership_config),
            }).game
            assert.is_table(g.sides)
            assert.are.equal(1, g.winning_side)
            assert.are.equal(1, g.winner)
            -- Partner seats end the deal at the same side total.
            assert.are.equal(g.running_totals[1], g.running_totals[3])
        end)
    end)

    -- Phase 3.6 scoring house-rule coverage. Each describe drives the
    -- engine through a non-default value of one toggle and pins the
    -- per-seat deltas + the new echoed fields on the result state.
    -- Reuses the json-round-trip helper imported at the top of the
    -- advance_game endgame variants block.
    local function with_scoring_overrides(overrides)
        local blob = json.decode(rule_config.to_json(rule_config.canonical_russian))
        overrides = overrides or {}
        for section, fields in pairs(overrides) do
            blob[section] = blob[section] or {}
            for k, v in pairs(fields) do
                blob[section][k] = v
            end
        end
        return rule_config.new(blob)
    end

    describe("scoring.actual_points_on_success", function()
        it("scores max(bid, deal_score) when on and deal_score exceeds bid", function()
            local cfg = with_scoring_overrides({ scoring = { actual_points_on_success = "on" } })
            local r = scoring.score_deal(cfg, {
                declarer = 1,
                bid = 100,
                captured_points = { 75, 25, 20 },
                marriage_bonuses = { 100, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(r.ok)
            -- declarer captured 75 → 75 + marriage 100 = 175 ≥ bid 100;
            -- success_payout becomes 175 instead of 100.
            assert.is_true(r.scoring.made_contract)
            assert.are.equal(175, r.scoring.success_payout)
            assert.are.equal(175, r.scoring.deltas[1])
        end)

        it("falls back to the bid when deal_score is below the bid", function()
            local cfg = with_scoring_overrides({ scoring = { actual_points_on_success = "on" } })
            local r = scoring.score_deal(cfg, {
                declarer = 1,
                bid = 100,
                captured_points = { 100, 10, 10 },
                marriage_bonuses = { 0, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(r.ok)
            -- 100 captured = 100 (rounded). deal_score equals bid → no
            -- override; success_payout stays at the bid.
            assert.is_true(r.scoring.made_contract)
            assert.are.equal(100, r.scoring.success_payout)
            assert.are.equal(100, r.scoring.deltas[1])
        end)

        it("does not boost the loss path under failure", function()
            local cfg = with_scoring_overrides({ scoring = { actual_points_on_success = "on" } })
            local r = scoring.score_deal(cfg, {
                declarer = 1,
                bid = 120,
                captured_points = { 50, 40, 30 },
                marriage_bonuses = { 0, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(r.ok)
            -- 50 captured + 0 marriage = 50 < 120 → fails; the loss
            -- path always uses effective_bid.
            assert.is_false(r.scoring.made_contract)
            assert.are.equal(-120, r.scoring.deltas[1])
        end)

        it("leaves declarer at the bid when the toggle is off (parity)", function()
            local r = scoring.score_deal(config, {
                declarer = 1,
                bid = 100,
                captured_points = { 75, 25, 20 },
                marriage_bonuses = { 100, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(r.ok)
            assert.are.equal(100, r.scoring.success_payout)
            assert.are.equal(100, r.scoring.deltas[1])
        end)
    end)

    describe("scoring.defender_contributions", function()
        it("pools defender deal_scores under pooled mode", function()
            local cfg = with_scoring_overrides({ scoring = { defender_contributions = "pooled" } })
            local r = scoring.score_deal(cfg, {
                declarer = 1,
                bid = 120,
                captured_points = { 50, 40, 30 },
                marriage_bonuses = { 0, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(r.ok)
            -- Defenders captured 40 + 30 = 70; pooled split → 35/35.
            -- (lowest-numbered defender absorbs the remainder; here pool
            -- is even so both get 35.)
            assert.are.equal(70, r.scoring.defender_pool_total)
            assert.are.equal(35, r.scoring.deltas[2])
            assert.are.equal(35, r.scoring.deltas[3])
            -- Declarer fails 120 → -120.
            assert.are.equal(-120, r.scoring.deltas[1])
        end)

        it("credits remainder to lowest-numbered defender on uneven pool", function()
            local cfg = with_scoring_overrides({ scoring = { defender_contributions = "pooled" } })
            local r = scoring.score_deal(cfg, {
                declarer = 1,
                bid = 120,
                captured_points = { 50, 23, 22 },
                marriage_bonuses = { 0, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(r.ok)
            -- 23 → 25; 22 → 20. Pool = 45; floor(45/2)=22, remainder 1
            -- → seat 2 gets 23, seat 3 gets 22.
            assert.are.equal(45, r.scoring.defender_pool_total)
            assert.are.equal(23, r.scoring.deltas[2])
            assert.are.equal(22, r.scoring.deltas[3])
        end)

        it("keeps standard mode crediting each defender their own", function()
            local cfg =
                with_scoring_overrides({ scoring = { defender_contributions = "standard" } })
            local r = scoring.score_deal(cfg, {
                declarer = 1,
                bid = 120,
                captured_points = { 50, 40, 30 },
                marriage_bonuses = { 0, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(r.ok)
            assert.is_nil(r.scoring.defender_pool_total)
            assert.are.equal(40, r.scoring.deltas[2])
            assert.are.equal(30, r.scoring.deltas[3])
        end)
    end)

    describe("scoring.failed_contract_distribution", function()
        it("adds 0 to defenders under lost mode (default)", function()
            local r = scoring.score_deal(config, {
                declarer = 1,
                bid = 120,
                captured_points = { 50, 40, 30 },
                marriage_bonuses = { 0, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(r.ok)
            assert.is_false(r.scoring.made_contract)
            assert.are.same({ 0, 0, 0 }, r.scoring.failed_contract_distribution_extras)
            assert.are.equal(40, r.scoring.deltas[2])
            assert.are.equal(30, r.scoring.deltas[3])
        end)

        it("splits the bid equally under split_among_defenders", function()
            local cfg = with_scoring_overrides({
                scoring = { failed_contract_distribution = "split_among_defenders" },
            })
            local r = scoring.score_deal(cfg, {
                declarer = 1,
                bid = 100,
                captured_points = { 50, 40, 30 },
                marriage_bonuses = { 0, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(r.ok)
            -- Declarer fails 100; defender share = 50 each.
            assert.is_false(r.scoring.made_contract)
            assert.are.equal(50, r.scoring.failed_contract_distribution_extras[2])
            assert.are.equal(50, r.scoring.failed_contract_distribution_extras[3])
            assert.are.equal(40 + 50, r.scoring.deltas[2])
            assert.are.equal(30 + 50, r.scoring.deltas[3])
        end)

        it("credits the remainder to lowest-numbered defender on uneven split", function()
            local cfg = with_scoring_overrides({
                scoring = { failed_contract_distribution = "split_among_defenders" },
            })
            -- bid 105 ÷ 2 defenders = 52 with remainder 1 → seat 2 gets
            -- 53, seat 3 gets 52.
            local r = scoring.score_deal(cfg, {
                declarer = 1,
                bid = 105,
                captured_points = { 50, 40, 30 },
                marriage_bonuses = { 0, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(r.ok)
            assert.are.equal(53, r.scoring.failed_contract_distribution_extras[2])
            assert.are.equal(52, r.scoring.failed_contract_distribution_extras[3])
        end)

        it("gives every defender the full bid under each_defender_full", function()
            local cfg = with_scoring_overrides({
                scoring = { failed_contract_distribution = "each_defender_full" },
            })
            local r = scoring.score_deal(cfg, {
                declarer = 1,
                bid = 100,
                captured_points = { 50, 40, 30 },
                marriage_bonuses = { 0, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(r.ok)
            assert.are.equal(100, r.scoring.failed_contract_distribution_extras[2])
            assert.are.equal(100, r.scoring.failed_contract_distribution_extras[3])
            assert.are.equal(40 + 100, r.scoring.deltas[2])
            assert.are.equal(30 + 100, r.scoring.deltas[3])
        end)

        it("mirrors forced_bid_concession = equal_split", function()
            local cfg = with_scoring_overrides({
                scoring = { failed_contract_distribution = "mirrors_forced_concession" },
                bidding = { forced_bid_concession = "equal_split" },
            })
            local r = scoring.score_deal(cfg, {
                declarer = 1,
                bid = 100,
                captured_points = { 50, 40, 30 },
                marriage_bonuses = { 0, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(r.ok)
            assert.are.equal(50, r.scoring.failed_contract_distribution_extras[2])
            assert.are.equal(50, r.scoring.failed_contract_distribution_extras[3])
        end)

        it("mirrors forced_bid_concession = preset_ratio", function()
            local cfg = with_scoring_overrides({
                scoring = { failed_contract_distribution = "mirrors_forced_concession" },
                bidding = {
                    forced_bid_concession = "preset_ratio",
                    forced_bid_concession_preset_ratio = { 0.6, 0.4 },
                },
            })
            local r = scoring.score_deal(cfg, {
                declarer = 1,
                bid = 100,
                captured_points = { 50, 40, 30 },
                marriage_bonuses = { 0, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(r.ok)
            -- 100 × 0.6 = 60; 100 × 0.4 = 40. Total credited = 100.
            assert.are.equal(60, r.scoring.failed_contract_distribution_extras[2])
            assert.are.equal(40, r.scoring.failed_contract_distribution_extras[3])
        end)

        it("falls back to lost when forced_bid_concession is off under mirrors", function()
            local cfg = with_scoring_overrides({
                scoring = { failed_contract_distribution = "mirrors_forced_concession" },
                bidding = { forced_bid_concession = "off" },
            })
            local r = scoring.score_deal(cfg, {
                declarer = 1,
                bid = 100,
                captured_points = { 50, 40, 30 },
                marriage_bonuses = { 0, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(r.ok)
            assert.are.same({ 0, 0, 0 }, r.scoring.failed_contract_distribution_extras)
        end)

        it("does not distribute under success", function()
            local cfg = with_scoring_overrides({
                scoring = { failed_contract_distribution = "split_among_defenders" },
            })
            local r = scoring.score_deal(cfg, {
                declarer = 1,
                bid = 100,
                captured_points = { 75, 25, 20 },
                marriage_bonuses = { 100, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(r.ok)
            assert.is_true(r.scoring.made_contract)
            assert.are.same({ 0, 0, 0 }, r.scoring.failed_contract_distribution_extras)
        end)
    end)

    describe("scoring.declarer_rounding_before_contract_check", function()
        it("rounds before checking under on (canonical default)", function()
            -- 118 captured + 0 marriage. on → round to 120; meets bid 120.
            local r = scoring.score_deal(config, {
                declarer = 1,
                bid = 120,
                captured_points = { 118, 2, 0 },
                marriage_bonuses = { 0, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(r.ok)
            assert.is_true(r.scoring.made_contract)
            assert.are.equal(120, r.scoring.contract_check_value)
            assert.are.equal(120, r.scoring.deltas[1])
        end)

        it("uses raw captured under off (strict tournament)", function()
            local cfg = with_scoring_overrides({
                scoring = { declarer_rounding_before_contract_check = "off" },
            })
            -- 118 captured + 0 marriage = 118 raw < 120 → fails.
            local r = scoring.score_deal(cfg, {
                declarer = 1,
                bid = 120,
                captured_points = { 118, 2, 0 },
                marriage_bonuses = { 0, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(r.ok)
            assert.is_false(r.scoring.made_contract)
            assert.are.equal(118, r.scoring.contract_check_value)
            assert.are.equal(-120, r.scoring.deltas[1])
        end)

        it("preserves rounded deal_scores in the result regardless of the toggle", function()
            local cfg = with_scoring_overrides({
                scoring = { declarer_rounding_before_contract_check = "off" },
            })
            local r = scoring.score_deal(cfg, {
                declarer = 1,
                bid = 120,
                captured_points = { 118, 2, 0 },
                marriage_bonuses = { 0, 0, 0 },
                running_totals = { 0, 0, 0 },
            })
            assert.is_true(r.ok)
            -- 118 still rounds to 120 in deal_scores; only the contract
            -- check uses the raw 118.
            assert.are.equal(120, r.scoring.deal_scores[1])
            assert.are.equal(120, r.scoring.card_points_rounded[1])
        end)
    end)

    describe("score_deal() named contracts (Phase 3.6 specials)", function()
        local function named_opts(overrides)
            local opts = {
                declarer = 1,
                bid = { kind = "named", contract = "mizere", value = 120 },
                named_contract_made = true,
                captured_points = { 0, 60, 60 },
                running_totals = { 0, 0, 0 },
            }
            if overrides then
                for k, v in pairs(overrides) do
                    opts[k] = v
                end
            end
            return opts
        end

        it("rejects a structured bid without kind = 'named'", function()
            local r =
                scoring.score_deal(config, named_opts({ bid = { kind = "blind", value = 120 } }))
            assert.is_false(r.ok)
            assert.are.equal("bad_bid", r.error.code)
        end)

        it("rejects a named bid missing a string contract", function()
            local r = scoring.score_deal(
                config,
                named_opts({ bid = { kind = "named", contract = 42, value = 120 } })
            )
            assert.is_false(r.ok)
            assert.are.equal("bad_bid", r.error.code)
        end)

        it("rejects a named bid with non-positive integer value", function()
            for _, bad in ipairs({ 0, -1, 1.5, "120" }) do
                local r = scoring.score_deal(
                    config,
                    named_opts({ bid = { kind = "named", contract = "mizere", value = bad } })
                )
                assert.is_false(r.ok)
                assert.are.equal("bad_bid", r.error.code)
            end
        end)

        it("rejects a named contract without named_contract_made boolean", function()
            -- Build opts without the helper so we can omit the field outright.
            local opts_missing = {
                declarer = 1,
                bid = { kind = "named", contract = "mizere", value = 120 },
                captured_points = { 0, 60, 60 },
                running_totals = { 0, 0, 0 },
            }
            local r = scoring.score_deal(config, opts_missing)
            assert.is_false(r.ok)
            assert.are.equal("bad_named_contract_made", r.error.code)

            local r2 = scoring.score_deal(config, named_opts({ named_contract_made = "yes" }))
            assert.is_false(r2.ok)
            assert.are.equal("bad_named_contract_made", r2.error.code)
        end)

        it("scores a successful mizère as +value to declarer, 0 to defenders", function()
            local s = score_ok(named_opts({
                bid = { kind = "named", contract = "mizere", value = 120 },
                named_contract_made = true,
                captured_points = { 0, 60, 60 },
            }))
            assert.are.equal(120, s.deltas[1])
            assert.are.equal(0, s.deltas[2])
            assert.are.equal(0, s.deltas[3])
            assert.are.equal(120, s.running_totals[1])
            assert.are.equal(0, s.running_totals[2])
            assert.are.equal(0, s.running_totals[3])
            assert.is_true(s.made_contract)
            assert.are.equal(120, s.effective_bid)
            assert.are.equal("mizere", s.bid.contract)
            assert.are.equal(120, s.bid.value)
            assert.are.same({ kind = "mizere", value = 120 }, s.named_contract)
        end)

        it("scores a failed mizère as -value to declarer, 0 to defenders", function()
            local s = score_ok(named_opts({
                bid = { kind = "named", contract = "mizere", value = 120 },
                named_contract_made = false,
                captured_points = { 20, 50, 50 },
            }))
            assert.are.equal(-120, s.deltas[1])
            assert.are.equal(0, s.deltas[2])
            assert.are.equal(0, s.deltas[3])
            assert.are.equal(-120, s.running_totals[1])
            assert.is_false(s.made_contract)
        end)

        it("scores a successful slam as +value to declarer", function()
            local s = score_ok(named_opts({
                bid = { kind = "named", contract = "slam", value = 240 },
                named_contract_made = true,
                captured_points = { 120, 0, 0 },
            }))
            assert.are.equal(240, s.deltas[1])
            assert.are.equal(0, s.deltas[2])
            assert.are.equal(0, s.deltas[3])
            assert.are.equal(240, s.effective_bid)
        end)

        it("scores a failed slam as -value to declarer", function()
            local s = score_ok(named_opts({
                bid = { kind = "named", contract = "slam", value = 240 },
                named_contract_made = false,
                captured_points = { 105, 10, 5 },
            }))
            assert.are.equal(-240, s.deltas[1])
            assert.are.equal(0, s.deltas[2])
            assert.are.equal(0, s.deltas[3])
        end)

        it("scores a successful open hand as +value (already-doubled) to declarer", function()
            local s = score_ok(named_opts({
                bid = { kind = "named", contract = "open_hand", value = 200 },
                named_contract_made = true,
                captured_points = { 80, 30, 10 },
            }))
            assert.are.equal(200, s.deltas[1])
            assert.are.equal(0, s.deltas[2])
            assert.are.equal(0, s.deltas[3])
            assert.are.equal("open_hand", s.bid.contract)
        end)

        it("scores a failed open hand as -value to declarer", function()
            local s = score_ok(named_opts({
                bid = { kind = "named", contract = "open_hand", value = 200 },
                named_contract_made = false,
                captured_points = { 30, 50, 40 },
            }))
            assert.are.equal(-200, s.deltas[1])
            assert.are.equal(0, s.deltas[2])
            assert.are.equal(0, s.deltas[3])
        end)

        it("preserves the score-state shape with zeroed bonus arrays", function()
            local s = score_ok(named_opts({
                bid = { kind = "named", contract = "mizere", value = 120 },
                named_contract_made = true,
                captured_points = { 0, 60, 60 },
            }))
            assert.are.same({ 0, 0, 0 }, s.marriage_bonuses)
            assert.are.same({ 0, 0, 0 }, s.half_marriage_capture_bonuses)
            assert.are.same({ 0, 0, 0 }, s.ace_marriage_bonuses)
            assert.are.same({ 0, 0, 0 }, s.last_trick_bonus)
            assert.are.same({ 0, 0, 0 }, s.slam_bonus)
            assert.are.same({ 0, 0, 0 }, s.slam_against_penalty)
            assert.are.same({ 0, 0, 0 }, s.deal_scores)
            assert.are.same({ 0, 0, 0 }, s.failed_contract_distribution_extras)
            assert.is_nil(s.defender_pool_total)
            assert.are.equal(1, s.bid_multiplier)
        end)

        it("rounds captured points for the state's card_points_rounded array", function()
            local s = score_ok(named_opts({
                bid = { kind = "named", contract = "mizere", value = 120 },
                named_contract_made = true,
                captured_points = { 0, 73, 47 },
            }))
            assert.are.equal(0, s.card_points_rounded[1])
            assert.are.equal(75, s.card_points_rounded[2])
            assert.are.equal(45, s.card_points_rounded[3])
        end)
    end)
end)
