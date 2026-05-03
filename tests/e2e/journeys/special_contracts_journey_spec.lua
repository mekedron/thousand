-- Phase 3.6 special-contracts e2e journey. Drives the table scene
-- through a session whose auction terminates with each named contract
-- (mizère / slam / open hand) and asserts:
--
--   * the localised active-contract banner appears in the recording;
--   * under open-hand, the declarer's hand renders face-up via the
--     view-model's `declarer_hand_open` + `open_hand_seat` flags;
--   * the talon construction succeeds (the deal becomes playable),
--     dropping the previous `not_yet_supported_named_contract` stub.
--
-- The harness uses the journey mock for `love.*`; engine math and the
-- view-model's named-contract block are pinned in unit + integration
-- specs.

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

local function build_config(specials_overrides)
    local rule_config = require("core.rule_config")
    local json = require("app.json")
    -- Round-trip through JSON to obtain a plain Lua table without the
    -- rule-config proxy (which prevents pairs() iteration over fields).
    local blob = json.decode(rule_config.to_json(rule_config.canonical_russian))
    blob.bidding.named_contracts = "on"
    for k, v in pairs(specials_overrides or {}) do
        blob.specials[k] = v
    end
    return rule_config.new(blob)
end

local function build_named_session_at_talon(cfg, named)
    local Session = require("app.session")
    local auction_module = require("core.auction")
    local marriages_module = require("core.marriages")
    local card = require("core.card")
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
    local auction = auction_module.new(cfg, 1).auction
    local marriages = marriages_module.new(cfg).marriages
    local s = Session.from_state({
        config = cfg,
        seed = 42,
        dealer = 1,
        hands = { seat1, seat2, seat3 },
        talon_cards = talon_cards,
        auction = auction,
        marriages = marriages,
        running_totals = { 0, 0, 0 },
        deal_index = 1,
    })
    -- Drive the auction: forehand (seat 2) bids the named contract,
    -- the other two pass. Auction terminates with a named winner; the
    -- session records `_active_named_contract` and constructs the
    -- talon.
    assert(s:bid_named_contract(2, named.kind).ok)
    assert(s:pass(3).ok)
    assert(s:pass(1).ok)
    return s
end

describe("special contracts journey", function()
    it("renders the mizère banner above the table during the talon phase", function()
        local j = journey.start({ locale = "en", width = 1024, height = 720 })
        j:step()
        local cfg = build_config({ mizere = "on" })
        local s = build_named_session_at_talon(cfg, { kind = "mizere" })
        assert.are.equal("mizere", s:active_named_contract().kind)
        assert.are.equal("talon", s:current_phase())
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        j._mock.graphics.clear_recording()
        scene:draw(1024, 720)

        assert.is_truthy(find_text(j, "Mizère"))
        -- The view-model carries the localised value; the rendered
        -- banner interpolates the contract value (120 default).
        assert.is_truthy(find_text(j, "120"))
    end)

    it("renders the slam banner and respects custom slam_contract_value", function()
        local j = journey.start({ locale = "en", width = 1024, height = 720 })
        j:step()
        local cfg = build_config({ slam_contract = "on", slam_contract_value = 300 })
        local s = build_named_session_at_talon(cfg, { kind = "slam" })
        assert.are.equal("slam", s:active_named_contract().kind)
        assert.are.equal(300, s:active_named_contract().value)
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        j._mock.graphics.clear_recording()
        scene:draw(1024, 720)

        assert.is_truthy(find_text(j, "Slam"))
        assert.is_truthy(find_text(j, "300"))
    end)

    it("renders the open-hand banner and exposes the declarer-hand-open flag", function()
        local j = journey.start({ locale = "en", width = 1024, height = 720 })
        j:step()
        local cfg = build_config({ open_hand = "on" })
        local s = build_named_session_at_talon(cfg, { kind = "open_hand" })
        assert.are.equal("open_hand", s:active_named_contract().kind)
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        j._mock.graphics.clear_recording()
        scene:draw(1024, 720)

        assert.is_truthy(find_text(j, "Open hand"))
        local vm = scene._view_model
        assert.is_table(vm)
        assert.is_true(vm.declarer_hand_open)
        assert.are.equal(2, vm.open_hand_seat)
    end)

    it(
        "the auction panel renders all three named-contract buttons under named_contracts",
        function()
            local j = journey.start({ locale = "en", width = 1024, height = 720 })
            j:step()
            local cfg = build_config({ mizere = "on", slam_contract = "on", open_hand = "on" })
            local Session = require("app.session")
            local auction_module = require("core.auction")
            local marriages_module = require("core.marriages")
            local card = require("core.card")
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
                    card.new("hearts", "Q"),
                    card.new("spades", "J"),
                    card.new("clubs", "J"),
                    card.new("diamonds", "J"),
                    card.new("hearts", "J"),
                    card.new("spades", "A"),
                    card.new("clubs", "A"),
                },
                {
                    card.new("diamonds", "A"),
                    card.new("hearts", "A"),
                    card.new("spades", "10"),
                    card.new("clubs", "10"),
                    card.new("diamonds", "10"),
                    card.new("hearts", "10"),
                    card.new("hearts", "9"),
                },
            }
            local s = Session.from_state({
                config = cfg,
                seed = 1,
                dealer = 1,
                hands = hands,
                talon_cards = {
                    card.new("spades", "9"),
                    card.new("clubs", "9"),
                    card.new("diamonds", "9"),
                },
                auction = auction_module.new(cfg, 1).auction,
                marriages = marriages_module.new(cfg).marriages,
                running_totals = { 0, 0, 0 },
                deal_index = 1,
            })
            local _, scene = build_table_scene_in_mock(s)
            scene:draw(1024, 720)
            dismiss_curtain_state(scene)

            j._mock.graphics.clear_recording()
            scene:draw(1024, 720)

            assert.is_truthy(find_text(j, "Mizère"))
            assert.is_truthy(find_text(j, "Slam"))
            assert.is_truthy(find_text(j, "Open hand"))
        end
    )
end)
