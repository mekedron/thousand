-- End-to-end journey for the Phase 3.6 bidding-variants UI. Builds a
-- session in the auction phase (or post-auction doubling phase) with each
-- bidding toggle exercised, drives the table scene under the journey's
-- mocked Love, and asserts the localised affordances render correctly.
--
-- These tests are RED until the implementation lands (see plan:
-- sidebar-position-4-title-modular-narwhal). Every `it` block describes
-- the expected behaviour so the implementation has an unambiguous target.

local journey = require("tests.e2e.support.journey")

local function find_text(j, needle)
    return j._mock.graphics.find_text(needle)
end

local function build_table_scene_in_mock(session)
    local scene_manager = require("ui.scene_manager")
    local table_scene = require("ui.scenes.table")
    local manager = scene_manager.new()
    manager:set_session(session)
    manager:register("table", table_scene.new(manager))
    manager:switch_to("table")
    return manager, manager._scenes["table"]
end

local function dismiss_curtain_state(scene)
    scene._curtain = nil
    if scene._view_model and scene._view_model.turn_player then
        scene._last_revealed_seat = scene._view_model.turn_player
    end
end

-- Build a RuleConfig from canonical_russian, deep-copying it through JSON
-- and overlaying only the bidding keys supplied in `overrides`. Every key
-- not mentioned is taken from the canonical defaults, so each test starts
-- from a valid, well-known config and changes only what it needs.
local function build_config(overrides, specials_overrides)
    local rule_config = require("core.rule_config")
    local s = rule_config.to_json(rule_config.canonical_russian)
    local res = rule_config.from_json(s)
    local base = res.config
    local bidding = {
        opening_min = base.bidding.opening_min,
        pre_talon_max = base.bidding.pre_talon_max,
        increment_threshold = base.bidding.increment_threshold,
        increment_below_200 = base.bidding.increment_below_200,
        increment_from_200 = base.bidding.increment_from_200,
        forced_opening = base.bidding.forced_opening,
        forced_dealer_bid = base.bidding.forced_dealer_bid,
        blind_bid = base.bidding.blind_bid,
        blind_bid_success_multiplier = base.bidding.blind_bid_success_multiplier,
        blind_bid_failure_multiplier = base.bidding.blind_bid_failure_multiplier,
        re_entry_after_pass = base.bidding.re_entry_after_pass,
        contra = base.bidding.contra,
        contra_multiplier = base.bidding.contra_multiplier,
        redouble_multiplier = base.bidding.redouble_multiplier,
        forced_bid_concession = base.bidding.forced_bid_concession,
        forced_bid_concession_preset_ratio = (function()
            local r = {}
            for i, v in ipairs(base.bidding.forced_bid_concession_preset_ratio) do
                r[i] = v
            end
            return r
        end)(),
        no_contract_without_marriage = base.bidding.no_contract_without_marriage,
        negative_score_restriction = base.bidding.negative_score_restriction,
        named_contracts = base.bidding.named_contracts,
        named_contracts_precedence = (function()
            local r = {}
            for i, v in ipairs(base.bidding.named_contracts_precedence) do
                r[i] = v
            end
            return r
        end)(),
    }
    for k, v in pairs(overrides or {}) do
        bidding[k] = v
    end
    local blob = {
        schema_version = 1,
        cards = base.cards,
        players = base.players,
        dealing = base.dealing,
        talon = base.talon,
        bidding = bidding,
        marriages = base.marriages,
        tricks = base.tricks,
        scoring = base.scoring,
        opening_game = base.opening_game,
        barrel = base.barrel,
        endgame = base.endgame,
        specials = base.specials,
        penalties = base.penalties,
    }
    if specials_overrides then
        local specials = {
            mizere = base.specials.mizere,
            slam_contract = base.specials.slam_contract,
            open_hand = base.specials.open_hand,
        }
        for k, v in pairs(specials_overrides) do
            specials[k] = v
        end
        blob.specials = specials
    end
    return rule_config.new(blob)
end

