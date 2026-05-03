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
        if session:current_phase() == "awaiting_write_off_decision" then
            assert(session:accept_play().ok)
        end
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
            if s:current_phase() == "awaiting_write_off_decision" then
                assert(s:accept_play().ok)
            end
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
        if s:current_phase() == "awaiting_write_off_decision" then
            assert(s:accept_play().ok)
        end
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
            if session:current_phase() == "awaiting_write_off_decision" then
                assert(session:accept_play().ok)
            end
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
            if session:current_phase() == "awaiting_write_off_decision" then
                assert(session:accept_play().ok)
            end
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
            if session:current_phase() == "awaiting_write_off_decision" then
                assert(session:accept_play().ok)
            end
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
            if session:current_phase() == "awaiting_write_off_decision" then
                assert(session:accept_play().ok)
            end
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

    describe("bot driver wiring (Phase 4.1)", function()
        local function fake_clock()
            local now = 0
            return {
                read = function()
                    return now
                end,
                advance = function(dt)
                    now = now + dt
                end,
            }
        end

        it("stores seat_kinds from enter params and instantiates the driver", function()
            local table_scene = require("ui.scenes.table")
            local sc = table_scene.new(fake_manager(session))
            sc:enter(nil, { seat_kinds = { "human", "bot", "bot" } })
            assert.are.same({ "human", "bot", "bot" }, sc._seat_kinds)
            assert.is_not_nil(sc._bot_driver)
            assert.is_function(sc._bot_driver.tick)
        end)

        it("defaults seat_kinds to nil when no params are passed", function()
            local table_scene = require("ui.scenes.table")
            local sc = table_scene.new(fake_manager(session))
            sc:enter(nil, nil)
            assert.is_nil(sc._seat_kinds)
        end)

        it("does not open the privacy curtain on a bot turn", function()
            local table_scene = require("ui.scenes.table")
            local sc = table_scene.new(fake_manager(session))
            sc:enter(nil, { seat_kinds = { "human", "bot", "bot" } })
            sc:draw(1024, 720)
            -- Forehand is seat 2 (a bot under this binding) → no curtain.
            assert.is_nil(sc._curtain, "no curtain expected on a bot turn")
            assert.is_nil(
                find_text(mock, t("scene.table.privacy.prompt", { n = 2 })),
                "no privacy prompt expected for the bot seat"
            )
        end)

        it("applies a bot pass via the session mutator after the thinking delay", function()
            local clock = fake_clock()
            local bot_driver = require("app.bot.driver")
            bot_driver._clock_for_test = clock.read

            local table_scene = require("ui.scenes.table")
            local sc = table_scene.new(fake_manager(session))
            sc:enter(nil, { seat_kinds = { "human", "bot", "bot" } })

            -- Forehand is seat 2 (bot). Tick: pending decision; no apply.
            sc:update(0.0)
            assert.is_true(sc._bot_driver:is_thinking())
            assert.are.equal(2, sc._bot_driver:thinking_seat())
            assert.are.equal("auction", session:current_phase())
            assert.are.equal(2, session:current_turn())

            -- Advance past the default delay; tick triggers apply.
            clock.advance(1.0)
            sc:update(0.0)
            assert.is_false(sc._bot_driver:is_thinking())
            -- The bot stub passes; the next forehand candidate is seat 3.
            assert.are.equal(3, session:current_turn())

            bot_driver._clock_for_test = nil
        end)

        it("renders the thinking banner while a bot decision is pending", function()
            local clock = fake_clock()
            local bot_driver = require("app.bot.driver")
            bot_driver._clock_for_test = clock.read

            local table_scene = require("ui.scenes.table")
            local sc = table_scene.new(fake_manager(session))
            sc:enter(nil, { seat_kinds = { "human", "bot", "bot" } })
            sc:update(0.0)

            mock.graphics.clear_recording()
            sc:draw(1024, 720)
            assert.is_not_nil(
                find_text(mock, t("scene.table.bot_thinking", { n = 2 })),
                "expected the bot-thinking banner during the pending decision"
            )

            bot_driver._clock_for_test = nil
        end)

        it("is a no-op when seat_kinds is nil (existing human-only flow)", function()
            local table_scene = require("ui.scenes.table")
            local sc = table_scene.new(fake_manager(session))
            sc:enter(nil, nil)
            sc:update(0.5)
            -- Driver did not run (no seat_kinds), session unchanged.
            assert.are.equal("auction", session:current_phase())
            assert.are.equal(2, session:current_turn())
            assert.is_false(sc._bot_driver:is_thinking())
        end)
    end)

    describe("viewer lock (Phase 4.2)", function()
        local function fresh_scene(seat_kinds)
            local Session = require("app.session")
            local s = Session.new({ seed = 42, dealer = 1, seat_kinds = seat_kinds })
            local table_scene = require("ui.scenes.table")
            local sc = table_scene.new(fake_manager(s))
            sc:enter(nil, { seat_kinds = seat_kinds })
            return sc, s
        end

        it("locks _viewer_seat to the lone human in single-player", function()
            local sc = fresh_scene({ "human", "bot", "bot" })
            -- Forehand is seat 2 (a bot under this binding); viewer
            -- must still resolve to seat 1.
            assert.are.equal(1, sc._viewer_seat)
        end)

        it("renders the human's hand as 'self' even when a bot is on turn", function()
            local sc = fresh_scene({ "human", "bot", "bot" })
            assert.are.equal("self", sc._view_model.hands[1].perspective)
            assert.are.equal("other", sc._view_model.hands[2].perspective)
            assert.are.equal("other", sc._view_model.hands[3].perspective)
        end)

        it("clears _viewer_seat when seat_kinds is nil (legacy hot-seat)", function()
            local sc = fresh_scene(nil)
            assert.is_nil(sc._viewer_seat)
            -- Legacy: turn-seat (forehand 2) renders as self.
            assert.are.equal("self", sc._view_model.hands[2].perspective)
        end)

        it("returns nil viewer for an all-bot composition", function()
            local sc = fresh_scene({ "bot", "bot", "bot" })
            assert.is_nil(sc._viewer_seat)
        end)

        it("snaps the viewer to the human-on-turn in a multi-human composition", function()
            local Session = require("app.session")
            local s =
                Session.new({ seed = 42, dealer = 1, seat_kinds = { "human", "human", "bot" } })
            local table_scene = require("ui.scenes.table")
            local sc = table_scene.new(fake_manager(s))
            sc:enter(nil, { seat_kinds = { "human", "human", "bot" } })
            -- Forehand 2 is human → viewer follows.
            assert.are.equal(2, sc._viewer_seat)
            -- Pass to seat 3 (bot). Viewer stays at 2 across the bot turn.
            assert.is_true(s:pass(2).ok)
            sc:_refresh_view_model()
            assert.are.equal(3, s:current_turn())
            assert.are.equal(2, sc._viewer_seat)
        end)

        it("hides the action panel while a bot is on turn", function()
            local sc = fresh_scene({ "human", "bot", "bot" })
            -- Bot on turn (forehand 2) → no buttons.
            assert.are.equal(0, #sc._panel_buttons)
        end)

        it("shows the action panel when control returns to the human", function()
            local Session = require("app.session")
            local s = Session.new({ seed = 42, dealer = 1, seat_kinds = { "human", "bot", "bot" } })
            local table_scene = require("ui.scenes.table")
            local sc = table_scene.new(fake_manager(s))
            sc:enter(nil, { seat_kinds = { "human", "bot", "bot" } })
            -- Drive both bot seats past their auction turn so seat 1
            -- becomes the next forehand candidate.
            assert.is_true(s:pass(2).ok)
            assert.is_true(s:pass(3).ok)
            sc:_refresh_view_model()
            sc:draw(1024, 720)
            assert.are.equal(1, s:current_turn())
            assert.is_true(
                #sc._panel_buttons > 0,
                "expected auction panel to rebuild for the human"
            )
        end)

        it("blocks hand interactivity while a bot is on turn", function()
            local sc = fresh_scene({ "human", "bot", "bot" })
            -- Forehand 2 is a bot under this binding.
            assert.is_false(sc:_hand_is_interactive())
        end)

        it("does not render the bot's hand face-up at the bottom in single-player", function()
            local sc = fresh_scene({ "human", "bot", "bot" })
            mock.graphics.clear_recording()
            sc:draw(1024, 720)
            -- The "you" label belongs to the human (seat 1); seat 2's
            -- per-N label appears at the top because it's an opponent
            -- now even though it's on turn.
            assert.is_not_nil(
                find_text(mock, t("scene.table.player_label.you")),
                "expected the human (seat 1) to render as 'you'"
            )
            assert.is_not_nil(
                find_text(mock, t("scene.table.player_label.other", { n = 2 })),
                "expected the bot at seat 2 to render as Player 2"
            )
        end)
    end)
end)

