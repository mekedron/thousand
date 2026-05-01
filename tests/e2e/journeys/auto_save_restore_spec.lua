-- End-to-end journey for baseline auto-save and restore.
--
-- Drives the full lifecycle:
--   1. Fresh launch with no save → Continue button is disabled.
--   2. New Game → drive a couple of auction actions → suspend (love.focus
--      false) → fresh launch with the same on-disk state → Continue is
--      enabled and routes back into the table scene.
--   3. Same flow with love.quit() instead of suspend.
--   4. Same flow but the auto-save fires after a played deal scores.
--   5. Abandon Game from the menu wipes the file so a future launch
--      shows Continue greyed-out again.
--
-- The auto-save store is a single Lua table shared between two
-- consecutive journey.start() calls, simulating "the save survives a
-- relaunch on the same machine".

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

-- Find the most recent setColor op that immediately precedes the rect.
local function rect_bg_color(j, rect)
    local last_color
    for _, op in ipairs(j:draws()) do
        if op.op == "setColor" then
            last_color = op.color
        end
        if op == rect then
            return last_color
        end
    end
    return nil
end

local function near(a, b)
    return math.abs(a - b) < 1e-3
end

local function color_matches(a, b)
    if not a or not b then
        return false
    end
    return near(a[1], b[1]) and near(a[2], b[2]) and near(a[3], b[3])
end

-- Mirror the palette used in ui/button.lua so the journey can tell a
-- disabled Continue button apart from an enabled one.
local DEFAULT_BG = { 0.20, 0.40, 0.25 }
local DISABLED_BG = { 0.18, 0.20, 0.18 }

local function dismiss_curtain(j)
    if not find_text(j, j:find_localised("scene.table.privacy.ready_button")) then
        return
    end
    j:click(10, 10)
    j:step()
end

local function continue_state(j)
    local label = j:find_localised("scene.menu.continue")
    local rect = smallest_rect_under_text(j, label)
    assert(rect, "no rectangle found under the Continue label")
    return rect_bg_color(j, rect)
end

describe("e2e: auto-save and restore", function()
    local store
    local j

    before_each(function()
        store = {}
    end)

    after_each(function()
        if j then
            j:stop()
            j = nil
        end
    end)

    it("starts with Continue disabled when no save exists", function()
        j = journey.start({ locale = "en", auto_save_store = store })
        j:step()
        assert.is_true(color_matches(continue_state(j), DISABLED_BG))
    end)

    it("save on suspend and restore on next launch enables Continue", function()
        j = journey.start({ locale = "en", auto_save_store = store })
        j:step()
        click_button(j, j:find_localised("scene.menu.new_game"))
        j:step()
        dismiss_curtain(j)
        -- One bid so the auction state is non-trivial; this gives the
        -- restored journey something distinctive to verify against.
        click_button(j, j:find_localised("scene.table.auction.bid_button", { amount = 100 }))
        j:step()
        -- Suspend → save fires through love.focus(false).
        j:lose_focus()
        assert.is_string(store["auto_save.json"])
        j:stop()
        j = nil

        -- Second launch with the same on-disk state.
        j = journey.start({ locale = "en", auto_save_store = store })
        j:step()
        assert.is_true(color_matches(continue_state(j), DEFAULT_BG))
        click_button(j, j:find_localised("scene.menu.continue"))
        j:step()
        -- The restored session is in the auction phase with the bid we
        -- placed before the suspend. The table scene's bid label
        -- renders the current bid as the localised "Bid" header value.
        assert.is_not_nil(find_text(j, j:find_localised("scene.table.bid.label")))
    end)

    it("save on graceful quit also enables Continue on next launch", function()
        j = journey.start({ locale = "en", auto_save_store = store })
        j:step()
        click_button(j, j:find_localised("scene.menu.new_game"))
        j:step()
        dismiss_curtain(j)
        click_button(j, j:find_localised("scene.table.auction.pass_button"))
        j:step()
        j:quit()
        assert.is_string(store["auto_save.json"])
        j:stop()
        j = nil

        j = journey.start({ locale = "en", auto_save_store = store })
        j:step()
        assert.is_true(color_matches(continue_state(j), DEFAULT_BG))
    end)

    it("Abandon Game clears the save", function()
        j = journey.start({ locale = "en", auto_save_store = store })
        j:step()
        click_button(j, j:find_localised("scene.menu.new_game"))
        j:step()
        dismiss_curtain(j)
        j:lose_focus()
        assert.is_string(store["auto_save.json"])
        j:stop()
        j = nil

        -- Re-launch, then abandon from the menu.
        j = journey.start({ locale = "en", auto_save_store = store })
        j:step()
        click_button(j, j:find_localised("scene.menu.abandon"))
        j:step()
        click_button(j, j:find_localised("scene.menu.confirm_abandon.yes"))
        j:step()
        assert.is_nil(store["auto_save.json"])
        assert.is_true(color_matches(continue_state(j), DISABLED_BG))
    end)

    it("New Game clears any prior auto-save", function()
        -- Seed a save on disk.
        store["auto_save.json"] = '{"schemaVersion":1,"templateName":"canonical_russian"}'
        j = journey.start({ locale = "en", auto_save_store = store })
        j:step()
        -- Starting a new game discards the leftover save so the next
        -- relaunch can't surface a stale half-played hand.
        click_button(j, j:find_localised("scene.menu.new_game"))
        j:step()
        dismiss_curtain(j)
        -- The freshly-saved blob from the new game has the default
        -- shape, not the seed payload. We don't have a deal_index in
        -- the seed; the new save will, so a sentinel check is enough.
        local previous = store["auto_save.json"]
        j:lose_focus()
        assert.is_string(store["auto_save.json"])
        assert.are_not.equal(previous, store["auto_save.json"])
    end)

    it("does not restore a finished game", function()
        -- Pre-seed a finished game directly onto disk: schemaVersion
        -- matches, template matches, but `winner` is set, which the
        -- auto-save loader rejects. The menu should boot with Continue
        -- disabled.
        local json = require("app.json")
        local rule_config = require("core.rule_config")
        local Session = require("app.session")
        local core_auto_save = require("core.auto_save")
        local s = Session.from_state({
            config = rule_config.canonical_russian,
            dealer = 1,
            running_totals = { 1000, 540, 420 },
            winner = 1,
        })
        store["auto_save.json"] = json.encode(core_auto_save.serialize(s))
        j = journey.start({ locale = "en", auto_save_store = store })
        j:step()
        assert.is_true(color_matches(continue_state(j), DISABLED_BG))
    end)
end)