-- Build a fresh session in the auction phase using `from_state`. The auction
-- is brand-new (no bids yet), dealer = 1, forehand = seat 2. This mirrors
-- the setup in session_talon_variants_spec but stays in the auction phase
-- rather than driving to talon-revealed — most bidding-variant affordances
-- appear on the auction panel.
local function build_session_at_auction(cfg)
    local Session = require("app.session")
    local auction_module = require("core.auction")
    local marriages_module = require("core.marriages")
    local card = require("core.card")
    -- Minimal hands: 7 cards each, talon 3 cards. Low-value cards so no
    -- forced marriages interfere with the auction state checks.
    local seat1 = {
        card.new("spades", "K"),
        card.new("clubs", "K"),
        card.new("diamonds", "K"),
        card.new("hearts", "K"),
        card.new("spades", "Q"),
        card.new("clubs", "Q"),
        card.new("diamonds", "Q"),
    }
    local seat2 = {
        card.new("hearts", "Q"),
        card.new("spades", "J"),
        card.new("clubs", "J"),
        card.new("diamonds", "J"),
        card.new("hearts", "J"),
        card.new("spades", "A"),
        card.new("clubs", "A"),
    }
    local seat3 = {
        card.new("diamonds", "A"),
        card.new("hearts", "A"),
        card.new("spades", "10"),
        card.new("clubs", "10"),
        card.new("diamonds", "10"),
        card.new("hearts", "10"),
        card.new("hearts", "9"),
    }
    local talon_cards = {
        card.new("spades", "9"),
        card.new("clubs", "9"),
        card.new("diamonds", "9"),
    }
    local auction_result = auction_module.new(cfg, 1)
    local marriages_result = marriages_module.new(cfg)
    return Session.from_state({
        config = cfg,
        seed = 42,
        dealer = 1,
        hands = { seat1, seat2, seat3 },
        talon_cards = talon_cards,
        auction = auction_result.auction,
        marriages = marriages_result.marriages,
        running_totals = { 0, 0, 0 },
        deal_index = 1,
    })
end

-- Build a session where the auction has terminated all-pass. The
-- engine fires its termination after pass_count >= player_count - 1,
-- so two passes are enough — the dealer is the "remaining" seat and
-- the forced_dealer_bid path picks them as the forced declarer.
local function build_session_after_all_pass(cfg)
    local s = build_session_at_auction(cfg)
    assert(s:pass(2).ok)
    assert(s:pass(3).ok)
    return s
end

-- Hands where seat 2 holds a marriage in hearts so named-contract / marriage
-- tests have realistic holdings.
local function build_session_with_marriage_hand(cfg)
    local Session = require("app.session")
    local auction_module = require("core.auction")
    local marriages_module = require("core.marriages")
    local card = require("core.card")
    -- Seat 2 has hearts K+Q (a marriage) and high-value cards.
    local seat1 = {
        card.new("spades", "K"),
        card.new("clubs", "K"),
        card.new("diamonds", "K"),
        card.new("hearts", "9"),
        card.new("spades", "Q"),
        card.new("clubs", "Q"),
        card.new("diamonds", "Q"),
    }
    local seat2 = {
        card.new("hearts", "K"),
        card.new("hearts", "Q"),
        card.new("spades", "J"),
        card.new("clubs", "J"),
        card.new("diamonds", "J"),
        card.new("spades", "A"),
        card.new("clubs", "A"),
    }
    local seat3 = {
        card.new("diamonds", "A"),
        card.new("hearts", "A"),
        card.new("spades", "10"),
        card.new("clubs", "10"),
        card.new("diamonds", "10"),
        card.new("hearts", "10"),
        card.new("hearts", "J"),
    }
    local talon_cards = {
        card.new("spades", "9"),
        card.new("clubs", "9"),
        card.new("diamonds", "9"),
    }
    local auction_result = auction_module.new(cfg, 1)
    local marriages_result = marriages_module.new(cfg)
    return Session.from_state({
        config = cfg,
        seed = 99,
        dealer = 1,
        hands = { seat1, seat2, seat3 },
        talon_cards = talon_cards,
        auction = auction_result.auction,
        marriages = marriages_result.marriages,
        running_totals = { 0, 0, 0 },
        deal_index = 1,
    })
end

-- Find a panel button by its `id` field. Returns the Button object or nil.
local function find_panel_button(scene, id)
    for _, b in ipairs(scene._panel_buttons) do
        if b.id == id then
            return b
        end
    end
    return nil
end