-- ---------------------------------------------------------------------------
-- Bidding house-rules UI tests (Phase 3.6)
-- ---------------------------------------------------------------------------
-- These tests are intentionally RED until the implementation lands.
-- They match the API contract in sidebar-position-4-title-modular-narwhal.md
-- exactly: view.auction.* keys, button IDs, and i18n keys are verbatim.
-- ---------------------------------------------------------------------------

local Session = require("app.session")
local rule_config = require("core.rule_config")
local auction_module = require("core.auction")
local marriages_module = require("core.marriages")
local card_module = require("core.card")

-- ---------------------------------------------------------------------------
-- Helper: build a RuleConfig with the Russian-style baseline plus arbitrary
-- bidding overrides, optionally also merging talon / specials overrides.
-- ---------------------------------------------------------------------------
local function canonical_with_bidding(bidding_overrides, extra_overrides)
    bidding_overrides = bidding_overrides or {}
    extra_overrides = extra_overrides or {}

    local bidding = {
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
    }
    for k, v in pairs(bidding_overrides) do
        bidding[k] = v
    end

    local blob = {
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
            two_nines_in_talon_redeal = "off",
            misdeal_handling = "standard",
            misdeal_flat_penalty = 20,
            all_pass_handling = "redeal",
            deck_size = "24",
            cut_deck_safety = "on",
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
        bidding = bidding,
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
            declarer_rounding_before_contract_check = "off",
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
            mizere = extra_overrides.mizere or "off",
            mizere_contract_value = extra_overrides.mizere_contract_value or 120,
            slam_contract = extra_overrides.slam_contract or "off",
            slam_contract_value = extra_overrides.slam_contract_value or 240,
            open_hand = extra_overrides.open_hand or "off",
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
    }
    return rule_config.new(blob)
