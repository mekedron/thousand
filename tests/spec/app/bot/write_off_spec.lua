-- Phase 3.9: bot stub for the pre-tricks write-off prompt.
-- The placeholder always returns "play"; Phase 4.5 replaces this with
-- a real hand-strength heuristic.

local write_off_bot = require("app.bot.write_off")

describe("app.bot.write_off", function()
    it("always returns 'play' under the placeholder stub", function()
        assert.are.equal("play", write_off_bot.choose(nil))
    end)

    it("ignores its session argument (placeholder is intentionally inert)", function()
        local fake_session = {
            write_off_offer_state = function()
                return { declarer = 2, bid = 100 }
            end,
        }
        assert.are.equal("play", write_off_bot.choose(fake_session))
    end)
end)
