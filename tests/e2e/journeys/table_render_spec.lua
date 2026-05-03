-- End-to-end journey for the playable table render. Drives main → menu →
-- New Game → table and asserts the scoreboard, opponent strip, talon,
-- bid / turn / trump / phase indicators, and the active player's hand
-- are all present on screen with the expected localised labels.

local journey = require("tests.e2e.support.journey")

local function find_text(j, needle)
    return j._mock.graphics.find_text(needle)
end

local function go_to_table(j)
    -- Phase 4.2: New Game now passes through the per-seat picker.
    -- start_hot_seat_game flips every row to Human and presses Start so
    -- this helper preserves the Phase 2 hot-seat semantics.
    j:start_hot_seat_game()
end

describe("e2e: render playable table state", function()
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

    describe("a fresh New Game lands on a populated table", function()
        before_each(function()
            go_to_table(j)
        end)

        it("renders the scoreboard column", function()
            assert.is_not_nil(find_text(j, j:find_localised("scene.table.scoreboard.title")))
        end)

        it("labels the active seat as the local player and the rest as opponents", function()
            -- Active turn (forehand) renders at the bottom as "Your hand"
            -- in hot-seat mode; the other two seats are opponents. The
            -- active seat rotates with the turn — perspective tracks
            -- is_turn so input wiring lands on whichever player is acting.
            assert.is_not_nil(find_text(j, j:find_localised("scene.table.player_label.you")))
            assert.is_not_nil(
                find_text(j, j:find_localised("scene.table.player_label.other", { n = 1 }))
            )
            assert.is_not_nil(
                find_text(j, j:find_localised("scene.table.player_label.other", { n = 3 }))
            )
        end)

        it("renders the centre band labels: bid / turn / trump / phase / talon", function()
            assert.is_not_nil(find_text(j, j:find_localised("scene.table.bid.label")))
            assert.is_not_nil(find_text(j, j:find_localised("scene.table.turn.label")))
            assert.is_not_nil(find_text(j, j:find_localised("scene.table.trump.label")))
            assert.is_not_nil(find_text(j, j:find_localised("scene.table.phase.label")))
            assert.is_not_nil(find_text(j, j:find_localised("scene.table.talon.label")))
        end)

        it("starts in the auction phase", function()
            assert.is_not_nil(find_text(j, j:find_localised("scene.table.phase.auction")))
        end)

        it("draws at least seven face-up card rectangles for the active hand", function()
            -- Each face-up card draws a fill rect of its own size; cards in
            -- the bottom strip share a y-coordinate. Count fills whose
            -- height roughly matches the card height range.
            local count = 0
            for _, op in ipairs(j:draws()) do
                if op.op == "rectangle" and op.mode == "fill" and op.w >= 30 and op.h >= 40 then
                    count = count + 1
                end
            end
            assert.is_true(count >= 7, "expected at least 7 card rectangles, got " .. count)
        end)

        it("keeps the back-to-menu button available", function()
            assert.is_not_nil(find_text(j, j:find_localised("scene.table.back_to_menu")))
        end)
    end)

    describe("table reflows with the window", function()
        it("re-renders without crashing across multiple sizes", function()
            go_to_table(j)
            for _, size in ipairs({ { 800, 600 }, { 1280, 720 }, { 1600, 900 } }) do
                j:resize(size[1], size[2])
                j:step()
                assert.is_not_nil(
                    find_text(j, j:find_localised("scene.table.scoreboard.title")),
                    "scoreboard at " .. size[1] .. "x" .. size[2]
                )
            end
        end)
    end)
end)
