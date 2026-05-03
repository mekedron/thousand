-- Phase 4.2 e2e journey: the Single Player main-menu entry. Drives
-- main → menu → Single Player and asserts the table opens directly
-- with seat 1 = human and the rest = bots, no intermediate picker.

local journey = require("tests.e2e.support.journey")
local bot_driver = require("app.bot.driver")

local function smallest_rect_under_text(j, text)
    local best
    for _, op in ipairs(j:draws()) do
        if op.op == "rectangle" and op.mode == "fill" then
            for _, txt in ipairs(j:draws()) do
                if txt.op == "text" and txt.text == text then
                    if
                        txt.x >= op.x
                        and txt.x <= op.x + op.w
                        and txt.y >= op.y
                        and txt.y <= op.y + op.h
                    then
                        if not best or (op.w * op.h) < (best.w * best.h) then
                            best = op
                        end
                    end
                end
            end
        end
    end
    return best
end

describe("e2e: Single Player main-menu entry", function()
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

    it("renders the Single Player button at the top of the menu", function()
        assert.is_not_nil(j:find_text(j:find_localised("scene.menu.single_player")))
        local sp_rect = smallest_rect_under_text(j, j:find_localised("scene.menu.single_player"))
        local ng_rect = smallest_rect_under_text(j, j:find_localised("scene.menu.new_game"))
        assert.is_not_nil(sp_rect, "Single Player button rect must exist")
        assert.is_not_nil(ng_rect, "New Game button rect must exist")
        assert.is_true(
            sp_rect.y < ng_rect.y,
            "Single Player should sit above New Game on the menu column"
        )
    end)

    it("clicking Single Player lands directly on the table — no picker between", function()
        j:start_single_player_game()
        -- The picker scene's title must NOT have rendered.
        assert.is_nil(
            j:find_text(j:find_localised("scene.new_game.title")),
            "Single Player must skip the per-seat picker"
        )
        assert.is_not_nil(
            j:find_text(j:find_localised("scene.table.scoreboard.title")),
            "table scoreboard must be visible after Single Player"
        )
    end)

    it("opens the table with seat 1 as the human (curtain raised on seat 1)", function()
        -- The bot driver gates each decision on its monotonic clock.
        -- The love-mock's love.timer.getTime is frozen at 0, so we drive
        -- the clock forward manually via the test seam to let bot
        -- decisions expire their delays.
        local clock = { now = 0 }
        bot_driver._clock_for_test = function()
            return clock.now
        end
        finally(function()
            bot_driver._clock_for_test = nil
        end)

        j:start_single_player_game()
        -- The forehand under canonical Russian 3-player is seat 2; with
        -- seat 1 as the only human, seat 2's bot moves first and the
        -- curtain therefore does NOT raise on entry. Once the bots have
        -- driven the auction back to seat 1, the curtain raises for the
        -- human seat.
        for _ = 1, 200 do
            clock.now = clock.now + 1.0
            j:step(0.016)
            if j:find_text(j:find_localised("scene.table.privacy.prompt", { n = 1 })) then
                break
            end
        end
        assert.is_not_nil(
            j:find_text(j:find_localised("scene.table.privacy.prompt", { n = 1 })),
            "expected privacy curtain on human seat 1 after both bots act"
        )
    end)

    it("defaults every seat's difficulty to 'normal' (Phase 4.2)", function()
        -- Restart with an in-memory auto-save store so we can decode the
        -- session blob and verify the difficulty binding without
        -- touching manager internals.
        if j then
            j:stop()
        end
        local store = {}
        j = journey.start({
            locale = "en",
            width = 1024,
            height = 720,
            auto_save_store = store,
        })
        j:step()
        j:start_single_player_game()
        j:lose_focus()
        local app_json = require("app.json")
        local decoded = app_json.decode(store["auto_save.json"] or "{}")
        assert.is_table(decoded)
        assert.are.same({ "human", "bot", "bot" }, decoded.seatKinds)
        assert.are.same({ "normal", "normal", "normal" }, decoded.seatDifficulties)
    end)

    it("locks the human's perspective for the entire deal (Phase 4.2)", function()
        j:start_single_player_game()
        -- Right after entry, forehand is the bot at seat 2. Phase 4.2
        -- viewer lock means seat 1 still renders as "you" and seat 2 as
        -- Player 2 — the bot's hand never takes over the bottom slot.
        assert.is_not_nil(
            j:find_text(j:find_localised("scene.table.player_label.you")),
            "human seat 1 must render as 'you' even on the bot's turn"
        )
        assert.is_not_nil(
            j:find_text(j:find_localised("scene.table.player_label.other", { n = 2 })),
            "bot at seat 2 must render with the opponent label"
        )
        -- The action panel must be empty during the bot's turn — no bid
        -- buttons rendered. The bid button label is "Bid 100", "Bid 110",
        -- … so no draw should contain the prefix.
        for _, op in ipairs(j:draws()) do
            if op.op == "text" then
                assert.is_nil(
                    op.text:find("Bid ", 1, true),
                    "no bid button text should render while a bot is on turn, got: " .. op.text
                )
            end
        end
        -- The "Bot N thinking…" banner is the only on-turn affordance.
        assert.is_not_nil(
            j:find_text(j:find_localised("scene.table.bot_thinking", { n = 2 })),
            "expected the 'Bot 2 thinking…' banner during the bot's turn"
        )
    end)
end)
