-- Unit coverage for the table view-model. Pure Lua — no love.* — so the
-- spec runs under plain busted.

local view_model = require("app.table_view_model")
local Session = require("app.session")
local rule_config = require("core.rule_config")

local config = rule_config.canonical_russian

local function find_in_hand(hand, suit, rank)
    for _, c in ipairs(hand) do
        if c.suit == suit and c.rank == rank then
            return c
        end
    end
    return nil
end

local function safe_pass_card(hand, marriage_suit)
    for _, c in ipairs(hand) do
        if not (c.suit == marriage_suit and (c.rank == "K" or c.rank == "Q")) then
            return c
        end
    end
    error("no safe pass card available")
end

local function drive_to_talon(seed, dealer)
    local s = Session.new({ seed = seed, dealer = dealer or 1 })
    assert(s:bid(2, 100).ok)
    assert(s:pass(3).ok)
    assert(s:pass(1).ok)
    return s
end

local function drive_to_tricks(seed)
    local s = drive_to_talon(seed)
    assert(s:take_talon().ok)
    local hand = s:hands()[2]
    assert(s:pass_talon(1, hand[1]).ok)
    hand = s:hands()[2]
    assert(s:pass_talon(3, hand[1]).ok)
    assert(s:skip_raise().ok)
    return s
end

