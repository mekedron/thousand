-- End-to-end journey for the Phase 3.6 talon-variants UI. Builds a
-- session at talon-revealed with each toggle exercised, drives the
-- table scene under the journey's mocked Love, and asserts the
-- localised affordances render.

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

local function build_config(overrides)
    local rule_config = require("core.rule_config")
    local talon = {
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
    }
    for k, v in pairs(overrides or {}) do
        talon[k] = v
    end
    -- Round-trip the canonical config through JSON to get a deep-copied
    -- plain table, then patch the talon block. Mirrors the redeal-prompt
    -- journey's approach for sub-section overrides.
    local s = rule_config.to_json(rule_config.canonical_russian)
    local res = rule_config.from_json(s)
    local blob = {
        schema_version = 1,
        cards = res.config.cards,
        players = res.config.players,
        dealing = res.config.dealing,
        talon = talon,
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

local function build_session_at_talon(cfg, hands, talon)
    local Session = require("app.session")
    local auction_module = require("core.auction")
    local marriages_module = require("core.marriages")
    local s = Session.from_state({
        config = cfg,
        seed = 1,
        dealer = 1,
        hands = hands,
        talon_cards = talon,
        auction = auction_module.new(cfg, 1).auction,
        marriages = marriages_module.new(cfg).marriages,
        running_totals = { 0, 0, 0 },
        deal_index = 1,
    })
    -- Drive the auction to completion: forehand (seat 2) bids 100, the
    -- other two seats pass. The session auto-builds the talon and
    -- evaluates any bad-talon offer.
    assert(s:bid(2, 100).ok)
    assert(s:pass(3).ok)
    assert(s:pass(1).ok)
    return s
end

local function low_points_layout()
    local card = require("core.card")
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
    local talon = {
        card.new("spades", "9"),
        card.new("clubs", "9"),
        card.new("diamonds", "9"),
    }
    return { seat1, seat2, seat3 }, talon
end

local function rich_layout()
    local card = require("core.card")
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
        card.new("spades", "9"),
        card.new("clubs", "9"),
    }
    local seat3 = {
        card.new("diamonds", "9"),
        card.new("hearts", "9"),
        card.new("spades", "10"),
        card.new("clubs", "10"),
        card.new("diamonds", "10"),
        card.new("hearts", "10"),
        card.new("spades", "A"),
    }
    local talon = {
        card.new("clubs", "A"),
        card.new("diamonds", "A"),
        card.new("hearts", "A"),
    }
    return { seat1, seat2, seat3 }, talon
end

describe("e2e: talon variants", function()
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

    it("renders Concede + Buyback buttons under pass_the_talon + buyback", function()
        local cfg = build_config({
            pass_the_talon = "on",
            buyback = "on",
            buyback_penalty = 80,
        })
        local hands, talon = rich_layout()
        local s = build_session_at_talon(cfg, hands, talon)
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        _G.love.graphics.clear_recording()
        scene:draw(1024, 720)

        local concede_label = j:find_localised("scene.table.talon.concede_button")
        assert.is_not_nil(find_text(j, concede_label), "concede button should be visible")

        local buyback_label = j:find_localised("scene.table.talon.buyback_button", { penalty = 80 })
        assert.is_not_nil(find_text(j, buyback_label), "buyback button should be visible")
    end)

    it("renders the bad-talon modal under bad_talon_redeal = any_contract", function()
        local cfg = build_config({ bad_talon_redeal = "any_contract" })
        local hands, talon = low_points_layout()
        local s = build_session_at_talon(cfg, hands, talon)
        assert.are.equal("awaiting_bad_talon_decision", s:current_phase())

        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        _G.love.graphics.clear_recording()
        scene:draw(1024, 720)

        local title = j:find_localised("scene.table.bad_talon_prompt.title")
        assert.is_not_nil(find_text(j, title), "bad-talon modal title should be visible")

        local body = j:find_localised("scene.table.bad_talon_prompt.body", { points = 0 })
        assert.is_not_nil(find_text(j, body), "bad-talon modal body should be visible")

        local accept = j:find_localised("scene.table.bad_talon_prompt.accept")
        assert.is_not_nil(find_text(j, accept), "accept button should be visible")

        local decline = j:find_localised("scene.table.bad_talon_prompt.decline")
        assert.is_not_nil(find_text(j, decline), "decline button should be visible")
    end)

    it("decline_bad_talon_redeal clears the modal and unblocks take_talon", function()
        local cfg = build_config({ bad_talon_redeal = "any_contract" })
        local hands, talon = low_points_layout()
        local s = build_session_at_talon(cfg, hands, talon)
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        scene:_do_decline_bad_talon_redeal()
        scene:_close_bad_talon_modal()
        scene:draw(1024, 720)

        assert.are.equal("talon", s:current_phase())
        assert.is_nil(s:bad_talon_offer_state())
        local log = s:bad_talon_log()
        assert.are.equal(1, #log)
        assert.is_false(log[1].accepted)
    end)
end)
