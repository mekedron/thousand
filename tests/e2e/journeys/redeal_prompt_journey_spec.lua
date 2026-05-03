-- End-to-end journey for the Phase 3.6 redeal prompt. Builds a session
-- whose pre-auction state holds an open weak-hand redeal offer and
-- drives the table scene under the journey's mocked Love so the
-- localised dialog body and Accept/Decline buttons render. We use the
-- "scene constructed under the mock" pattern (mirrors
-- legal_action_affordances_spec.lua + end_of_game_render_spec.lua)
-- because we need to inject specific hands — a fresh shuffle would not
-- reliably trigger the entitlement.

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

local function build_session_with_weak_hand_offer()
    local Session = require("app.session")
    local rule_config = require("core.rule_config")
    local card = require("core.card")
    local auction_module = require("core.auction")
    local marriages_module = require("core.marriages")

    -- Canonical Russian + weak_hand_redeal = "strict".
    local s = rule_config.to_json(rule_config.canonical_russian)
    local res = rule_config.from_json(s)
    local cfg = rule_config.new({
        schema_version = 1,
        cards = res.config.cards,
        players = res.config.players,
        dealing = {
            four_nine_redeal = "off",
            three_nine_redeal = "off",
            four_jack_redeal = "off",
            weak_hand_redeal = "strict",
            weak_hand_threshold = 14,
            two_nines_in_talon_redeal = "off",
            misdeal_handling = "standard",
            misdeal_flat_penalty = 20,
            all_pass_handling = "redeal",
            deck_size = "24",
            cut_deck_nine_jack_penalty = "off",
        },
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
    })

    local hands = {
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
            -- Strict-weak: only 9s and 10s.
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
    }
    local talon = {
        card.new("clubs", "A"),
        card.new("diamonds", "A"),
        card.new("hearts", "A"),
    }
    return Session.from_state({
        config = cfg,
        seed = 1,
        dealer = 1,
        hands = hands,
        talon_cards = talon,
        auction = auction_module.new(cfg, 1).auction,
        marriages = marriages_module.new(cfg).marriages,
        running_totals = { 0, 0, 0 },
        deal_index = 1,
        redeal_offer = { seat = 2, kind = "weak_hand", forced = false },
    })
end

describe("e2e: redeal prompt", function()
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

    it("renders the localised body and Accept/Decline buttons", function()
        local s = build_session_with_weak_hand_offer()
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        _G.love.graphics.clear_recording()
        scene:draw(1024, 720)

        local body = j:find_localised("scene.table.redeal_prompt.body.weak_hand", { seat = 2 })
        assert.is_not_nil(find_text(j, body), "weak_hand body should be visible")

        local accept_label = j:find_localised("scene.table.redeal_prompt.accept")
        assert.is_not_nil(find_text(j, accept_label), "accept button should be visible")

        local decline_label = j:find_localised("scene.table.redeal_prompt.decline")
        assert.is_not_nil(find_text(j, decline_label), "decline button should be visible")
    end)

    it("decline_redeal clears the prompt and starts the auction", function()
        local s = build_session_with_weak_hand_offer()
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        -- Driving the click goes through the modal's button which calls
        -- _do_decline_redeal and then _close_redeal_modal. We invoke
        -- _do_decline_redeal directly to avoid layout-coordinate tests
        -- pinning specific pixel regions; the existing legal-action
        -- affordances spec uses the same direct-invocation pattern.
        scene:_do_decline_redeal()
        scene:_close_redeal_modal()
        scene:draw(1024, 720)

        assert.are.equal("auction", s:current_phase())
        assert.is_nil(s:redeal_offer())
        local log = s:redeal_log()
        assert.are.equal(1, #log)
        assert.is_false(log[1].accepted)
    end)
end)