describe("app.table_view_model", function()
    describe("from_session — fresh session", function()
        local view

        before_each(function()
            local s = Session.new({ seed = 42, dealer = 1 })
            view = view_model.from_session(s)
        end)

        it("derives the auction phase with the forehand on turn", function()
            assert.are.equal("auction", view.phase)
            assert.are.equal(2, view.turn_player)
            assert.are.equal(1, view.dealer)
        end)

        it("annotates dealer and turn flags on the hands", function()
            assert.is_true(view.hands[1].is_dealer)
            assert.is_false(view.hands[2].is_dealer)
            assert.is_false(view.hands[1].is_turn)
            assert.is_true(view.hands[2].is_turn)
        end)

        it("sets perspective to self for the seat on turn and other elsewhere", function()
            -- Hot-seat input wiring needs the active hand visible so the
            -- player can pick. The privacy hand-off task adds the
            -- between-turns overlay on top of this.
            assert.are.equal("other", view.hands[1].perspective)
            assert.are.equal("self", view.hands[2].perspective)
            assert.are.equal("other", view.hands[3].perspective)
        end)

        it("renders the talon face-down with three cards in the auction", function()
            assert.is_true(view.talon.face_down)
            assert.are.equal(3, view.talon.count)
        end)

        it("reports no bid, no leader, no trump, no winner pre-action", function()
            assert.is_nil(view.current_bid)
            assert.is_nil(view.leader)
            assert.is_nil(view.trump)
            assert.is_nil(view.winner)
            assert.is_nil(view.final_scores)
        end)

        it("zeros the scoreboard with all seats off the barrel", function()
            for _, entry in ipairs(view.scoreboard) do
                assert.are.equal(0, entry.total)
                assert.is_false(entry.barrel.on_barrel)
                assert.is_false(entry.is_winner)
            end
        end)

        it("includes the player count for downstream layout choices", function()
            assert.are.equal(3, view.player_count)
        end)

        it("surfaces an auction block describing the bid panel inputs", function()
            assert.is_table(view.auction)
            assert.is_nil(view.auction.current_bid) -- pre-first bid
            assert.is_table(view.auction.allowed_bid_amounts)
            -- Opening minimum is 100; first allowed bid is 100, then
            -- 105 / 110 / 115 / 120 up to the pre-talon ceiling.
            assert.are.equal(100, view.auction.allowed_bid_amounts[1])
            assert.is_true(view.auction.can_pass)
            assert.are.equal(2, view.auction.on_turn)
        end)

        it("does not surface a talon_phase block while in auction", function()
            assert.is_nil(view.talon_phase)
        end)

        it("does not surface a current_trick block while in auction", function()
            assert.is_nil(view.current_trick)
        end)

        it("does not surface a marriage_offer flag while in auction", function()
            assert.is_nil(view.marriage_offer)
        end)

        it("does not surface a deal_done block while in auction", function()
            assert.is_nil(view.deal_done)
        end)
    end)

    describe("from_session — talon phase", function()
        local view, session

        before_each(function()
            session = drive_to_talon(42)
            view = view_model.from_session(session)
        end)

        it("reports the talon phase with the declarer on turn", function()
            assert.are.equal("talon", view.phase)
            assert.are.equal(2, view.turn_player)
            assert.are.equal(2, view.leader)
        end)

        it("uncovers the talon (face-up, three cards visible)", function()
            assert.is_false(view.talon.face_down)
            assert.are.equal(3, view.talon.count)
        end)

        it("flags the declarer's hand as self", function()
            assert.are.equal("self", view.hands[2].perspective)
            assert.are.equal("other", view.hands[1].perspective)
            assert.are.equal("other", view.hands[3].perspective)
        end)

        it("surfaces a talon_phase block at status 'revealed' before take", function()
            assert.is_table(view.talon_phase)
            assert.are.equal("revealed", view.talon_phase.status)
            assert.are.equal(2, view.talon_phase.declarer)
        end)

        it("transitions talon_phase to awaiting_pass after take", function()
            assert(session:take_talon().ok)
            view = view_model.from_session(session)
            assert.are.equal("awaiting_pass", view.talon_phase.status)
            assert.is_not_nil(view.talon_phase.pass_target_seat)
        end)

        it("surfaces awaiting_raise with allowed_raise_amounts after both passes", function()
            assert(session:take_talon().ok)
            local hand = session:hands()[2]
            assert(session:pass_talon(1, hand[1]).ok)
            hand = session:hands()[2]
            assert(session:pass_talon(3, hand[1]).ok)
            view = view_model.from_session(session)
            assert.are.equal("awaiting_raise", view.talon_phase.status)
            assert.is_table(view.talon_phase.allowed_raise_amounts)
            -- Raise must be strictly higher; the first amount > 100.
            assert.is_true(view.talon_phase.allowed_raise_amounts[1] > 100)
        end)

        it("does not surface a current_trick block during talon", function()
            assert.is_nil(view.current_trick)
        end)
    end)

    describe("from_session — tricks phase", function()
        local view, session

        before_each(function()
            session = drive_to_tricks(42)
            view = view_model.from_session(session)
        end)

        it("reports the tricks phase with the declarer leading", function()
            assert.are.equal("tricks", view.phase)
            assert.are.equal(2, view.turn_player)
        end)

        it("flags the player on turn as self", function()
            assert.are.equal("self", view.hands[2].perspective)
            assert.are.equal("other", view.hands[1].perspective)
            assert.are.equal("other", view.hands[3].perspective)
        end)

        it("surfaces an empty current_trick at the lead", function()
            assert.is_table(view.current_trick)
            assert.are.same({}, view.current_trick.plays)
            assert.is_nil(view.current_trick.lead_suit)
            assert.are.equal(2, view.current_trick.next_to_play)
        end)

        it("surfaces plays + lead suit after the leader plays", function()
            local p = session:current_turn()
            local card = session:legal_cards(p)[1]
            assert(session:play(p, card).ok)
            view = view_model.from_session(session)
            assert.are.equal(1, #view.current_trick.plays)
            assert.are.equal(p, view.current_trick.plays[1].player)
            assert.are.equal(card.suit, view.current_trick.lead_suit)
        end)

        it("does not surface the auction or talon_phase blocks during tricks", function()
            assert.is_nil(view.auction)
            assert.is_nil(view.talon_phase)
        end)
    end)

    describe("from_session — marriage offer", function()
        local view, session
        local marriage_suit = "spades"

        before_each(function()
            session = Session.new({ seed = 1, dealer = 1 })
            assert(session:bid(2, 100).ok)
            assert(session:bid(3, 105).ok)
            assert(session:pass(1).ok)
            assert(session:bid(2, 120).ok)
            assert(session:pass(3).ok)
            assert(session:take_talon().ok)
            local hand = session:hands()[2]
            assert(session:pass_talon(1, safe_pass_card(hand, marriage_suit)).ok)
            hand = session:hands()[2]
            assert(session:pass_talon(3, safe_pass_card(hand, marriage_suit)).ok)
            assert(session:skip_raise().ok)
            view = view_model.from_session(session)
        end)

        it("flags the lead-time marriage offer for the seat on turn", function()
            assert.is_table(view.marriage_offer)
            assert.is_table(view.marriage_offer.suits)
            assert.are.equal(1, #view.marriage_offer.suits)
            assert.are.equal(marriage_suit, view.marriage_offer.suits[1])
        end)

        it("clears the marriage offer once the lead has been played", function()
            local king = find_in_hand(session:hands()[2], marriage_suit, "K")
            assert(session:declare_marriage(2, marriage_suit).ok)
            assert(session:play(2, king).ok)
            view = view_model.from_session(session)
            assert.is_nil(view.marriage_offer)
        end)
    end)

    describe("from_session — deal_done after scoring", function()
        local view

        before_each(function()
            local session = drive_to_tricks(42)
            while session:current_phase() == "tricks" do
                local p = session:current_turn()
                local card = session:legal_cards(p)[1]
                assert(session:play(p, card).ok)
            end
            view = view_model.from_session(session)
        end)

        it("reports the deal_done phase after the eighth trick", function()
            assert.are.equal("deal_done", view.phase)
        end)

        it("surfaces a deal_done block with reason 'scored' and running totals", function()
            assert.is_table(view.deal_done)
            assert.are.equal("scored", view.deal_done.reason)
            assert.are.same({ 65, -100, 30 }, view.deal_done.running_totals)
        end)

        it("clears auction / talon_phase / current_trick / marriage_offer", function()
            assert.is_nil(view.auction)
            assert.is_nil(view.talon_phase)
            assert.is_nil(view.current_trick)
            assert.is_nil(view.marriage_offer)
        end)
    end)

    describe("from_session — finished session", function()
        local view

        before_each(function()
            local s = Session.from_state({
                config = config,
                dealer = 2,
                running_totals = { 1010, 720, 540 },
                winner = 1,
            })
            view = view_model.from_session(s)
        end)

        it("reports the done phase with no actor on turn", function()
            assert.are.equal("done", view.phase)
            assert.is_nil(view.turn_player)
        end)

        it("populates winner and final scores", function()
            assert.are.equal(1, view.winner)
            assert.are.same({ 1010, 720, 540 }, view.final_scores)
        end)

        it("flags the winning seat in the scoreboard", function()
            assert.is_true(view.scoreboard[1].is_winner)
            assert.is_false(view.scoreboard[2].is_winner)
            assert.is_false(view.scoreboard[3].is_winner)
        end)
    end)

    it("never returns the engine's hand list directly so the renderer cannot mutate it", function()
        local s = Session.new({ seed = 1 })
        local engine_hands = s:hands()
        local view = view_model.from_session(s)
        view.hands[1].cards[1] = { suit = "spades", rank = "A" } -- bogus tamper
        -- Engine's list still untouched.
        assert.are_not.equal(view.hands[1].cards, engine_hands[1])
    end)

    describe("allowed_bid_amounts follows config.bidding.increment_threshold", function()
        -- Helper: clone canonical Russian and override one bidding field.
        local function with_bidding(overrides)
            local bidding = {
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
            }
            for k, v in pairs(overrides) do
                bidding[k] = v
            end
            return rule_config.new({
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
                    buyback_penalty = 50,
                    hidden_on_minimum_100 = "off",
                    bad_talon_redeal = "off",
                    bad_talon_threshold = 5,
                    rebuy = "off",
                    rebuy_contract_value = 240,
                    open_discard = "off",
                },
                bidding = bidding,
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
            })
        end

        it("under canonical Russian the opening ladder is 100, 105, 110, 115, 120", function()
            local s = Session.new({ seed = 7 })
            local view = view_model.from_session(s)
            assert.same({ 100, 105, 110, 115, 120 }, view.auction.allowed_bid_amounts)
        end)

        it("with threshold = 110 the ladder pivots early and skips 115", function()
            -- Pivot drops to 110, step jumps to 10 from there. With
            -- pre_talon_max still 120, the panel renders 100, 105, 110, 120.
            local custom = with_bidding({ increment_threshold = 110 })
            local s = Session.new({ seed = 7, config = custom })
            local view = view_model.from_session(s)
            assert.same({ 100, 105, 110, 120 }, view.auction.allowed_bid_amounts)
        end)
    end)

    describe("variant view fields", function()
        it("exposes the dealer's sits-out seat and partnership sides for 4-player B", function()
            local s = Session.new({
                seed = 7,
                dealer = 2,
                config = rule_config.builtins.four_player_b,
            })
            local view = view_model.from_session(s)
            assert.are.equal(4, view.player_count)
            assert.are.equal(2, view.sits_out)
            assert.is_table(view.partnership)
            assert.same({ 1, 2, 1, 2 }, view.partnership.sides)
            assert.are.equal(2, #view.partnership.totals)
            -- The dealer's seat is rendered with sits_out = true so the
            -- table scene dims it; per-seat partnership side is also
            -- surfaced.
            assert.is_true(view.hands[2].sits_out)
            assert.are.equal(1, view.hands[1].side)
            assert.are.equal(2, view.hands[2].side)
            assert.is_true(view.scoreboard[2].sits_out)
        end)

        it("exposes a stock block with trump indicator for 2-player A", function()
            local s = Session.new({
                seed = 7,
                config = rule_config.builtins.two_player_a,
            })
            local view = view_model.from_session(s)
            assert.are.equal(2, view.player_count)
            assert.is_table(view.stock)
            assert.are.equal(6, view.stock.count)
            assert.is_table(view.stock.trump_indicator)
            assert.is_nil(view.partnership)
            assert.is_nil(view.sits_out)
        end)
    end)

    describe("dealing & redeal view fields", function()
        local function canonical_with_dealing(overrides)
            overrides = overrides or {}
            local d = {
                four_nine_redeal = "off",
                three_nine_redeal = "off",
                four_jack_redeal = "off",
                weak_hand_redeal = "off",
                weak_hand_threshold = 14,
                misdeal_handling = "standard",
                misdeal_flat_penalty = 20,
                all_pass_handling = "redeal",
            }
            for k, v in pairs(overrides) do
                d[k] = v
            end
            local s = rule_config.to_json(rule_config.canonical_russian)
            local res = rule_config.from_json(s)
            local blob = {
                schema_version = 1,
                cards = res.config.cards,
                players = res.config.players,
                dealing = d,
                talon = res.config.talon,
                bidding = res.config.bidding,
                marriages = res.config.marriages,
                tricks = res.config.tricks,
                scoring = res.config.scoring,
                opening_game = res.config.opening_game,
                barrel = res.config.barrel,
                endgame = res.config.endgame,
                specials = res.config.specials,
                penalties = res.config.penalties,
            }
            return rule_config.new(blob)
        end

        it("leaves all four blocks nil for a fresh canonical session", function()
            local s = Session.new({ seed = 42, dealer = 1 })
            local view = view_model.from_session(s)
            assert.is_nil(view.redeal_prompt)
            assert.is_nil(view.misdeal_banner)
            assert.is_nil(view.all_pass_banner)
            assert.is_false(view.raspassy_active)
        end)

        it("populates redeal_prompt while a session is awaiting a decision", function()
            local cfg = canonical_with_dealing({ weak_hand_redeal = "strict" })
            local auction_module = require("core.auction")
            local marriages_module = require("core.marriages")
            local card = require("core.card")
            local s = Session.from_state({
                config = cfg,
                seed = 1,
                dealer = 1,
                hands = {
                    {
                        card.new("spades", "K"),
                        card.new("clubs", "K"),
                        card.new("diamonds", "K"),
                        card.new("hearts", "K"),
                        card.new("spades", "Q"),
                        card.new("clubs", "Q"),
                        card.new("diamonds", "Q"),
                    },
                    {
                        card.new("spades", "9"),
                        card.new("clubs", "9"),
                        card.new("diamonds", "9"),
                        card.new("hearts", "9"),
                        card.new("spades", "10"),
                        card.new("clubs", "10"),
                        card.new("diamonds", "10"),
                    },
                    {
                        card.new("hearts", "Q"),
                        card.new("hearts", "10"),
                        card.new("spades", "J"),
                        card.new("clubs", "J"),
                        card.new("diamonds", "J"),
                        card.new("hearts", "J"),
                        card.new("spades", "A"),
                    },
                },
                talon_cards = {
                    card.new("clubs", "A"),
                    card.new("diamonds", "A"),
                    card.new("hearts", "A"),
                },
                auction = auction_module.new(cfg, 1).auction,
                marriages = marriages_module.new(cfg).marriages,
                running_totals = { 0, 0, 0 },
                redeal_offer = { seat = 2, kind = "weak_hand", forced = false },
            })
            local view = view_model.from_session(s)
            assert.is_table(view.redeal_prompt)
            assert.are.equal("weak_hand", view.redeal_prompt.kind)
            assert.are.equal(2, view.redeal_prompt.seat)
            assert.is_false(view.redeal_prompt.forced)
            assert.are.equal("awaiting_redeal_decision", view.phase)
        end)

        it("populates misdeal_banner with handling, dealer, and penalty", function()
            local cfg = canonical_with_dealing({
                misdeal_handling = "flat_penalty",
                misdeal_flat_penalty = 30,
            })
            local s = Session.new({ config = cfg, seed = 1, dealer = 2 })
            assert.is_true(s:report_misdeal().ok)
            local view = view_model.from_session(s)
            assert.is_table(view.misdeal_banner)
            assert.are.equal("flat_penalty", view.misdeal_banner.handling)
            assert.are.equal(2, view.misdeal_banner.dealer)
            assert.are.equal(30, view.misdeal_banner.penalty)
        end)

        it("renders an all_pass_banner with mode = redeal under the default", function()
            local s = Session.new({ seed = 1, dealer = 1 })
            assert.is_true(s:pass(s:current_turn()).ok)
            assert.is_true(s:pass(s:current_turn()).ok)
            local view = view_model.from_session(s)
            assert.is_table(view.all_pass_banner)
            assert.are.equal("redeal", view.all_pass_banner.mode)
        end)

        it("renders an all_pass_banner with mode = pass_out when configured", function()
            local cfg = canonical_with_dealing({ all_pass_handling = "pass_out" })
            local s = Session.new({ config = cfg, seed = 1, dealer = 1 })
            assert.is_true(s:pass(s:current_turn()).ok)
            assert.is_true(s:pass(s:current_turn()).ok)
            local view = view_model.from_session(s)
            assert.are.equal("pass_out", view.all_pass_banner.mode)
        end)

        it("renders raspassy_active = true with all_pass_banner mode = raspassy", function()
            local cfg = canonical_with_dealing({ all_pass_handling = "raspassy" })
            local s = Session.new({ config = cfg, seed = 1, dealer = 1 })
            assert.is_true(s:pass(s:current_turn()).ok)
            assert.is_true(s:pass(s:current_turn()).ok)
            local view = view_model.from_session(s)
            assert.is_true(view.raspassy_active)
            assert.are.equal("raspassy", view.all_pass_banner.mode)
            -- Bid/leader/trump indicators are hidden in raspassy mode.
            assert.is_nil(view.current_bid)
            assert.is_nil(view.leader)
            assert.is_nil(view.trump)
            assert.are.equal("raspassy_play", view.phase)
        end)
    end)
end)
