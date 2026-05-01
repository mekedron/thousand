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
        assert.is_not_nil(find_text(mock, t("scene.table.player_label.you")), "your-hand label")
        assert.is_not_nil(
            find_text(mock, t("scene.table.player_label.other", { n = 2 })),
            "Player 2 label"
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
end)