end

-- ---------------------------------------------------------------------------
-- Helper: build a session wired from internal state (mirrors
-- session_talon_variants_spec pattern). Dealer = 1 → forehand = seat 2.
-- ---------------------------------------------------------------------------
local function c(suit, rank)
    return card_module.new(suit, rank)
end

-- A balanced hand set with no marriages in any hand and a neutral talon.
-- Used for tests that must not trigger marriage-related rules.
local function plain_hands()
    local seat1 = {
        c("spades", "9"),
        c("clubs", "9"),
        c("diamonds", "9"),
        c("hearts", "J"),
        c("spades", "J"),
        c("clubs", "J"),
        c("diamonds", "J"),
    }
    local seat2 = {
        c("hearts", "9"),
        c("spades", "10"),
        c("clubs", "10"),
        c("diamonds", "10"),
        c("hearts", "10"),
        c("spades", "A"),
        c("clubs", "A"),
    }
    local seat3 = {
        c("diamonds", "A"),
        c("hearts", "A"),
        c("spades", "K"),
        c("clubs", "K"),
        c("diamonds", "K"),
        c("hearts", "K"),
        c("spades", "Q"),
    }
    local talon = {
        c("clubs", "Q"),
        c("diamonds", "Q"),
        c("hearts", "Q"),
    }
    return { seat1, seat2, seat3 }, talon
end

-- A hand set where seat 2 (forehand / typical declarer) holds a spades
-- marriage (K+Q of spades) and no other marriages.
-- luacheck: ignore hands_with_marriage_seat2
local function hands_with_marriage_seat2()
    local seat1 = {
        c("spades", "9"),
        c("clubs", "9"),
        c("diamonds", "9"),
        c("hearts", "J"),
        c("spades", "J"),
        c("clubs", "J"),
        c("diamonds", "J"),
    }
    local seat2 = {
        c("spades", "K"),
        c("spades", "Q"),
        c("hearts", "9"),
        c("spades", "10"),
        c("clubs", "10"),
        c("diamonds", "10"),
        c("hearts", "10"),
    }
    local seat3 = {
        c("diamonds", "A"),
        c("hearts", "A"),
        c("spades", "A"),
        c("clubs", "A"),
        c("clubs", "K"),
        c("diamonds", "K"),
        c("hearts", "K"),
    }
    local talon = {
        c("clubs", "Q"),
        c("diamonds", "Q"),
        c("hearts", "Q"),
    }
    return { seat1, seat2, seat3 }, talon
end

-- A hand set where NO seat holds any marriage (every K is separated from
-- its Q by being in a different hand or the talon).
local function hands_without_marriage()
    local seat1 = {
        c("spades", "9"),
        c("clubs", "9"),
        c("diamonds", "9"),
        c("hearts", "9"),
        c("spades", "J"),
        c("clubs", "J"),
        c("diamonds", "J"),
    }
    local seat2 = {
        c("hearts", "J"),
        c("spades", "10"),
        c("clubs", "10"),
        c("diamonds", "10"),
        c("hearts", "10"),
        c("spades", "A"),
        c("clubs", "A"),
    }
    local seat3 = {
        c("diamonds", "A"),
        c("hearts", "A"),
        c("spades", "K"),
        c("clubs", "K"),
        c("diamonds", "K"),
        c("hearts", "K"),
        c("spades", "Q"),
    }
    -- All queens in talon so no hand has a complete K+Q pair.
    local talon = {
        c("clubs", "Q"),
        c("diamonds", "Q"),
        c("hearts", "Q"),
    }
    return { seat1, seat2, seat3 }, talon
end

-- Build a Session from explicit hands/talon/config via from_state.
local function session_at_auction(cfg, hands, talon, opts)
    opts = opts or {}
    local dealer = opts.dealer or 1
    local running_totals = opts.running_totals or { 0, 0, 0 }
    -- Mirror the session's marriage-holdings + running-totals threading
    -- so auction.holdings and auction.locked are populated for tests.
    local holdings = {}
    for seat = 1, #hands do
        local suits = marriages_module.detect(hands[seat])
        local total = 0
        for _, suit in ipairs(suits) do
            total = total + (cfg.marriages.values[suit] or 0)
        end
        holdings[seat] = { marriage_total = total }
    end
    local auction = auction_module.new(cfg, dealer, {
        holdings = holdings,
        running_totals = running_totals,
    }).auction
    local marriages = marriages_module.new(cfg).marriages
    return Session.from_state({
        config = cfg,
        seed = opts.seed or 1,
        dealer = dealer,
        hands = hands,
        talon_cards = talon,
        auction = auction,
        marriages = marriages,
        running_totals = running_totals,
        deal_index = opts.deal_index or 1,
    })
