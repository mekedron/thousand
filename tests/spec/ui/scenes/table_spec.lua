-- Unit coverage for the table scene. Builds a stub manager + session and
-- asserts the scene draws the expected localised text labels and the
-- right number of card rectangles in the bottom strip. Avoids the full
-- e2e harness so we can poke at intermediate state directly.

local love_mock = require("tests.e2e.support.love_mock")

local function reset_modules()
    local to_reset = {
        "ui.cards",
        "ui.scenes.table",
        "ui.button",
        "ui.layout",
        "app.i18n",
        "app.session",
        "app.settings",
        "app.json",
        "app.table_view_model",
    }
    for _, mod in ipairs(to_reset) do
        package.loaded[mod] = nil
    end
end

local function fake_manager(session)
    return {
        switch_to = function() end,
        session = function()
            return session
        end,
        is_game_active = function()
            return session ~= nil
        end,
    }
end

local function find_text(mock, needle)
    for _, op in ipairs(mock.graphics.recording()) do
        if op.op == "text" and op.text:find(needle, 1, true) then
            return op
        end
    end
    return nil
end

local function count_face_up_card_rects(mock, region)
    local count = 0
    for _, op in ipairs(mock.graphics.recording()) do
        if
            op.op == "rectangle"
            and op.mode == "fill"
            and op.w >= 30
            and op.w <= 120
            and op.h >= 40
            and op.h <= 200
            and op.y >= region.y
            and op.y + op.h <= region.y + region.h + 4
        then
            count = count + 1
        end
    end
    return count
end

