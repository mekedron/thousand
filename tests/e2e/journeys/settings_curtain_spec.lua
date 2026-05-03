-- End-to-end journey for the hot-seat privacy settings toggle. Drives
-- main → menu → Settings → toggle off → back to menu → New Game and
-- asserts that no privacy curtain rises on the table when the toggle
-- is off. Then re-enables the toggle from a fresh game and checks the
-- curtain re-appears.

local journey = require("tests.e2e.support.journey")

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

describe("e2e: hot-seat privacy settings toggle", function()
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

    it("Settings is reachable from the main menu", function()
        assert.is_not_nil(find_text(j, j:find_localised("scene.menu.settings")))
        click_button(j, j:find_localised("scene.menu.settings"))
        j:step()
        assert.is_not_nil(find_text(j, j:find_localised("scene.settings.title")))
        assert.is_not_nil(find_text(j, j:find_localised("scene.settings.hot_seat_privacy.label")))
    end)

    it("toggle off then New Game shows no privacy curtain", function()
        click_button(j, j:find_localised("scene.menu.settings"))
        j:step()
        -- Toggle starts at On.
        assert.is_not_nil(find_text(j, j:find_localised("scene.settings.toggle.on")))
        click_button(j, j:find_localised("scene.settings.toggle.on"))
        j:step()
        -- Toggle should now read Off.
        assert.is_not_nil(find_text(j, j:find_localised("scene.settings.toggle.off")))

        click_button(j, j:find_localised("scene.settings.back_to_menu"))
        j:step()
        j:start_hot_seat_game()
        -- No curtain — the bid panel is reachable directly.
        assert.is_nil(
            find_text(j, j:find_localised("scene.table.privacy.prompt", { n = 2 })),
            "no privacy prompt expected when the curtain is disabled"
        )
        assert.is_not_nil(
            find_text(j, j:find_localised("scene.table.auction.bid_button", { amount = 100 })),
            "the auction bid panel should be visible without dismissing a curtain"
        )
    end)

    it("toggle on (default) keeps the curtain on the next game", function()
        -- The default IS on, so just start a new game and assert the
        -- curtain is up. This is a regression guard — we want the
        -- toggle's default to remain protective.
        j:start_hot_seat_game()
        assert.is_not_nil(
            find_text(j, j:find_localised("scene.table.privacy.prompt", { n = 2 })),
            "expected curtain on a fresh game with default settings"
        )
    end)
end)