describe("bidding variants e2e", function()
    local j

    before_each(function()
        j = journey.start({ locale = "en", width = 1024, height = 720 })
        j:step()
    end)

    after_each(function()
        if j then
            j:stop()
        end
    end)

    -- -----------------------------------------------------------------------
    -- 1. forced_opening: forehand cannot pass on the first action.
    --    The pass button should be rendered with enabled = false (greyed out)
    --    or absent entirely while it is forehand's first turn.
    -- -----------------------------------------------------------------------
    it("renders greyed-out (or hidden) pass button under forced_opening", function()
        local cfg = build_config({ forced_opening = "on" })
        local s = build_session_at_auction(cfg)

        -- Auction is fresh; seat 2 (forehand) is on turn.
        assert.are.equal("auction", s:current_phase())
        assert.are.equal(2, s:current_turn())

        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        _G.love.graphics.clear_recording()
        scene:draw(1024, 720)

        -- The pass button must either be absent from _panel_buttons or
        -- present with enabled = false.
        local pass_btn = find_panel_button(scene, "auction_pass")
        if pass_btn ~= nil then
            assert.is_false(
                pass_btn.enabled,
                "pass button must be disabled (greyed out) for forehand on round 1 under forced_opening"
            )
        end

        -- Additionally, the view model must expose forehand_pass_disabled.
        local vm = scene._view_model
        assert.is_not_nil(
            vm and vm.auction and vm.auction.forehand_pass_disabled,
            "view model auction.forehand_pass_disabled must be truthy under forced_opening"
        )
    end)

    -- -----------------------------------------------------------------------
    -- 2. forced_dealer_bid: when all seats pass, the dealer is assigned 100
    --    automatically and a banner is shown near the misdeal banner area.
    -- -----------------------------------------------------------------------
    it("renders dealer-forced banner under forced_dealer_bid after all-pass", function()
        local cfg = build_config({ forced_dealer_bid = "on" })
        local s = build_session_after_all_pass(cfg)

        -- After all-pass with forced_dealer_bid=on the auction must be done
        -- with dealer forced; the session may still be in "auction" (done
        -- status) or have moved to "talon" depending on implementation.
        -- Either way the scene must draw the banner.
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        _G.love.graphics.clear_recording()
        scene:draw(1024, 720)

        -- The banner text key encodes seat 1 forced to 100.
        local banner_text =
            j:find_localised("scene.table.auction.dealer_forced_banner", { seat = 1, amount = 100 })
        assert.is_not_nil(
            find_text(j, banner_text),
            "dealer-forced banner must be visible after all-pass with forced_dealer_bid=on"
        )
    end)

    -- -----------------------------------------------------------------------
    -- 3. blind_bid = first_bid_double: before the first bid is placed the
    --    auction panel must show a "Bid blind ×2" button. After clicking it
    --    the multiplier badge (×2) must appear beside the current bid.
    -- -----------------------------------------------------------------------
    it("renders blind-bid button with x2 multiplier preview under blind_bid", function()
        local cfg = build_config({ blind_bid = "first_bid_double" })
        local s = build_session_at_auction(cfg)

        -- Forehand (seat 2) is on turn; no bid has been placed yet so the
        -- blind-bid offer must be active.
        assert.are.equal(2, s:current_turn())

        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        _G.love.graphics.clear_recording()
        scene:draw(1024, 720)

        -- The "Bid blind ×2" button must appear on the panel.
        local blind_label =
            j:find_localised("scene.table.auction.bid_blind_button", { multiplier = 2 })
        assert.is_not_nil(
            find_text(j, blind_label),
            "blind-bid button must be visible before any bid under blind_bid=first_bid_double"
        )

        local blind_btn = find_panel_button(scene, "auction_bid_blind")
        assert.is_not_nil(blind_btn, "auction_bid_blind panel button must exist")
        assert.is_true(
            blind_btn.enabled,
            "auction_bid_blind button must be enabled before the first bid"
        )

        -- Simulate the player declaring blind.
        local res = s:declare_blind(2)
        assert.is_true(res.ok, "declare_blind must succeed for forehand pre-bid")

        -- After declaring blind, contract_multiplier() must return 2.
        assert.are.equal(2, s:contract_multiplier())

        -- Redraw and verify the multiplier badge is visible.
        _G.love.graphics.clear_recording()
        scene:draw(1024, 720)

        local badge_text =
            j:find_localised("scene.table.auction.contract_multiplier_badge", { n = 2 })
        assert.is_not_nil(
            find_text(j, badge_text),
            "multiplier badge ×2 must be visible after declare_blind"
        )
    end)

    -- -----------------------------------------------------------------------
    -- 4. contra = contra_and_redouble: after the auction concludes,
    --    defenders see a "Contra" button; if contra is declared the declarer
    --    sees a "Redouble" button (and a "Concede" option at equal_split).
    -- -----------------------------------------------------------------------
    it("renders contra and redouble buttons at talon-revealed under contra_and_redouble", function()
        local cfg = build_config({
            contra = "contra_and_redouble",
            forced_bid_concession = "equal_split",
        })
        local s = build_session_at_auction(cfg)

        -- Drive the auction: seat 2 bids 100, seats 3 and 1 pass.
        assert(s:bid(2, 100).ok)
        assert(s:pass(3).ok)
        assert(s:pass(1).ok)

        -- Session must now be in a doubling or talon phase waiting for
        -- contra/redouble decisions.
        local phase = s:current_phase()
        assert.is_true(
            phase == "talon" or phase == "auction",
            "session must be past auction after bidding completes (phase=" .. tostring(phase) .. ")"
        )

        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        _G.love.graphics.clear_recording()
        scene:draw(1024, 720)

        -- Defender should see Contra button.
        local contra_label = j:find_localised("scene.table.auction.contra_button")
        assert.is_not_nil(
            find_text(j, contra_label),
            "Contra button must be visible to defenders under contra_and_redouble"
        )

        local contra_btn = find_panel_button(scene, "talon_contra")
        assert.is_not_nil(contra_btn, "talon_contra panel button must exist")

        -- Declare contra; then declarer should see Redouble.
        -- Seat 3 is a defender (seat 2 is declarer).
        local contra_res = s:declare_contra(3)
        assert.is_true(contra_res.ok, "declare_contra must succeed for a defender")

        _G.love.graphics.clear_recording()
        scene:draw(1024, 720)

        local redouble_label = j:find_localised("scene.table.auction.redouble_button")
        assert.is_not_nil(
            find_text(j, redouble_label),
            "Redouble button must be visible to declarer after contra"
        )

        local redouble_btn = find_panel_button(scene, "talon_redouble")
        assert.is_not_nil(redouble_btn, "talon_redouble panel button must exist after contra")

        -- forced_bid_concession only opens when the dealer was forced
        -- into the contract via forced_dealer_bid. Numeric winners
        -- (this scenario) do not get the concession offer. The
        -- concede assertion is covered by the dedicated
        -- forced_bid_concession test in session_bidding_variants_spec.
    end)

    -- -----------------------------------------------------------------------
    -- 5. named_contracts = on: the auction panel shows mizère, slam and
    --    open-hand buttons during the bidding phase alongside normal bids.
    -- -----------------------------------------------------------------------
    it("renders mizere, slam, and open-hand buttons under named_contracts + specials", function()
        local cfg = build_config(
            { named_contracts = "on" },
            { mizere = "on", slam_contract = "on", open_hand = "on" }
        )
        local s = build_session_with_marriage_hand(cfg)

        -- Auction is fresh; the named-contract buttons should appear for
        -- the seat on turn even before any bid is made.
        assert.are.equal("auction", s:current_phase())

        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        _G.love.graphics.clear_recording()
        scene:draw(1024, 720)

        -- Retrieve the named-contract values from the view model.
        local vm = scene._view_model
        local named_buttons = vm and vm.auction and vm.auction.named_contract_buttons
        assert.is_not_nil(
            named_buttons,
            "view model auction.named_contract_buttons must be present under named_contracts=on"
        )

        -- Mizère button. named_buttons is an ordered list of
        -- {id, kind, contract_value} entries; pull the kind we need.
        local function value_for(kind)
            for _, btn in ipairs(named_buttons or {}) do
                if btn.kind == kind then
                    return btn.contract_value
                end
            end
            return 0
        end
        local mizere_value = value_for("mizere")
        local mizere_label =
            j:find_localised("scene.table.auction.named_mizere_button", { value = mizere_value })
        assert.is_not_nil(
            find_text(j, mizere_label),
            "Mizère button must be visible under named_contracts=on"
        )

        local mizere_btn = find_panel_button(scene, "auction_named_mizere")
        assert.is_not_nil(mizere_btn, "auction_named_mizere panel button must exist")

        -- Slam button.
        local slam_value = value_for("slam")
        local slam_label =
            j:find_localised("scene.table.auction.named_slam_button", { value = slam_value })
        assert.is_not_nil(
            find_text(j, slam_label),
            "Slam button must be visible under named_contracts=on"
        )

        local slam_btn = find_panel_button(scene, "auction_named_slam")
        assert.is_not_nil(slam_btn, "auction_named_slam panel button must exist")

        -- Open-hand button.
        local open_value = value_for("open_hand")
        local open_label =
            j:find_localised("scene.table.auction.named_open_hand_button", { value = open_value })
        assert.is_not_nil(
            find_text(j, open_label),
            "Open hand button must be visible under named_contracts=on"
        )

        local open_btn = find_panel_button(scene, "auction_named_open_hand")
        assert.is_not_nil(open_btn, "auction_named_open_hand panel button must exist")

        -- Bid a named contract and verify the session records it.
        local named_res = s:bid_named_contract(2, "mizere")
        assert.is_true(named_res.ok, "bid_named_contract(2, 'mizere') must succeed")

        -- After a named bid wins (only bidder), session reflects named leader.
        assert.are.equal(2, s:current_leader())
    end)
end)
