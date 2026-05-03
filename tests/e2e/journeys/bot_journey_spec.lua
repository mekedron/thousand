-- End-to-end journey for the bot driver vs a single human seat.
-- Drives main → menu → Single Player → table with seat_kinds =
-- {"human","bot","bot"}, then ticks frames forward and asserts that:
--
--   * the privacy curtain never raises for bot seats (seats 2 and 3),
--   * the "Bot N thinking…" banner renders while a bot decision is
--     pending,
--   * bot turns auto-resolve via the engine — the auction completes
--     without any human-side input on bot seats,
--   * the human seat (seat 1) still gets its curtain when control
--     returns to it.
--
-- Phase 4.2 retired the `M._test_seat_kinds` backdoor; this journey now
-- drives the real new-game flow via the Single Player main-menu entry.

local journey = require("tests.e2e.support.journey")
local bot_driver = require("app.bot.driver")

local function find_text(j, needle)
    return j._mock.graphics.find_text(needle)
end

describe("e2e: bot driver vs human seat", function()
    local j
    local clock

    before_each(function()
        clock = { now = 0 }
        bot_driver._clock_for_test = function()
            return clock.now
        end

        j = journey.start({ locale = "en", width = 1024, height = 720 })
        j:step()
        -- Single Player produces the exact composition this journey
        -- wants: seat 1 = human, seats 2 and 3 = bots.
        j:start_single_player_game()
    end)

    after_each(function()
        bot_driver._clock_for_test = nil
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
