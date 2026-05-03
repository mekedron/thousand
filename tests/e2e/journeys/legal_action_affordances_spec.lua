-- End-to-end journey for legal-action affordances. Builds a session that
-- has reached the tricks phase, primes a single trick lead so the next
-- seat is constrained by must-follow, then drives a tap on an illegal
-- card and asserts that the localised must-follow toast surfaces. A
-- second case asserts the dim affordance: the illegal card draws the
-- ILLEGAL_DIM rectangle while the legal cards do not.
--
-- We construct a fresh scene_manager + table_scene under the same
-- love-mock the journey installed (mirrors end_of_game_render_spec.lua)
-- because main.lua's manager is a layer-4 local — exposing it to the
-- test would only exist for the test's benefit.

local journey = require("tests.e2e.support.journey")

local function find_first_illegal_card(scene)
    for i, entry in ipairs(scene._hand_card_rects) do
        if entry.legal == false then
            return i, entry
        end
    end
    return nil, nil
end

local function find_first_legal_card(scene)
    for i, entry in ipairs(scene._hand_card_rects) do
        if entry.legal then
            return i, entry
        end
    end
    return nil, nil
end

-- Count fill rectangles painted at the exact (x, y, w, h) of a card.
-- A legal card draws one (the cream background from cards.draw_face_up);
-- an illegal card draws two (background + ILLEGAL_DIM overlay). The
-- mock's `setColor` path is separate from the rect op, so this count is
-- the cleanest single-axis signal that the dim was applied.
local function fill_rects_at(mock, x, y, w, h)
    local n = 0
    for _, op in ipairs(mock.graphics.recording()) do
        if
            op.op == "rectangle"
            and op.mode == "fill"
            and op.x == x
            and op.y == y
            and op.w == w
            and op.h == h
        then
            n = n + 1
        end
    end
    return n
end

local function drive_to_tricks(seed)
    local Session = require("app.session")
    local s = Session.new({ seed = seed, dealer = 1 })
    assert(s:bid(2, 100).ok)
    assert(s:pass(3).ok)
    assert(s:pass(1).ok)
    assert(s:take_talon().ok)
    -- Phase 3.9: canonical Russian opens the pre-tricks write-off
    -- prompt after take. Decline so the deal flows into the pass step.
    if s:current_phase() == "awaiting_write_off_decision" then
        assert(s:accept_play().ok)
    end
    local hand = s:hands()[2]
    assert(s:pass_talon(1, hand[1]).ok)
    hand = s:hands()[2]
    assert(s:pass_talon(3, hand[1]).ok)
    assert(s:skip_raise().ok)
    return s
end

local function lead_first_legal(s)
    local leader = s:current_turn()
    local card = s:legal_cards(leader)[1]
    assert(s:play(leader, card).ok)
end

describe("e2e: legal-action affordances", function()
    local j, t

    before_each(function()
        j = journey.start({ locale = "en", width = 1024, height = 720 })
        j:step()
        t = j._i18n.t
    end)

    after_each(function()
        if j then
            j:stop()
        end
    end)

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

    it("dims illegal cards while legal cards stay undimmed in the active hand", function()
        local s = drive_to_tricks(42)
        lead_first_legal(s)

        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)

        _G.love.graphics.clear_recording()
        scene:draw(1024, 720)

        local illegal_index, illegal_entry = find_first_illegal_card(scene)
        local legal_index, legal_entry = find_first_legal_card(scene)
        assert.is_not_nil(
            illegal_index,
            "test fixture should produce at least one illegal card after a constrained lead"
        )
        assert.is_not_nil(legal_index, "active hand should hold at least one legal card")

        local illegal_fills = fill_rects_at(
            j._mock,
            illegal_entry.rect.x,
            illegal_entry.rect.y,
            illegal_entry.rect.w,
            illegal_entry.rect.h
        )
        local legal_fills = fill_rects_at(
            j._mock,
            legal_entry.rect.x,
            legal_entry.rect.y,
            legal_entry.rect.w,
            legal_entry.rect.h
        )
        assert.is_true(
            illegal_fills >= 2,
            "illegal card should draw card-bg + ILLEGAL_DIM (>= 2 fills), got " .. illegal_fills
        )
        assert.are.equal(
            1,
            legal_fills,
            "legal card should draw only the card background (no overlay)"
        )
    end)

    it("tapping an illegal card surfaces the localised must-follow toast", function()
        local s = drive_to_tricks(42)
        lead_first_legal(s)

        local _, scene = build_table_scene_in_mock(s)
        scene:draw(1024, 720)
        dismiss_curtain_state(scene)
        scene:draw(1024, 720)

        local _, illegal_entry = find_first_illegal_card(scene)
        assert.is_not_nil(illegal_entry, "expected an illegal card to tap")
        local cx = illegal_entry.rect.x + illegal_entry.rect.w * 0.5
        local cy = illegal_entry.rect.y + illegal_entry.rect.h * 0.5

        scene:mousepressed(cx, cy, 1)
        scene:mousereleased(cx, cy, 1)

        _G.love.graphics.clear_recording()
        scene:draw(1024, 720)

        local view = scene._view_model
        local lead_suit = view.current_trick and view.current_trick.lead_suit
        assert.is_not_nil(lead_suit, "the lead trick should expose its lead suit on the view-model")
        assert.is_not_nil(
            j._mock.graphics.find_text(
                t("scene.table.toast.must_follow", { suit = t("card.suit." .. lead_suit) })
            ),
            "expected the localised must-follow toast after tapping an illegal card"
        )
    end)
end)