describe("ui.scenes.table", function()
    local mock, scene, session, layout, t

    before_each(function()
        reset_modules()
        mock = love_mock.new({ width = 1024, height = 720 })
        mock:install()
        local i18n = require("app.i18n")
        i18n._reset()
        i18n._set_logger(function() end)
        i18n.set_locale("en")
        t = i18n.t

        local Session = require("app.session")
        session = Session.new({ seed = 42, dealer = 1 })

        local table_scene = require("ui.scenes.table")
        scene = table_scene.new(fake_manager(session))
        scene:enter(nil, nil)
        layout = require("ui.layout")
    end)

    after_each(function()
        if mock then
            mock:restore()
        end
        reset_modules()
    end)

    it("renders the scoreboard, hand and centre labels", function()
        scene:draw(1024, 720)
        assert.is_not_nil(find_text(mock, t("scene.table.scoreboard.title")), "scoreboard title")
        assert.is_not_nil(find_text(mock, t("scene.table.bid.label")), "bid label")
        assert.is_not_nil(find_text(mock, t("scene.table.turn.label")), "turn label")
        assert.is_not_nil(find_text(mock, t("scene.table.trump.label")), "trump label")
        assert.is_not_nil(find_text(mock, t("scene.table.phase.label")), "phase label")
        assert.is_not_nil(find_text(mock, t("scene.table.talon.label")), "talon label")
        -- Active player (forehand 2 with dealer 1) renders at the bottom
        -- as the "self" hand. Seats 1 and 3 are opponents and appear by
        -- their player-N label. Seat 2 does NOT appear by its player-N
        -- label because the active hand is rendered as "Your hand".
        assert.is_not_nil(find_text(mock, t("scene.table.player_label.you")), "your-hand label")
        assert.is_not_nil(
            find_text(mock, t("scene.table.player_label.other", { n = 1 })),
            "Player 1 label"
        )
        assert.is_not_nil(
            find_text(mock, t("scene.table.player_label.other", { n = 3 })),
            "Player 3 label"
        )
    end)

    it("renders the auction phase indicator on a fresh session", function()
        scene:draw(1024, 720)
        assert.is_not_nil(find_text(mock, t("scene.table.phase.auction")))
    end)

    it("renders the back-to-menu button", function()
        scene:draw(1024, 720)
        assert.is_not_nil(find_text(mock, t("scene.table.back_to_menu")))
    end)

    it("renders 7 face-up card rectangles in the bottom strip for the active hand", function()
        scene:draw(1024, 720)
        local regions = layout.table_regions(1024, 720)
        local n = count_face_up_card_rects(mock, regions.hand)
        assert.is_true(
            n >= 7,
            "expected at least 7 face-up card rects in the hand region, got " .. n
        )
    end)

    it("falls back to dim em-dash when no bid has been placed", function()
        scene:draw(1024, 720)
        assert.is_not_nil(find_text(mock, t("scene.table.bid.none")))
    end)

    it("does not crash and re-renders after a window resize", function()
        scene:draw(1024, 720)
        mock.graphics.clear_recording()
        scene:draw(800, 600)
        assert.is_not_nil(find_text(mock, t("scene.table.scoreboard.title")))
    end)

    it("survives a session-less manager (defensive draw)", function()
        reset_modules()
        local i18n = require("app.i18n")
        i18n._reset()
        i18n._set_logger(function() end)
        i18n.set_locale("en")
        local table_scene = require("ui.scenes.table")
        local s = table_scene.new(fake_manager(nil))
        s:enter(nil, nil)
        assert.has_no.errors(function()
            s:draw(800, 600)
        end)
    end)

    it("renders the bid panel with bid amount labels and a pass button", function()
        scene:draw(1024, 720)
        -- Auction phase shows the opening minimum (100) as the first
        -- bid button.
        assert.is_not_nil(
            find_text(mock, t("scene.table.auction.bid_button", { amount = 100 })),
            "bid 100 button label"
        )
        assert.is_not_nil(find_text(mock, t("scene.table.auction.pass_button")), "pass button")
    end)

    it("auction your-turn label renders for the active player", function()
        scene:draw(1024, 720)
        assert.is_not_nil(find_text(mock, t("scene.table.auction.your_turn")))
    end)

    it("transitions to the talon take-button when auction terminates", function()
        assert(session:bid(2, 100).ok)
        assert(session:pass(3).ok)
        assert(session:pass(1).ok)
        scene:draw(1024, 720)
        assert.is_not_nil(find_text(mock, t("scene.table.talon.take_button")), "take talon button")
    end)

    it("shows the deal_done banner after scoring", function()
        -- Drive a deal to completion through legal_cards picks.
        assert(session:bid(2, 100).ok)
        assert(session:pass(3).ok)
        assert(session:pass(1).ok)
        assert(session:take_talon().ok)
        local hand = session:hands()[2]
        assert(session:pass_talon(1, hand[1]).ok)
        hand = session:hands()[2]
        assert(session:pass_talon(3, hand[1]).ok)
        assert(session:skip_raise().ok)
        while session:current_phase() == "tricks" do
            local p = session:current_turn()
            local card = session:legal_cards(p)[1]
            assert(session:play(p, card).ok)
        end
        scene:draw(1024, 720)
        assert.is_not_nil(
            find_text(mock, t("scene.table.deal_done.scored")),
            "deal complete banner"
        )
        assert.is_not_nil(find_text(mock, t("scene.table.deal_done.next_deal")), "next deal button")
    end)

    it("shows a toast when a mutator returns an engine error", function()
        -- Bidding off-turn returns not_your_turn; the scene should
        -- surface that as a localised toast.
        local r = session:bid(1, 100)
        assert.is_false(r.ok)
        -- Drive the toast surface directly via the public mutator path.
        scene:_invoke(r)
        scene:draw(1024, 720)
        assert.is_not_nil(
            find_text(mock, t("scene.table.toast.not_your_turn")),
            "not-your-turn toast"
        )
    end)

    describe("legal-action affordances", function()
        local function fake_envelope(code, extra)
            local err = { code = code, message = code }
            if extra then
                for k, v in pairs(extra) do
                    err[k] = v
                end
            end
            return { ok = false, error = err }
        end

        it("must_follow_violation surfaces the localised must-follow toast", function()
            scene:_invoke(fake_envelope("must_follow_violation", { led_suit = "hearts" }))
            scene:draw(1024, 720)
            assert.is_not_nil(
                find_text(
                    mock,
                    t("scene.table.toast.must_follow", { suit = t("card.suit.hearts") })
                ),
                "must-follow toast with the led-suit glyph"
            )
        end)

        it("must_beat_violation surfaces the localised must-beat toast", function()
            scene:_invoke(fake_envelope("must_beat_violation", { led_suit = "diamonds" }))
            scene:draw(1024, 720)
            assert.is_not_nil(
                find_text(
                    mock,
                    t("scene.table.toast.must_beat", { suit = t("card.suit.diamonds") })
                ),
                "must-beat toast with the led-suit glyph"
            )
        end)

        it("must_trump_violation surfaces the localised must-trump toast", function()
            scene:_invoke(fake_envelope("must_trump_violation", { trump = "spades" }))
            scene:draw(1024, 720)
            local glyph = t("card.suit.spades")
            assert.is_not_nil(
                find_text(mock, t("scene.table.toast.must_trump", { suit = glyph })),
                "must-trump toast with the trump-suit glyph"
            )
        end)

        it("must_overtrump_violation surfaces the localised must-overtrump toast", function()
            scene:_invoke(fake_envelope("must_overtrump_violation", { trump = "clubs" }))
            scene:draw(1024, 720)
            assert.is_not_nil(
                find_text(
                    mock,
                    t("scene.table.toast.must_overtrump", { suit = t("card.suit.clubs") })
                ),
                "must-overtrump toast with the trump-suit glyph"
            )
        end)

        it("card_not_in_hand surfaces its own localised toast", function()
            scene:_invoke(fake_envelope("card_not_in_hand"))
            scene:draw(1024, 720)
            assert.is_not_nil(
                find_text(mock, t("scene.table.toast.card_not_in_hand")),
                "card-not-in-hand toast"
            )
        end)

        it("falls back to the generic illegal_play toast for unknown engine codes", function()
            scene:_invoke(fake_envelope("future_unknown_code", { message = "engine said no" }))
            scene:draw(1024, 720)
            assert.is_not_nil(
                find_text(mock, t("scene.table.toast.illegal_play", { reason = "engine said no" })),
                "fallback illegal_play toast"
            )
        end)

        it("hover does not lift an illegal card", function()
            -- Drive the session into a state where the active player has
            -- both clubs (led suit) and at least one off-suit card; the
            -- engine then marks the off-suit card illegal, and the scene
            -- must NOT lift it under hover.
            reset_modules()
            local i18n = require("app.i18n")
            i18n._reset()
            i18n._set_logger(function() end)
            i18n.set_locale("en")
            local Session = require("app.session")
            local view_model = require("app.table_view_model")

            local s = Session.new({ seed = 42, dealer = 1 })
            assert(s:bid(2, 100).ok)
            assert(s:pass(3).ok)
            assert(s:pass(1).ok)
            assert(s:take_talon().ok)
            local hand = s:hands()[2]
            assert(s:pass_talon(1, hand[1]).ok)
            hand = s:hands()[2]
            assert(s:pass_talon(3, hand[1]).ok)
            assert(s:skip_raise().ok)

            -- Lead a card so the next seat's hand is constrained by
            -- must-follow. Pick the leader's first legal card.
            local leader = s:current_turn()
            local leader_card = s:legal_cards(leader)[1]
            assert(s:play(leader, leader_card).ok)

            -- Construct a manager whose session() returns a wrapper:
            -- the active hand for the new turn is what matters. Build
            -- the scene against `s` directly.
            local table_scene = require("ui.scenes.table")
            local sc = table_scene.new(fake_manager(s))
            sc:enter(nil, nil)
            -- Suppress the privacy curtain so the hover test can see
            -- the active hand.
            sc._curtain = nil
            sc._last_revealed_seat = s:current_turn()
            sc._input_mode = "mouse"

            local view = view_model.from_session(s)
            local turn = view.turn_player
            local active_hand = view.hands[turn]
            assert.is_not_nil(active_hand.card_legality, "active hand should expose card_legality")

            local illegal_index
            for i, legal in ipairs(active_hand.card_legality) do
                if legal == false then
                    illegal_index = i
                    break
                end
            end
            assert.is_not_nil(
                illegal_index,
                "test fixture should produce at least one illegal card after a constrained lead"
            )

            sc._hovered_card_index = illegal_index
            mock.graphics.clear_recording()
            sc:draw(1024, 720)

            -- After the draw, the scene's _hand_card_rects[i] holds the
            -- base rect (.rect.y) for that card. If hover had lifted the
            -- card, an extra fill rectangle would have appeared at
            -- (rect.y - CARD_HOVER_LIFT). Assert no such rectangle was
            -- drawn for the illegal card's column.
            local entry = sc._hand_card_rects[illegal_index]
            assert.is_not_nil(entry, "illegal card should have a recorded hand rect")
            local base_y = entry.rect.y
            local lifted_y = base_y - 12 -- CARD_HOVER_LIFT in the scene
            local saw_lift = false
            for _, op in ipairs(mock.graphics.recording()) do
                if
                    op.op == "rectangle"
                    and op.mode == "fill"
                    and op.x == entry.rect.x
                    and op.w == entry.rect.w
                    and op.y == lifted_y
                then
                    saw_lift = true
                    break
                end
            end
            assert.is_false(saw_lift, "illegal card should not lift under hover")
        end)
    end)

    it("opens the marriage modal when active player taps K of a marriage suit", function()
        reset_modules()
        local i18n = require("app.i18n")
        i18n._reset()
        i18n._set_logger(function() end)
        i18n.set_locale("en")
        local Session = require("app.session")

        -- seed=1 gives declarer 2 a spades K+Q after the talon take.
        local s = Session.new({ seed = 1, dealer = 1 })
        assert(s:bid(2, 100).ok)
        assert(s:bid(3, 105).ok)
        assert(s:pass(1).ok)
        assert(s:bid(2, 120).ok)
        assert(s:pass(3).ok)
        assert(s:take_talon().ok)
        local hand = s:hands()[2]
        local function safe_pass(h)
            for _, c in ipairs(h) do
                if not (c.suit == "spades" and (c.rank == "K" or c.rank == "Q")) then
                    return c
                end
            end
        end
        assert(s:pass_talon(1, safe_pass(hand)).ok)
        hand = s:hands()[2]
        assert(s:pass_talon(3, safe_pass(hand)).ok)
        assert(s:skip_raise().ok)

        local table_scene = require("ui.scenes.table")
        local sc = table_scene.new(fake_manager(s))
        sc:enter(nil, nil)
        sc:draw(1024, 720)
        -- The privacy curtain greets every fresh entry; dismiss it before
        -- clicking the K of spades, otherwise the tap just dismisses the
        -- curtain.
        sc._curtain = nil
        sc._last_revealed_seat = sc._view_model and sc._view_model.turn_player

        -- Find the K of spades rect; tap it.
        local king_rect
        for _, entry in ipairs(sc._hand_card_rects) do
            if entry.card.suit == "spades" and entry.card.rank == "K" then
                king_rect = entry.rect
                break
            end
        end
        assert.is_not_nil(king_rect, "K of spades rect was not produced")

        sc:mousepressed(king_rect.x + 4, king_rect.y + 4, 1)
        sc:mousereleased(king_rect.x + 4, king_rect.y + 4, 1)
        sc:draw(1024, 720)

        local prompt =
            find_text(mock, t("scene.table.marriage.prompt", { suit = t("card.suit.spades") }))
        assert.is_not_nil(prompt, "marriage prompt did not render")
    end)

    describe("privacy curtain", function()
        local function dismiss_curtain(s)
            -- State-level dismiss: matches what _close_curtain does. Used
            -- by tests that want to drive the table past the first
            -- between-turns pause without simulating a click.
            s._curtain = nil
            if s._view_model and s._view_model.turn_player then
                s._last_revealed_seat = s._view_model.turn_player
            end
        end

        it("raises the curtain on a fresh table for the forehand", function()
            scene:draw(1024, 720)
            -- Forehand 2 with dealer 1 is the first non-nil current_turn.
            assert.is_not_nil(
                find_text(mock, t("scene.table.privacy.prompt", { n = 2 })),
                "expected privacy prompt for the forehand on first frame"
            )
            assert.is_not_nil(
                find_text(mock, t("scene.table.privacy.subtitle")),
                "expected privacy subtitle"
            )
            assert.is_not_nil(
                find_text(mock, t("scene.table.privacy.ready_button")),
                "expected Ready button label"
            )
        end)

        it("dismisses the curtain when Ready is pressed", function()
            scene:draw(1024, 720)
            local ready = scene._curtain_button
            assert.is_not_nil(ready, "expected a curtain Ready button after first draw")
            local cx = ready.x + ready.w * 0.5
            local cy = ready.y + ready.h * 0.5
            scene:mousepressed(cx, cy, 1)
            scene:mousereleased(cx, cy, 1)
            mock.graphics.clear_recording()
            scene:draw(1024, 720)
            assert.is_nil(
                find_text(mock, t("scene.table.privacy.prompt", { n = 2 })),
                "curtain prompt should be gone after Ready"
            )
            assert.is_nil(scene._curtain, "scene._curtain should be cleared")
        end)

        it("dismisses the curtain on a tap anywhere on the backdrop", function()
            scene:draw(1024, 720)
            assert.is_not_nil(scene._curtain, "expected curtain up before tap-anywhere")
            -- (10, 10) is well outside the centred panel for 1024x720.
            scene:mousepressed(10, 10, 1)
            scene:mousereleased(10, 10, 1)
            assert.is_nil(scene._curtain, "scene._curtain should clear after a tap-anywhere")
            mock.graphics.clear_recording()
            scene:draw(1024, 720)
            assert.is_nil(
                find_text(mock, t("scene.table.privacy.prompt", { n = 2 })),
                "curtain prompt should be gone after a tap-anywhere"
            )
        end)

        it("dismisses the curtain on Enter / Space", function()
            scene:draw(1024, 720)
            assert.is_not_nil(scene._curtain, "expected curtain up before Enter")
            scene:keypressed("return")
            assert.is_nil(scene._curtain, "scene._curtain should clear after Enter")
            mock.graphics.clear_recording()
            scene:draw(1024, 720)
            assert.is_nil(
                find_text(mock, t("scene.table.privacy.prompt", { n = 2 })),
                "Enter should dismiss the curtain via the Ready button"
            )
        end)

        it("re-raises the curtain after a card play changes the turn", function()
            scene:draw(1024, 720)
            dismiss_curtain(scene)

            assert(session:bid(2, 100).ok)
            assert(session:pass(3).ok)
            assert(session:pass(1).ok)
            assert(session:take_talon().ok)
            local hand = session:hands()[2]
            assert(session:pass_talon(1, hand[1]).ok)
            hand = session:hands()[2]
            assert(session:pass_talon(3, hand[1]).ok)
            assert(session:skip_raise().ok)
            -- All of the above keep the declarer on turn — no curtain.
            local card = session:legal_cards(2)[1]
            assert(session:play(2, card).ok)

            mock.graphics.clear_recording()
            scene:draw(1024, 720)
            assert.is_not_nil(
                find_text(mock, t("scene.table.privacy.prompt", { n = 3 })),
                "expected curtain for seat 3 after the first card play"
            )
        end)

        it("Esc during the curtain returns to the menu", function()
            local switched_to
            local recording_manager = {
                switch_to = function(_self, id)
                    switched_to = id
                end,
                session = function()
                    return session
                end,
                is_game_active = function()
                    return true
                end,
            }
            local table_scene = require("ui.scenes.table")
            local sc = table_scene.new(recording_manager)
            sc:enter(nil, nil)
            sc:draw(1024, 720)
            assert.is_not_nil(sc._curtain, "expected curtain to be up before Esc")
            sc:keypressed("escape")
            assert.are.equal("menu", switched_to)
        end)

        it("does not show a curtain in the deal_done phase", function()
            assert(session:bid(2, 100).ok)
            assert(session:pass(3).ok)
            assert(session:pass(1).ok)
            assert(session:take_talon().ok)
            local hand = session:hands()[2]
            assert(session:pass_talon(1, hand[1]).ok)
            hand = session:hands()[2]
            assert(session:pass_talon(3, hand[1]).ok)
            assert(session:skip_raise().ok)
            while session:current_phase() == "tricks" do
                local p = session:current_turn()
                local card = session:legal_cards(p)[1]
                assert(session:play(p, card).ok)
            end
            scene:draw(1024, 720)
            assert.is_not_nil(
                find_text(mock, t("scene.table.deal_done.scored")),
                "deal-done banner should appear"
            )
            for seat = 1, 3 do
                assert.is_nil(
                    find_text(mock, t("scene.table.privacy.prompt", { n = seat })),
                    "no privacy prompt expected during deal_done for seat " .. seat
                )
            end
        end)

        it("playing the last focused card snaps focus to the new last card", function()
            -- Disable the privacy curtain so focus is observable
            -- straight after the mutation, without dismissing a modal.
            local settings = require("app.settings")
            local store = {}
            settings._set_storage(function(p)
                return store[p]
            end, function(p, v)
                store[p] = v
                return true
            end)
            settings.set("hot_seat_privacy", false)

            -- Drive to the tricks phase.
            assert(session:bid(2, 100).ok)
            assert(session:pass(3).ok)
            assert(session:pass(1).ok)
            assert(session:take_talon().ok)
            local hand = session:hands()[2]
            assert(session:pass_talon(1, hand[1]).ok)
            hand = session:hands()[2]
            assert(session:pass_talon(3, hand[1]).ok)
            assert(session:skip_raise().ok)
            assert.are.equal("tricks", session:current_phase())

            -- Drive two plays so the third player is about to close
            -- trick 1. The trick winner leads trick 2 with one fewer
            -- card than the closer had — that is the rotation gap
            -- where the bug was visible.
            local lead = session:current_turn()
            assert(session:play(lead, session:legal_cards(lead)[1]).ok)
            local follower = session:current_turn()
            assert(session:play(follower, session:legal_cards(follower)[1]).ok)

            local closer = session:current_turn()
            scene:draw(1024, 720)
            local closer_count = #session:hands()[closer]
            scene._focus_index = closer_count
            assert.are.equal("card", scene:_focus_target())

            scene:_do_play(closer, session:legal_cards(closer)[1])

            local new_turn = session:current_turn()
            assert.is_not_nil(new_turn, "trick 2 should have begun with a new leader")
            scene:draw(1024, 720)
            local new_count = scene:_focus_card_count()
            assert.is_not_nil(scene._focus_index, "focus should snap to a card, not drop")
            assert.is_true(
                scene._focus_index <= new_count,
                "focus_index "
                    .. tostring(scene._focus_index)
                    .. " > new card_count "
                    .. tostring(new_count)
                    .. " — focus leaked into the panel/back range"
            )
            assert.are.equal("card", scene:_focus_target())
        end)

        it("does not raise the curtain when settings.hot_seat_privacy is off", function()
            local settings = require("app.settings")
            -- Swap in an in-memory storage hook so the toggle write
            -- does not touch love.filesystem, then turn the curtain off.
            local store = {}
            settings._set_storage(function(p)
                return store[p]
            end, function(p, v)
                store[p] = v
                return true
            end)
            settings.set("hot_seat_privacy", false)

            -- Re-create the scene so its first draw runs through the
            -- gated trigger from a clean state.
            local table_scene = require("ui.scenes.table")
            local sc = table_scene.new(fake_manager(session))
            sc:enter(nil, nil)
            sc:draw(1024, 720)
            assert.is_nil(sc._curtain, "no curtain expected when privacy is disabled")
            assert.is_nil(
                find_text(mock, t("scene.table.privacy.prompt", { n = 2 })),
                "no privacy prompt expected when privacy is disabled"
            )
        end)

        it("clears an existing curtain if the setting flips off mid-game", function()
            scene:draw(1024, 720)
            assert.is_not_nil(scene._curtain, "expected curtain on first frame")

            local settings = require("app.settings")
            local store = {}
            settings._set_storage(function(p)
                return store[p]
            end, function(p, v)
                store[p] = v
                return true
            end)
            settings.set("hot_seat_privacy", false)

            mock.graphics.clear_recording()
            scene:draw(1024, 720)
            assert.is_nil(scene._curtain, "curtain should clear once the setting flips off")
        end)

        it("raises a curtain after Next deal kicks off the next deal", function()
            scene:draw(1024, 720)
            dismiss_curtain(scene)

            assert(session:bid(2, 100).ok)
            assert(session:pass(3).ok)
            assert(session:pass(1).ok)
            assert(session:take_talon().ok)
            local hand = session:hands()[2]
            assert(session:pass_talon(1, hand[1]).ok)
            hand = session:hands()[2]
            assert(session:pass_talon(3, hand[1]).ok)
            assert(session:skip_raise().ok)
            while session:current_phase() == "tricks" do
                local p = session:current_turn()
                local c = session:legal_cards(p)[1]
                assert(session:play(p, c).ok)
            end
            scene:draw(1024, 720)
            local next_btn
            for _, b in ipairs(scene._panel_buttons) do
                if b.id == "deal_done_next" then
                    next_btn = b
                    break
                end
            end
            assert.is_not_nil(next_btn, "expected the deal_done next-deal button")
            next_btn:activate()
            mock.graphics.clear_recording()
            scene:draw(1024, 720)
            -- Dealer rotated 1 → 2; new forehand is seat 3.
            assert.is_not_nil(
                find_text(mock, t("scene.table.privacy.prompt", { n = 3 })),
                "expected curtain for the new forehand after Next deal"
            )
        end)
    end)
end)
