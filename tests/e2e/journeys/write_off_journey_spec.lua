-- Phase 3.9 write-off / сдача e2e journey. Drives the table scene
-- through a session sitting at the `awaiting_write_off_decision`
-- phase (between talon take and the pass step) and asserts:
--
--   * no modal auto-opens — the inline Write-off button is in the
--     panel instead, sized like any other action button;
--   * the per-seat "Write-offs: %{count} / %{threshold}" scoreboard
--     line still surfaces when `penalties.write_off_streak` is on;
--   * clicking the inline button opens the destructive-action
--     confirmation modal;
--   * **Cancel** closes the modal and leaves the offer open;
--   * **Write off** closes the deal with `reason = "write_off"`
--     and the deal-done banner appears.
--
-- Engine math is pinned in tests/spec/app/session_write_off_spec; this
-- journey verifies the rendered output round-trips to the user.

local journey = require("tests.e2e.support.journey")
local Session = require("app.session")
local rule_config = require("core.rule_config")
local card = require("core.card")
local json = require("app.json")
local marriages_module = require("core.marriages")
local auction_module = require("core.auction")

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

local function find_modal_button(scene, id)
    for _, b in ipairs(scene._modal_buttons or {}) do
        if b.id == id then
            return b
        end
    end
    return nil
end

local function find_panel_button(scene, id)
    for _, b in ipairs(scene._panel_buttons or {}) do
        if b.id == id then
            return b
        end
    end
    return nil
end

local function build_config(overrides)
    local blob = json.decode(rule_config.to_json(rule_config.canonical_russian))
    for section, fields in pairs(overrides or {}) do
        blob[section] = blob[section] or {}
        for k, v in pairs(fields) do
            blob[section][k] = v
        end
    end
    return rule_config.new(blob)
end

local function c(suit, rank)
    return card.new(suit, rank)
end

-- 24-card deal. Seat 2 is the declarer; the actual card mix doesn't
-- matter — the prompt fires before any tricks are played.
local function generic_layout()
    return {
        {
            c("hearts", "9"),
            c("hearts", "J"),
            c("diamonds", "9"),
            c("diamonds", "J"),
            c("clubs", "9"),
            c("clubs", "J"),
            c("spades", "9"),
            c("spades", "J"),
        },
        {
            c("hearts", "A"),
            c("hearts", "10"),
            c("diamonds", "A"),
            c("diamonds", "10"),
            c("clubs", "A"),
            c("clubs", "10"),
            c("spades", "A"),
            c("spades", "10"),
        },
        {
            c("hearts", "Q"),
            c("hearts", "K"),
            c("diamonds", "Q"),
            c("diamonds", "K"),
            c("clubs", "Q"),
            c("clubs", "K"),
            c("spades", "Q"),
            c("spades", "K"),
        },
    }
end

-- Build a session sitting in awaiting_write_off_decision via
-- Session.from_state. Mirrors the natural take_talon path but stops
-- the engine at the prompt so the journey can render and interact
-- with the modal.
local function session_at_write_off_decision(cfg, hands, opts)
    opts = opts or {}
    local pc = cfg.players.count
    local dealer = opts.dealer or 1
    local declarer = opts.declarer or ((dealer % pc) + 1)
    local running_totals = { 0, 0, 0 }
    local holdings = {}
    for seat = 1, pc do
        local suits = marriages_module.detect(hands[seat])
        local total = 0
        for _, suit in ipairs(suits) do
            total = total + (cfg.marriages.values[suit] or 0)
        end
        holdings[seat] = { marriage_total = total }
    end
    local auction = auction_module.new(
        cfg,
        dealer,
        { holdings = holdings, running_totals = running_totals }
    ).auction
    local forehand = (dealer % pc) + 1
    auction = auction_module.bid(auction, forehand, opts.bid or 100).auction
    for seat = 1, pc do
        if seat ~= forehand and auction.status == "in_progress" then
            local r = auction_module.pass(auction, seat)
            if r.ok then
                auction = r.auction
            end
        end
    end
    local marriages = marriages_module.new(cfg).marriages
    return Session.from_state({
        config = cfg,
        seed = 1,
        dealer = dealer,
        hands = hands,
        auction = auction,
        marriages = marriages,
        talon = {
            declarer = declarer,
            final_bid = opts.bid or 100,
            status = "awaiting_pass",
            distribution = "declarer_takes_then_passes",
            hands = hands,
            opponent_count = pc - 1,
            passes_received = {},
        },
        running_totals = running_totals,
        deal_index = 1,
        write_off_counts = opts.write_off_counts,
        awaiting_write_off_decision = {
            declarer = declarer,
            bid = opts.bid or 100,
            split_mode = cfg.bidding.write_off_split,
        },
    })
