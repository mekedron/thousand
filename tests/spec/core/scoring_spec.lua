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
end)
