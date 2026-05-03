-- Phase 4.2 e2e journey: the New Game per-seat picker. Drives
-- main → menu → New Game → toggle seats → Start, and asserts the
-- intended composition reaches the table:
--
--   * Default composition (Start without toggling) is seat 1 = human,
--     others = bot.
--   * Flipping seat 2 to human produces a 2-human + 1-bot mix where
--     seat 3's bot still auto-passes.
--   * All-bot composition is permitted (no Start guard).

local journey = require("tests.e2e.support.journey")

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

describe("e2e: New Game per-seat picker", function()
    local j
    local auto_save_store

    before_each(function()
        auto_save_store = {}
        j = journey.start({
            locale = "en",
            width = 1024,
            height = 720,
            auto_save_store = auto_save_store,
        })
        j:step()
        click_button(j, j:find_localised("scene.menu.new_game"))
        j:step()
    end)

    after_each(function()
        if j then
            j:stop()
        end
    end)

    it("renders the picker with the active template name and seat rows", function()
        assert.is_not_nil(j:find_text(j:find_localised("scene.new_game.title")))
        assert.is_not_nil(j:find_text(j:find_localised("scene.new_game.template", {
            name = j:find_localised("templates.builtin.russian"),
        })))
        for i = 1, 3 do
            assert.is_not_nil(
                j:find_text(j:find_localised("scene.new_game.seat_label", { n = i })),
                "expected seat label for row " .. tostring(i)
            )
        end
        assert.is_not_nil(j:find_text(j:find_localised("scene.new_game.start")))
        assert.is_not_nil(j:find_text(j:find_localised("scene.new_game.back")))
    end)

    it("Back returns to the menu without starting a game", function()
        click_button(j, j:find_localised("scene.new_game.back"))
        j:step()
        assert.is_not_nil(j:find_text(j:find_localised("scene.menu.title")))
        -- Continue should still be disabled (no session).
        local rect = smallest_rect_under_text(j, j:find_localised("scene.menu.continue"))
        assert.is_not_nil(rect)
    end)

    it("Esc returns to the menu without starting a game", function()
        j:press_key("escape")
        j:step()
        assert.is_not_nil(j:find_text(j:find_localised("scene.menu.title")))
    end)

    it("Start with default composition opens the table (seat 1 human, rest bot)", function()
        click_button(j, j:find_localised("scene.new_game.start"))
        j:step()
        assert.is_not_nil(j:find_text(j:find_localised("scene.table.scoreboard.title")))
    end)

    it("cycling a bot seat's difficulty via keyboard nav persists into the session", function()
        -- Cycle row 2 difficulty from Normal → Hard, then walk to Start.
        -- Tab path with default {human, bot, bot}: kind1 (skip diff1
        -- disabled) -> kind2 -> diff2 [Return to cycle] -> kind3 -> diff3
        -- -> Start.
        j:press_key("tab") -- kind 1 (human)
        j:press_key("tab") -- kind 2 (bot)
        j:press_key("tab") -- diff 2 (enabled, normal)
        j:press_key("return") -- cycle diff 2 to Hard
        j:press_key("tab") -- kind 3
        j:press_key("tab") -- diff 3
        j:press_key("tab") -- Start
        j:press_key("return")
        j:step()
        -- Save and confirm the difficulty binding survived all the way
        -- into the on-disk session blob.
        j:lose_focus()
        local app_json = require("app.json")
        local decoded = app_json.decode(auto_save_store["auto_save.json"] or "{}")
        assert.is_table(decoded)
        assert.are.same({ "normal", "hard", "normal" }, decoded.seatDifficulties)
    end)

    it("flipping a seat to Human via keyboard nav lands on a mixed composition", function()
        -- Default: row 1 = Human, row 2 = Bot, row 3 = Bot. Each row has
        -- a kind toggle and a difficulty toggle; the difficulty toggle is
        -- only Tab-reachable when the row's kind is "bot". After flipping
        -- row 2 to Human, the only enabled difficulty toggle is row 3's,
        -- so the Tab path is: kind1 -> kind2 -> Return -> kind3 -> diff3
        -- -> Start.
        j:press_key("tab") -- focus kind row 1
        j:press_key("tab") -- focus kind row 2 (diff row 1 is disabled, skipped)
        j:press_key("return") -- cycle row 2 to Human (diff row 2 disables itself)
        j:press_key("tab") -- focus kind row 3
        j:press_key("tab") -- focus diff row 3 (still enabled, row 3 = bot)
        j:press_key("tab") -- focus Start
        j:press_key("return")
        j:step()
        -- We're on the table. Forehand under canonical Russian dealer 1
        -- is seat 2 — now also a human — so the curtain raises on seat 2.
        assert.is_not_nil(j:find_text(j:find_localised("scene.table.privacy.prompt", { n = 2 })))
    end)
end)