end

describe("write-off journey", function()
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

    it("renders the inline Write-off button (no auto-modal) at the prompt phase", function()
        local cfg = build_config({ bidding = { write_off = "on" } })
        local s = session_at_write_off_decision(cfg, generic_layout(), {
            dealer = 1,
            declarer = 2,
            bid = 100,
        })
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        j._mock.graphics.clear_recording()
        scene:draw(1024, 720)

        assert.is_nil(scene._modal, "no auto-modal on prompt-phase entry")
        assert.is_not_nil(find_panel_button(scene, "write_off_inline"))
        assert.is_truthy(find_text(j, "Write off"))
    end)

    it("does not surface the inline button when the toggle is off", function()
        local cfg = build_config({ bidding = { write_off = "off" } })
        -- When the toggle is off, the natural flow lands at the talon
        -- phase with no prompt. Drive a Session.new through take_talon
        -- here so we observe the no-prompt branch end-to-end.
        local fresh = Session.new({ seed = 7, dealer = 1, config = cfg })
        assert(fresh:bid(2, 100).ok)
        assert(fresh:pass(3).ok)
        assert(fresh:pass(1).ok)
        assert(fresh:take_talon().ok)
        assert.are.equal("talon", fresh:current_phase())

        local _, scene = build_table_scene_in_mock(fresh)
        scene:draw(1024, 720)
        assert.is_nil(scene._modal)
        assert.is_nil(find_panel_button(scene, "write_off_inline"))
    end)

    it("clicking the inline Write-off button opens the confirmation modal", function()
        local cfg = build_config({ bidding = { write_off = "on" } })
        local s = session_at_write_off_decision(cfg, generic_layout(), {
            dealer = 1,
            declarer = 2,
            bid = 100,
        })
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)

        local inline = find_panel_button(scene, "write_off_inline")
        assert.is_not_nil(inline)
        inline:activate()
        scene:draw(1024, 720)

        assert.are.equal("write_off_prompt", scene._modal)
        assert.is_not_nil(find_modal_button(scene, "write_off_prompt_accept"))
        assert.is_not_nil(find_modal_button(scene, "write_off_prompt_decline"))
        assert.is_truthy(find_text(j, "Write off the contract?"))
        assert.is_truthy(find_text(j, "Cancel"))
    end)

    it("Cancel closes the modal and leaves the offer open", function()
        local cfg = build_config({ bidding = { write_off = "on" } })
        local s = session_at_write_off_decision(cfg, generic_layout(), {
            dealer = 1,
            declarer = 2,
            bid = 100,
        })
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        find_panel_button(scene, "write_off_inline"):activate()
        scene:draw(1024, 720)

        local decline = find_modal_button(scene, "write_off_prompt_decline")
        assert.is_not_nil(decline)
        decline:activate()
        scene:draw(1024, 720)

        assert.is_nil(scene._modal, "modal closed after Cancel")
        assert.is_not_nil(s:write_off_offer_state(), "offer still open")
        assert.is_not_nil(find_panel_button(scene, "write_off_inline"))
        assert.are.equal("awaiting_write_off_decision", s:current_phase())
    end)

    it("confirming Write off closes the deal with reason = write_off", function()
        local cfg = build_config({ bidding = { write_off = "on" } })
        local s = session_at_write_off_decision(cfg, generic_layout(), {
            dealer = 1,
            declarer = 2,
            bid = 100,
        })
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        find_panel_button(scene, "write_off_inline"):activate()
        scene:draw(1024, 720)

        local accept = find_modal_button(scene, "write_off_prompt_accept")
        assert.is_not_nil(accept)
        accept:activate()

        assert.are.equal("deal_done", s:current_phase())
        local dd = s:deal_done()
        assert.are.equal("write_off", dd.reason)
        assert.are.equal(2, dd.declarer)

        scene:draw(1024, 720)
        j._mock.graphics.clear_recording()
        scene:draw(1024, 720)
        assert.is_nil(find_modal_button(scene, "write_off_prompt_accept"))
        assert.is_truthy(find_text(j, "Write-off — declarer conceded mid-deal"))
    end)

    -- Auto-clear path: the inline button vanishes the moment the
    -- offer clears. We drive a fresh Session through bid → take_talon
    -- (which opens the offer) → pass_talon (auto-clears) and assert
    -- the panel re-renders without the inline button.
    it("the inline button disappears once the offer auto-clears", function()
        local cfg = build_config({ bidding = { write_off = "on" } })
        local fresh = Session.new({ seed = 7, dealer = 1, config = cfg })
        assert(fresh:bid(2, 100).ok)
        assert(fresh:pass(3).ok)
        assert(fresh:pass(1).ok)
        assert(fresh:take_talon().ok)
        assert.are.equal("awaiting_write_off_decision", fresh:current_phase())

        local _, scene = build_table_scene_in_mock(fresh)
        scene:draw(1024, 720)
        assert.is_not_nil(find_panel_button(scene, "write_off_inline"))

        local hand = fresh:hands()[2]
        assert(fresh:pass_talon(1, hand[1]).ok)
        scene:draw(1024, 720)

        assert.is_nil(fresh:write_off_offer_state())
        assert.is_nil(find_panel_button(scene, "write_off_inline"))
    end)

    it("renders the per-seat write-off counter while the prompt is open", function()
        local cfg = build_config({
            bidding = { write_off = "on" },
            penalties = {
                write_off_streak = "any_three",
                write_off_streak_threshold = 3,
            },
        })
        local s = session_at_write_off_decision(cfg, generic_layout(), {
            dealer = 1,
            declarer = 2,
            bid = 100,
            write_off_counts = { 0, 1, 0 },
        })
        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        j._mock.graphics.clear_recording()
        scene:draw(1024, 720)

        assert.is_truthy(find_text(j, "Write-offs: 1 / 3"))
    end)

    it("does not render the legacy inline tricks-phase write-off button", function()
        local cfg = build_config({ bidding = { write_off = "on" } })
        -- Build a session at the tricks phase (post-prompt) so any
        -- regression that re-introduces the inline button surfaces.
        local fresh = Session.new({ seed = 7, dealer = 1, config = cfg })
        assert(fresh:bid(2, 100).ok)
        assert(fresh:pass(3).ok)
        assert(fresh:pass(1).ok)
        assert(fresh:take_talon().ok)
        assert(fresh:accept_play().ok)
        local hand = fresh:hands()[2]
        assert(fresh:pass_talon(1, hand[1]).ok)
        hand = fresh:hands()[2]
        assert(fresh:pass_talon(3, hand[1]).ok)
        assert(fresh:skip_raise().ok)
        assert.are.equal("tricks", fresh:current_phase())

        local _, scene = build_table_scene_in_mock(fresh)
        scene:draw(1024, 720)
        assert.is_nil(find_panel_button(scene, "tricks_write_off"))
    end)
end)
