-- End-to-end journey for the Phase 4.1 bot driver. Drives main → menu →
-- New Game → table with seat_kinds = {"human","bot","bot"}, then ticks
-- frames forward and asserts that:
--
--   * the privacy curtain never raises for bot seats (seats 2 and 3),
--   * the "Bot N thinking…" banner renders while a bot decision is
--     pending,
--   * bot turns auto-resolve via the engine — the auction completes
--     without any human-side input on bot seats,
--   * the human seat (seat 1) still gets its curtain when control
--     returns to it.
--
-- Phase 4.2 will replace the M._test_seat_kinds shortcut with a proper
-- new-game UI; this journey is the closest a 4.1-only commit can land
-- to a real bot-vs-human flow.

local journey = require("tests.e2e.support.journey")
local table_scene = require("ui.scenes.table")
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

describe("e2e: bot driver vs human seat", function()
    local j
    local clock

    before_each(function()
        clock = { now = 0 }
        bot_driver._clock_for_test = function()
            return clock.now
        end
        table_scene._test_seat_kinds = { "human", "bot", "bot" }

        j = journey.start({ locale = "en", width = 1024, height = 720 })
        j:step()
        click_button(j, j:find_localised("scene.menu.new_game"))
        j:step()
    end)

    after_each(function()
        bot_driver._clock_for_test = nil
        table_scene._test_seat_kinds = nil
        if j then
            j:stop()
        end
    end)

    it("does not raise the privacy curtain for the forehand bot seat", function()
        assert.is_nil(
            find_text(j, j:find_localised("scene.table.privacy.prompt", { n = 2 })),
            "no privacy prompt expected for the bot forehand"
        )
        assert.is_nil(
            find_text(j, j:find_localised("scene.table.privacy.ready_button")),
            "no Ready button expected on a bot turn"
        )
    end)

    it("renders the thinking banner while the bot decision is pending", function()
        -- The first bot tick happens during the previous step()'s update.
        -- Re-step at t=0 so the banner draws while the decision is
        -- still pending (clock has not crossed the delay yet).
        j:step(0.0)
        assert.is_not_nil(
            find_text(j, j:find_localised("scene.table.bot_thinking", { n = 2 })),
            "expected 'Bot 2 thinking…' banner during the pending decision"
        )
    end)

    it("auto-passes both bot seats and lands on the human seat 1", function()
        local function step_until(predicate, max_steps)
            for _ = 1, (max_steps or 200) do
                clock.now = clock.now + 1.0
                j:step(0.016)
                if predicate() then
                    return true
                end
            end
            return false
        end

        -- The bot stubs always pass during the auction; after both
        -- bots act, the turn rotates to the human seat 1 and the
        -- curtain prompt appears (human-eyes-protect re-engages).
        local advanced = step_until(function()
            return find_text(j, j:find_localised("scene.table.privacy.prompt", { n = 1 })) ~= nil
        end, 100)

        assert.is_true(advanced, "bots should have driven the auction to the human seat")
        assert.is_not_nil(
            find_text(j, j:find_localised("scene.table.privacy.prompt", { n = 1 })),
            "curtain expected for the human seat once both bots have passed"
        )
    end)
end)
