-- Phase 4.2 e2e journey: mixed human + bot composition. Drives the
-- New Game picker to {human, human, bot}, then asserts the viewer
-- behaves correctly across the curtain handoff and bot turns:
--
--   * Forehand seat 2 (human under this composition) gets the curtain
--     raised on entry.
--   * After dismissal, seat 2's auction panel is interactive (it's the
--     viewer and on turn).
--   * After seat 2 passes, control moves to seat 3 (bot). The viewer
--     stays at seat 2: no new curtain raises for seat 3, no auction
--     panel renders during the bot's turn, and the "Bot 3 thinking…"
--     banner shows instead.
--   * Once bot 3 acts, the curtain raises for seat 1 (human) and the
--     handoff completes as in pure hot-seat play.

local journey = require("tests.e2e.support.journey")
local bot_driver = require("app.bot.driver")

local function find_text(j, needle)
    return j._mock.graphics.find_text(needle)
end

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

local function rect_center(rect)
    return rect.x + rect.w * 0.5, rect.y + rect.h * 0.5
end

local function click_button(j, label)
    local rect = smallest_rect_under_text(j, label)
    assert(rect, "no button rectangle for label: " .. label)
    j:click(rect_center(rect))
end

local function dismiss_curtain(j)
    if not find_text(j, j:find_localised("scene.table.privacy.ready_button")) then
        return
    end
    j:click(10, 10)
    j:step()
end

-- Drive the New Game picker to {human, human, bot}: row 1 is human by
-- default, row 2 needs to flip from Bot to Human, row 3 stays as Bot.
-- Then activate Start. Mirrors the keyboard nav used in
-- new_game_journey_spec.lua's mixed-composition test. The Tab path
-- accounts for the per-row difficulty toggle (Phase 4.2): only enabled
-- for bot seats, so once row 2 flips to human the only reachable
-- difficulty toggle is row 3's.
local function start_human_human_bot(j)
    click_button(j, j:find_localised("scene.menu.new_game"))
    j:step()
    j:press_key("tab") -- focus kind row 1
    j:press_key("tab") -- focus kind row 2 (diff row 1 disabled, skipped)
    j:press_key("return") -- cycle row 2 from Bot to Human
    j:press_key("tab") -- focus kind row 3
    j:press_key("tab") -- focus diff row 3 (row 3 still bot)
    j:press_key("tab") -- focus Start
    j:press_key("return")
    j:step()
end

describe("e2e: mixed human/bot composition (Phase 4.2)", function()
    local j
    local clock

    before_each(function()
        clock = { now = 0 }
        bot_driver._clock_for_test = function()
            return clock.now
        end

        j = journey.start({ locale = "en", width = 1024, height = 720 })
        j:step()
        start_human_human_bot(j)
    end)

    after_each(function()
        bot_driver._clock_for_test = nil
        if j then
            j:stop()
        end
    end)

    it("opens with the curtain on the human forehand (seat 2)", function()
        assert.is_not_nil(
            find_text(j, j:find_localised("scene.table.privacy.prompt", { n = 2 })),
            "expected curtain on seat 2 (human forehand under canonical Russian dealer 1)"
        )
    end)

    it("after dismissing seat 2's curtain, the auction panel renders for seat 2", function()
        dismiss_curtain(j)
        assert.is_not_nil(
            find_text(j, j:find_localised("scene.table.auction.bid_button", { amount = 100 })),
            "auction panel must render for the active human (seat 2)"
        )
    end)

    it("keeps the viewer locked to seat 2 while bot 3 is on turn", function()
        dismiss_curtain(j)
        click_button(j, j:find_localised("scene.table.auction.pass_button"))
        j:step()
        -- Turn now belongs to bot seat 3. The bot has a pending
        -- decision (clock has not crossed the delay), so the thinking
        -- banner is up and no action panel renders. The viewer stays
        -- at seat 2: no new curtain for seat 3.
        assert.is_nil(
            find_text(j, j:find_localised("scene.table.privacy.prompt", { n = 3 })),
            "no curtain expected on bot seat 3"
        )
        assert.is_not_nil(
            find_text(j, j:find_localised("scene.table.bot_thinking", { n = 3 })),
            "expected the 'Bot 3 thinking…' banner during the bot turn"
        )
        for _, op in ipairs(j:draws()) do
            if op.op == "text" then
                assert.is_nil(
                    op.text:find("Bid ", 1, true),
                    "no bid button text should render while bot 3 is on turn, got: " .. op.text
                )
            end
        end
    end)

    it("raises the curtain for seat 1 once bot 3 has acted", function()
        dismiss_curtain(j)
        click_button(j, j:find_localised("scene.table.auction.pass_button"))
        j:step()
        -- Advance the bot driver clock past its decision delay so the
        -- pass for seat 3 lands and control moves to seat 1.
        for _ = 1, 20 do
            clock.now = clock.now + 1.0
            j:step(0.016)
            if find_text(j, j:find_localised("scene.table.privacy.prompt", { n = 1 })) then
                break
            end
        end
        assert.is_not_nil(
            find_text(j, j:find_localised("scene.table.privacy.prompt", { n = 1 })),
            "curtain expected for seat 1 after bot 3 passes"
        )
    end)
end)