end

-- Dismiss the privacy curtain on a scene so subsequent interactions work.
local function dismiss_curtain(sc)
    sc._curtain = nil
    if sc._view_model and sc._view_model.turn_player then
        sc._last_revealed_seat = sc._view_model.turn_player
    end
end

-- Find a button by id in scene._panel_buttons; returns nil if absent.
local function find_button(sc, id)
    for _, b in ipairs(sc._panel_buttons or {}) do
        if b.id == id then
            return b
        end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- The main describe block required by the plan.
-- ---------------------------------------------------------------------------
describe("bidding house rules", function()
    -- luacheck: ignore scene_bhr
    local mock_bhr, scene_bhr, t_bhr

    before_each(function()
        reset_modules()
        mock_bhr = love_mock.new({ width = 1024, height = 720 })
        mock_bhr:install()
        local i18n = require("app.i18n")
        i18n._reset()
        i18n._set_logger(function() end)
        i18n.set_locale("en")
        t_bhr = i18n.t
    end)

    after_each(function()
        if mock_bhr then
            mock_bhr:restore()
        end
        reset_modules()
    end)

    -- -----------------------------------------------------------------------
    -- 1. forced_opening: forehand cannot pass on first bid round
    -- -----------------------------------------------------------------------
    it("hides pass button when forced_opening is on at first action", function()
        local cfg = canonical_with_bidding({ forced_opening = "on" })
        local hands, talon = plain_hands()
        -- Dealer = 1, forehand = seat 2. No bids yet — seat 2's first action.
        local s = session_at_auction(cfg, hands, talon)

        local table_scene = require("ui.scenes.table")
        local sc = table_scene.new(fake_manager(s))
        sc:enter(nil, nil)
        dismiss_curtain(sc)
        sc:draw(1024, 720)

        -- The pass button must be absent (forehand_pass_disabled = true).
        local pass_btn = find_button(sc, "auction_pass")
        assert.is_nil(
            pass_btn,
            "pass button must be absent when forced_opening is on at forehand's first action"
        )

        -- Bid amount buttons must still appear.
        local bid_btn = find_button(sc, "bid_100")
        assert.is_not_nil(bid_btn, "bid_100 button must appear even when pass is blocked")

        -- View-model should carry the disabled reason.
        local view = sc._view_model
        assert.is_not_nil(view, "view_model must be populated after draw")
        assert.is_true(
            view.auction and view.auction.forehand_pass_disabled,
            "view.auction.forehand_pass_disabled must be true"
        )
        assert.are.equal(
            "forced_opening",
            view.auction and view.auction.pass_disabled_reason,
            "pass_disabled_reason must be 'forced_opening'"
        )
    end)

    -- -----------------------------------------------------------------------
    -- 2. forced_dealer_bid: dealer-forced banner after all seats pass
    -- -----------------------------------------------------------------------
    it("renders dealer-forced banner under forced_dealer_bid after all-pass", function()
        -- The auction terminates after pass_count >= player_count - 1
        -- so two passes (forehand + middlehand) are sufficient — the
        -- dealer (seat 1) is the "remaining" seat and gets forced
        -- into the minimum-100 contract.
        local cfg = canonical_with_bidding({ forced_dealer_bid = "on" })
        local hands, talon = plain_hands()
        local s = session_at_auction(cfg, hands, talon)
        assert(s:pass(2).ok, "seat 2 pass must succeed")
        assert(s:pass(3).ok, "seat 3 pass must succeed")
        -- Session should NOT have redealed; dealer should be forced to 100.
        -- Phase should not be "auction" anymore.
        assert.are_not.equal(
            "auction",
            s:current_phase(),
            "auction must be over after all-pass with forced_dealer_bid"
        )

        local table_scene = require("ui.scenes.table")
        local sc = table_scene.new(fake_manager(s))
        sc:enter(nil, nil)
        dismiss_curtain(sc)
        sc:draw(1024, 720)

        -- The view-model must expose a dealer_forced_banner.
        local view = sc._view_model
        assert.is_not_nil(view, "view_model must be populated")
        local banner = view.auction and view.auction.dealer_forced_banner
        assert.is_not_nil(
            banner,
            "view.auction.dealer_forced_banner must be set after forced all-pass"
        )
        assert.are.equal(1, banner.dealer_seat, "banner.dealer_seat must be the dealer (1)")
        assert.are.equal(100, banner.amount, "banner.amount must equal the opening_min (100)")

        -- The scene must render the i18n-formatted banner text.
        assert.is_not_nil(
            find_text(
                mock_bhr,
                t_bhr("scene.table.auction.dealer_forced_banner", { seat = 1, amount = 100 })
            ),
            "dealer_forced_banner i18n text must be rendered"
        )
    end)

    -- -----------------------------------------------------------------------
    -- 3. blind_bid: "Bid blind" button rendered before curtain reveal
    -- -----------------------------------------------------------------------
    it("renders blind-bid button under blind_bid before reveal", function()
        local cfg = canonical_with_bidding({ blind_bid = "first_bid_double" })
        local hands, talon = plain_hands()
        -- Dealer = 1, forehand = seat 2. No bids yet — blind offer active.
        local s = session_at_auction(cfg, hands, talon)

        local table_scene = require("ui.scenes.table")
        local sc = table_scene.new(fake_manager(s))
        sc:enter(nil, nil)
        -- Do NOT dismiss curtain: blind_bid is only offered while the curtain
        -- is still up (the plan: "Shown only while the seat's curtain is still up
        -- and they have no prior action"). The view-model check is sufficient.
        sc:draw(1024, 720)

        -- View-model must expose a blind_bid_offer for the on-turn seat.
        local view = sc._view_model
        assert.is_not_nil(view, "view_model must be populated")
        local offer = view.auction and view.auction.blind_bid_offer
        assert.is_not_nil(
            offer,
            "view.auction.blind_bid_offer must be set when toggle is active and curtain up"
        )
        assert.are.equal(2, offer.seat, "offer.seat must be the forehand (2)")
        assert.are.equal(
            2,
            offer.multiplier_preview,
            "offer.multiplier_preview must be 2 (first_bid_double)"
        )

        -- The scene must render the blind-bid button.
        local btn = find_button(sc, "auction_bid_blind")
        assert.is_not_nil(
            btn,
            "auction_bid_blind button must be present when blind_bid_offer is active"
        )
        assert.is_not_nil(
            find_text(mock_bhr, t_bhr("scene.table.auction.bid_blind_button", { multiplier = 2 })),
            "bid_blind_button i18n text must be rendered"
        )
    end)

    -- -----------------------------------------------------------------------
    -- 4. re_entry_after_pass: passed seat sees a "Re-enter" button
    -- -----------------------------------------------------------------------
    it("renders re-enter button for passed seat under re_entry_after_pass", function()
        local cfg = canonical_with_bidding({ re_entry_after_pass = "on" })
        local hands, talon = plain_hands()
        -- Dealer = 1, forehand = seat 2. Sequence: forehand passes
        -- first, seat 3 opens at 100. Auction stays in_progress (only
        -- one pass) so the view-model still surfaces the auction
        -- block with seat 2 listed as eligible to re-enter.
        local s = session_at_auction(cfg, hands, talon)
        assert(s:pass(2).ok, "seat 2 passes — now eligible for re-entry")
        assert(s:bid(3, 100).ok, "seat 3 opens the auction")
        -- Now seat 1 is on turn; re-entry button for seat 2 would only appear
        -- from seat 2's perspective. We check the view-model key is populated.
        -- The scene always renders seat 2 as "self" (dealer=1 → forehand=2).

        local table_scene = require("ui.scenes.table")
        local sc = table_scene.new(fake_manager(s))
        sc:enter(nil, nil)
        dismiss_curtain(sc)
        sc:draw(1024, 720)

        local view = sc._view_model
        assert.is_not_nil(view, "view_model must be populated")
        local re_entry_seats = view.auction and view.auction.passed_seats_with_re_entry
        assert.is_not_nil(re_entry_seats, "view.auction.passed_seats_with_re_entry must be set")

        -- Seat 2 must appear in the list (it passed and has not yet re-entered).
        local seat2_eligible = false
        for _, seat in ipairs(re_entry_seats) do
            if seat == 2 then
                seat2_eligible = true
            end
        end
        assert.is_true(seat2_eligible, "seat 2 must appear in passed_seats_with_re_entry")

        -- Re-enter button must be rendered for the self seat.
        local btn = find_button(sc, "auction_re_enter")
        assert.is_not_nil(btn, "auction_re_enter button must be present for the passed self seat")
        assert.is_not_nil(
            find_text(mock_bhr, t_bhr("scene.table.auction.re_enter_button")),
            "re_enter_button i18n text must be rendered"
        )
    end)

    -- -----------------------------------------------------------------------
    -- 5. contra=contra_only: defenders see "Contra" button after talon reveal
    -- -----------------------------------------------------------------------
    it("renders contra button at talon-revealed under contra=contra_only", function()
        local cfg = canonical_with_bidding({ contra = "contra_only" })
        local hands, talon = plain_hands()
        local s = session_at_auction(cfg, hands, talon)
        -- Seat 2 wins the auction; session enters the talon phase.
        assert(s:bid(2, 100).ok)
        assert(s:pass(3).ok)
        assert(s:pass(1).ok)
        -- Session must now be in the talon phase or a doubling phase.
        assert.are_not.equal("auction", s:current_phase(), "should be past auction")

        local table_scene = require("ui.scenes.table")
        local sc = table_scene.new(fake_manager(s))
        sc:enter(nil, nil)
        dismiss_curtain(sc)
        sc:draw(1024, 720)

        -- View-model (talon_phase or auction) must expose a contra_offer.
        local view = sc._view_model
        assert.is_not_nil(view, "view_model must be populated")
        local contra = view.talon_phase and view.talon_phase.contra_offer
        assert.is_not_nil(
            contra,
            "view.talon_phase.contra_offer must be set when contra=contra_only and auction done"
        )
        assert.are.equal("contra", contra.kind, "contra_offer.kind must be 'contra'")

        -- The scene must render the contra button in the talon take panel.
        local btn = find_button(sc, "talon_contra")
        assert.is_not_nil(btn, "talon_contra button must be present in the talon panel")
        assert.is_not_nil(
            find_text(mock_bhr, t_bhr("scene.table.auction.contra_button")),
            "contra_button i18n text must be rendered"
        )
    end)

    -- -----------------------------------------------------------------------
    -- 6. contra=contra_and_redouble: both Contra and Redouble buttons present
    -- -----------------------------------------------------------------------
    it("renders contra and redouble buttons under contra_and_redouble", function()
        local cfg = canonical_with_bidding({ contra = "contra_and_redouble" })
        local hands, talon = plain_hands()
        local s = session_at_auction(cfg, hands, talon)
        assert(s:bid(2, 100).ok)
        assert(s:pass(3).ok)
        assert(s:pass(1).ok)
        assert.are_not.equal("auction", s:current_phase(), "should be past auction")

        -- Simulate a defender declaring contra so the redouble window opens.
        -- If the mutator is not yet implemented this will be the RED signal.
        local contra_res = s:declare_contra(3)
        assert.is_true(
            contra_res and contra_res.ok,
            "declare_contra(3) must succeed when contra=contra_and_redouble"
        )

        local table_scene = require("ui.scenes.table")
        local sc = table_scene.new(fake_manager(s))
        sc:enter(nil, nil)
        dismiss_curtain(sc)
        sc:draw(1024, 720)

        local view = sc._view_model
        assert.is_not_nil(view, "view_model must be populated")
        local contra_offer = view.talon_phase and view.talon_phase.contra_offer
        assert.is_not_nil(contra_offer, "contra_offer must be set after contra declared")
        assert.are.equal(
            "redouble",
            contra_offer.kind,
            "contra_offer.kind must be 'redouble' once contra is declared"
        )

        -- After contra is declared, the contra button is replaced by
        -- the redouble button — they share the talon-take panel slot
        -- and the offer.kind switches to drive the rendering.
        local btn_redouble = find_button(sc, "talon_redouble")
        assert.is_not_nil(
            btn_redouble,
            "talon_redouble button must be present when redouble window open"
        )
        assert.is_not_nil(
            find_text(mock_bhr, t_bhr("scene.table.auction.redouble_button")),
            "redouble_button i18n text must be rendered"
        )
    end)

    -- -----------------------------------------------------------------------
    -- 7. forced_bid_concession: "Concede" button with split label
    -- -----------------------------------------------------------------------
    it("renders concede button under forced_bid_concession with split label", function()
        -- forced_bid_concession fires when dealer is forced into 100 by
        -- forced_dealer_bid. Use equal_split mode as the simplest case.
        local cfg = canonical_with_bidding({
            forced_dealer_bid = "on",
            forced_bid_concession = "equal_split",
        })
        local hands, talon = plain_hands()
        local s = session_at_auction(cfg, hands, talon)
        -- The auction terminates after pass_count >= player_count - 1,
        -- so two passes (forehand + middlehand) are sufficient to leave
        -- the dealer as the forced declarer.
        assert(s:pass(2).ok)
        assert(s:pass(3).ok)
        -- Session should now be in awaiting_forced_concession_decision phase.
        assert.are.equal(
            "awaiting_forced_concession_decision",
            s:current_phase(),
            "session must be in forced-concession phase after all-pass with forced_bid_concession on"
        )

        local table_scene = require("ui.scenes.table")
        local sc = table_scene.new(fake_manager(s))
        sc:enter(nil, nil)
        dismiss_curtain(sc)
        sc:draw(1024, 720)

        local view = sc._view_model
        assert.is_not_nil(view, "view_model must be populated")
        local concede = view.talon_phase and view.talon_phase.concede_offer
        assert.is_not_nil(
            concede,
            "view.talon_phase.concede_offer must be set in forced-concession phase"
        )
        assert.are.equal(
            "equal_split",
            concede.split_preview,
            "split_preview must be 'equal_split'"
        )

        local btn = find_button(sc, "talon_concede_forced")
        assert.is_not_nil(btn, "talon_concede_forced button must be present in the panel")
        assert.is_not_nil(
            find_text(
                mock_bhr,
                t_bhr("scene.table.auction.concede_button", { split = "equal_split" })
            ),
            "concede_button i18n text with split label must be rendered"
        )
    end)

    -- -----------------------------------------------------------------------
    -- 8. no_contract_without_marriage: bids >= 120 disabled when no marriage
    -- -----------------------------------------------------------------------
    it(
        "disables bid amounts >=120 under no_contract_without_marriage with empty marriage hand",
        function()
            local cfg = canonical_with_bidding({
                no_contract_without_marriage = "no_120_without_marriage",
                pre_talon_max = 120,
            })
            -- Use a hand set where seat 2 (forehand) has NO marriage.
            local hands, talon = hands_without_marriage()
            local s = session_at_auction(cfg, hands, talon)
            -- Seat 2 must have no marriages so the rule fires. Verify with the
            -- view-model (the engine passes holdings so the auction knows).

            local table_scene = require("ui.scenes.table")
            local sc = table_scene.new(fake_manager(s))
            sc:enter(nil, nil)
            dismiss_curtain(sc)
            sc:draw(1024, 720)

            local view = sc._view_model
            assert.is_not_nil(view, "view_model must be populated")
            local disabled = view.auction and view.auction.disabled_bid_amounts
            assert.is_not_nil(
                disabled,
                "view.auction.disabled_bid_amounts must be set when no_contract_without_marriage is on and seat has no marriage"
            )
            assert.is_true(disabled[120] == true, "bid amount 120 must be in disabled_bid_amounts")

            -- The bid_120 button must exist but be disabled.
            local bid120 = find_button(sc, "bid_120")
            assert.is_not_nil(bid120, "bid_120 button must still appear in the panel (greyed out)")
            assert.is_false(bid120.enabled, "bid_120 button must be disabled (no marriage in hand)")

            -- Informational text must explain why.
            assert.is_not_nil(
                find_text(mock_bhr, t_bhr("scene.table.auction.bid_disabled_no_marriage")),
                "bid_disabled_no_marriage i18n text must be rendered"
            )
        end
    )

    -- -----------------------------------------------------------------------
    -- 9. negative_score_restriction: bid panel locked to 100 for negative seat
    -- -----------------------------------------------------------------------
    it(
        "locks bid panel to 100 button only under negative_score_restriction with negative total",
        function()
            local cfg = canonical_with_bidding({ negative_score_restriction = "on" })
            local hands, talon = plain_hands()
            -- Seat 2 (forehand) has a negative running total → bid panel locked.
            local s = session_at_auction(cfg, hands, talon, {
                running_totals = { 0, -50, 0 },
            })

            local table_scene = require("ui.scenes.table")
            local sc = table_scene.new(fake_manager(s))
            sc:enter(nil, nil)
            dismiss_curtain(sc)
            sc:draw(1024, 720)

            local view = sc._view_model
            assert.is_not_nil(view, "view_model must be populated")
            assert.are.equal(
                100,
                view.auction and view.auction.locked_bid_amount,
                "view.auction.locked_bid_amount must be 100 for a negative-score forehand"
            )

            -- Only the 100 button must exist in the panel.
            local bid100 = find_button(sc, "bid_100")
            assert.is_not_nil(bid100, "bid_100 must appear as the sole bid button")
            assert.is_true(bid100.enabled, "bid_100 must be enabled (the locked choice)")

            local bid105 = find_button(sc, "bid_105")
            assert.is_nil(bid105, "bid_105 must be absent when locked to 100")

            -- The locked-reason label must appear.
            assert.is_not_nil(
                find_text(
                    mock_bhr,
                    t_bhr("scene.table.auction.locked_to_minimum", { amount = 100 })
                ),
                "locked_to_minimum i18n text must be rendered"
            )
        end
    )

    -- -----------------------------------------------------------------------
    -- 10. named_contracts: mizère button appears when specials.mizere is on
    -- -----------------------------------------------------------------------
    it("renders mizère button under named_contracts=on with specials.mizere=on", function()
        local cfg = canonical_with_bidding({ named_contracts = "on" }, { mizere = "on" })
        local hands, talon = plain_hands()
        local s = session_at_auction(cfg, hands, talon)

        local table_scene = require("ui.scenes.table")
        local sc = table_scene.new(fake_manager(s))
        sc:enter(nil, nil)
        dismiss_curtain(sc)
        sc:draw(1024, 720)

        local view = sc._view_model
        assert.is_not_nil(view, "view_model must be populated")
        local named_buttons = view.auction and view.auction.named_contract_buttons
        assert.is_not_nil(
            named_buttons,
            "view.auction.named_contract_buttons must be set when named_contracts=on"
        )

        local found_mizere = false
        for _, entry in ipairs(named_buttons) do
            if entry.id == "named_mizere" and entry.kind == "mizere" then
                found_mizere = true
                assert.is_not_nil(
                    entry.contract_value,
                    "named_mizere entry must have a contract_value"
                )
            end
        end
        assert.is_true(found_mizere, "named_contract_buttons must include a mizere entry")

        local btn = find_button(sc, "auction_named_mizere")
        assert.is_not_nil(btn, "auction_named_mizere button must be present in the panel")
        local mizere_value = (named_buttons[1] or {}).contract_value or 0
        assert.is_not_nil(
            find_text(
                mock_bhr,
                t_bhr("scene.table.auction.named_mizere_button", { value = mizere_value })
            ),
            "named_mizere_button i18n text must be rendered"
        )
    end)

    -- -----------------------------------------------------------------------
    -- 11. Multiplier badge rendered after blind / contra / redouble
    -- -----------------------------------------------------------------------
    it("renders multiplier badge after blind / contra / redouble", function()
        -- Use blind_bid=first_bid_double so the multiplier is > 1 immediately
        -- after the blind bid is declared.
        local cfg = canonical_with_bidding({ blind_bid = "first_bid_double" })
        local hands, talon = plain_hands()
        local s = session_at_auction(cfg, hands, talon)

        -- Declare blind for seat 2 (the mutator is expected to exist after impl).
        local res = s:declare_blind(2)
        assert.is_true(
            res and res.ok,
            "declare_blind(2) must succeed when blind_bid=first_bid_double and no prior action"
        )

        local table_scene = require("ui.scenes.table")
        local sc = table_scene.new(fake_manager(s))
        sc:enter(nil, nil)
        dismiss_curtain(sc)
        sc:draw(1024, 720)

        -- contract_multiplier() must return 2 (blind ×2, no contra yet).
        local multiplier = s:contract_multiplier()
        assert.are.equal(
            2,
            multiplier,
            "Session:contract_multiplier() must return 2 after blind bid"
        )

        -- The multiplier badge must be visible in the scene.
        assert.is_not_nil(
            find_text(mock_bhr, t_bhr("scene.table.auction.contract_multiplier_badge", { n = 2 })),
            "contract_multiplier_badge ×2 must be rendered after blind bid"
        )
    end)
end)

-- ---------------------------------------------------------------------------
-- Phase 3.8 cut-deck ritual UI surface.
-- ---------------------------------------------------------------------------
describe("cut-deck ritual (Phase 3.8)", function()
    local mock_cut, t_cut

    before_each(function()
        reset_modules()
        mock_cut = love_mock.new({ width = 1024, height = 720 })
        mock_cut:install()
        local i18n = require("app.i18n")
        i18n._reset()
        i18n._set_logger(function() end)
        i18n.set_locale("en")
        t_cut = i18n.t
    end)

    after_each(function()
        if mock_cut then
            mock_cut:restore()
        end
        reset_modules()
    end)

    -- Build a config off canonical_russian and patch the dealing
    -- toggles for the procedural cut ritual. canonical_with_bidding
    -- doesn't expose dealing overrides, so go through the JSON
    -- round-trip path.
    local function cut_config()
        local rc = require("core.rule_config")
        local jsmod = require("app.json")
        local blob = jsmod.decode(rc.to_json(rc.canonical_russian))
        blob.dealing.cut_deck_safety = "off"
        blob.dealing.cut_deck_nine_jack_penalty = "on"
        blob.dealing.four_nine_redeal = "off"
        blob.dealing.three_nine_redeal = "off"
        blob.dealing.four_jack_redeal = "off"
        return rc.new(blob)
    end

    it("renders the Cut the deck button while the cut phase is open", function()
        local s = Session.new({ config = cut_config(), seed = 1, dealer = 1 })
        assert.are.equal("cut", s:current_phase())

        local table_scene = require("ui.scenes.table")
        local sc = table_scene.new(fake_manager(s))
        sc:enter(nil, nil)
        dismiss_curtain(sc)
        sc:draw(1024, 720)

        local btn = find_button(sc, "cut_deck")
        assert.is_not_nil(btn, "Cut the deck button must appear in the cut phase")
        assert.is_true(btn.enabled)
        assert.is_not_nil(
            find_text(mock_cut, t_cut("scene.table.cut.cut_deck_button")),
            "the localised 'Cut the deck' label must render"
        )
    end)

    it("invokes Session:cut_deck() on press", function()
        local s = Session.new({ config = cut_config(), seed = 1, dealer = 1 })

        local table_scene = require("ui.scenes.table")
        local sc = table_scene.new(fake_manager(s))
        sc:enter(nil, nil)
        dismiss_curtain(sc)
        sc:draw(1024, 720)

        local btn = find_button(sc, "cut_deck")
        assert.is_not_nil(btn)
        btn.on_press()
        -- After the button fires the session should no longer be in
        -- the cut phase (seed=1 is canonical_russian's good-bottom
        -- seed so the cut clears immediately).
        assert.are_not.equal("cut", s:current_phase())
    end)

    it("renders the bad-cut indicator counter while the cut phase is open", function()
        local card = require("core.card")
        local s = Session.from_state({
            config = cut_config(),
            seed = 1,
            dealer = 1,
            running_totals = { 0, 0, 0 },
            cut_phase = {
                active_cutter = 2,
                bad_cut_count = 1,
                bottom_card = card.new("hearts", "J"),
            },
            cut_deck_log = {
                {
                    kind = "bad_cut",
                    seat = 3,
                    dealer = 1,
                    bad_cut_count = 1,
                    next_cutter = 2,
                },
            },
        })

        local table_scene = require("ui.scenes.table")
        local sc = table_scene.new(fake_manager(s))
        sc:enter(nil, nil)
        dismiss_curtain(sc)
        sc:draw(1024, 720)

        assert.is_not_nil(
            find_text(
                mock_cut,
                t_cut("scene.table.cut.bad_cut_indicator", { count = 1, threshold = 3 })
            ),
            "the bad-cut counter must render while the cut phase is open"
        )
    end)
end)
