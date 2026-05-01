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
end)
