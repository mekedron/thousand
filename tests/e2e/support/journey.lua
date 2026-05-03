-- Journey driver for the e2e harness. Wraps the love-mock, loads main.lua
-- against it, and exposes a small action surface so journey specs can
-- exercise the running game from a fresh-launch state.
--
-- Usage (see tests/e2e/journeys/launch_journey_spec.lua for a real example):
--
--   local journey = require("tests.e2e.support.journey")
--
--   describe("e2e: …", function()
--       local j
--       before_each(function() j = journey.start({ locale = "en" }) end)
--       after_each(function() if j then j:stop() end end)
--
--       it("renders something", function()
--           j:step()
--           assert.is_not_nil(j:screen().clear)
--       end)
--   end)
--
-- The driver always resets app.i18n module state in start() so locale and
-- missing-key state cannot leak between tests, and it force-reloads main
-- via package.loaded.main = nil so each journey binds the entry-point
-- callbacks (love.load, love.draw, …) to its own mock — without that,
-- two consecutive starts would leave callbacks bound to the first mock.

local love_mock = require("tests.e2e.support.love_mock")

local Journey = {}
Journey.__index = Journey

local M = {}

local function noop() end

local function reset_i18n(locale)
    local i18n = require("app.i18n")
    i18n._reset()
    i18n._set_logger(noop)
    i18n.set_locale(locale)
    return i18n
end

-- Drop settings module state so each journey starts with the default
-- toggle values. We can't simply unload the package — scenes capture
-- the module reference at require time and would still see the old
-- table — so call its test-only _reset hook on whichever instance
-- they captured.
local function reset_settings()
    local ok, settings = pcall(require, "app.settings")
    if ok and settings and settings._reset then
        settings._reset()
    end
end

-- Reset auto-save module state so each journey starts with no
-- carry-over save. Tests that exercise the save/restore flow pass an
-- explicit `auto_save_store` option (a table acting as in-memory
-- storage shared across two journey instances) — without it, auto_save
-- falls back to its in-memory transient storage and behaves as if no
-- save file is present.
local function reset_auto_save(opts)
    local ok, auto_save = pcall(require, "app.auto_save")
    if not ok or not auto_save or not auto_save._reset then
        return
    end
    auto_save._reset()
    local store = opts.auto_save_store
    if store then
        local read_fn = function(path)
            return store[path]
        end
        local write_fn = function(path, content)
            store[path] = content
            return true
        end
        local remove_fn = function(path)
            store[path] = nil
            return true
        end
        auto_save._set_storage(read_fn, write_fn, remove_fn)
    end
end

function M.start(opts)
    opts = opts or {}
    local locale = opts.locale or "en"

    local i18n = reset_i18n(locale)
    reset_settings()
    reset_auto_save(opts)

    local mock = love_mock.new({
        width = opts.width or 800,
        height = opts.height or 600,
    })
    mock:install()

    -- Defeat Lua's module cache: main.lua sets love.load / love.draw on
    -- whichever `love` global was alive at require time. Without this
    -- reset, the second start() would leave callbacks bound to the
    -- previous mock. main.lua at the repo root resolves through the
    -- default package.path entry `./?.lua` because busted runs from
    -- the project root.
    --
    -- ui/ scenes are created per-journey too: the scene_manager module
    -- itself is stateless (M.new() returns a fresh table) but main.lua
    -- builds its manager via require, and the menu / table / end_of_game
    -- modules need a fresh instance bound to the new manager. Forcing
    -- main to re-execute on each start handles this transparently.
    package.loaded.main = nil
    require("main")

    -- Mirror LÖVE's boot sequence: love.load fires once before the first
    -- frame. The scene manager registers and activates its initial scene
    -- here; without it, journey:step() would draw against an empty
    -- manager.
    mock:dispatch("load")

    local self = setmetatable({}, Journey)
    self._mock = mock
    self._i18n = i18n
    self._stopped = false
    return self
end

function Journey:step(dt)
    dt = dt or 0.016
    -- Each step represents one rendered frame: the recording shows only the
    -- ops produced by this update + draw cycle so journey assertions can
    -- speak about "what's on screen now" without filtering out history.
    self._mock.graphics.clear_recording()
    self._mock:dispatch("update", dt)
    self._mock:dispatch("draw")
end

function Journey:click(x, y, button)
    button = button or 1
    -- Mirror real interaction: hover, press, release at the same coords.
    -- Buttons key their hit-test off contains(x, y) rather than the hover
    -- flag, so the move is for visual-state coverage, not click correctness.
    self._mock:dispatch("mousemoved", x, y, 0, 0)
    self._mock:dispatch("mousepressed", x, y, button)
    self._mock:dispatch("mousereleased", x, y, button)
end

function Journey:hover(x, y)
    self._mock:dispatch("mousemoved", x, y, 0, 0)
end

function Journey:release(x, y, button)
    button = button or 1
    self._mock:dispatch("mousereleased", x, y, button)
end

function Journey:press(x, y, button)
    button = button or 1
    self._mock:dispatch("mousepressed", x, y, button)
end

-- Touch dispatch path. Mirrors :click but goes through love.touchpressed /
-- love.touchreleased so journey specs can exercise the same code path real
-- iOS / Android devices would. main.lua suppresses synthesised mouse
-- callbacks while a touch is in flight (see touch_active there); these
-- helpers lay each gesture stage bare so specs can prove that behaviour.

function Journey:touch(x, y)
    self:press_touch(x, y)
    self:release_touch(x, y)
end

function Journey:press_touch(x, y)
    self._mock:dispatch("touchpressed", 1, x, y, 0, 0, 1)
end

function Journey:move_touch(x, y, dx, dy)
    self._mock:dispatch("touchmoved", 1, x, y, dx or 0, dy or 0, 1)
end

function Journey:release_touch(x, y)
    self._mock:dispatch("touchreleased", 1, x, y, 0, 0, 1)
end

function Journey:click_text(needle)
    local op = self:find_text(needle)
    if not op then
        return false
    end
    -- print/printf record the text origin in screen-space; we have no
    -- font metrics yet, so click the origin. Phase 2 button scenes that
    -- wrap text in a rectangle should call click() with the rectangle's
    -- center directly until the harness grows real font geometry.
    self:click(op.x, op.y)
    return true
end

function Journey:press_key(key)
    self._mock:dispatch("keypressed", key)
    self._mock:dispatch("keyreleased", key)
end

function Journey:resize(w, h)
    self._mock:dispatch("resize", w, h)
end

-- Lifecycle helpers used by the auto-save journey. `quit` simulates a
-- graceful close (Cmd+Q / window close button). `lose_focus` and
-- `become_invisible` simulate the app moving to the background or being
-- minimised on iOS / Android, which LÖVE surfaces via love.focus and
-- love.visible respectively.
function Journey:quit()
    self._mock:dispatch("quit")
end

function Journey:lose_focus()
    self._mock:dispatch("focus", false)
end

function Journey:become_invisible()
    self._mock:dispatch("visible", false)
end

function Journey:find_text(needle)
    return self._mock.graphics.find_text(needle)
end

-- Phase 4.2: walks main menu → New Game → picker → Start with every
-- seat set to Human, landing on the table scene with all-human
-- composition. Phase 2 / 3 journeys that previously did
-- `click "New Game"` and expected to be on the table use this instead,
-- because the new-game flow now passes through a per-seat picker.
function Journey:start_hot_seat_game()
    local function smallest_rect_under_text(text)
        local best
        local draws = self:draws()
        for _, op in ipairs(draws) do
            if op.op == "rectangle" and op.mode == "fill" then
                for _, t in ipairs(draws) do
                    if
                        t.op == "text"
                        and t.text == text
                        and t.x >= op.x
                        and t.x <= op.x + op.w
                        and t.y >= op.y
                        and t.y <= op.y + op.h
                    then
                        if not best or (op.w * op.h) < (best.w * best.h) then
                            best = op
                        end
                    end
                end
            end
        end
        return best
    end
    local function click_button_by_label(label)
        local rect = smallest_rect_under_text(label)
        assert(rect, "no button rectangle found for label: " .. label)
        self:click(rect.x + rect.w * 0.5, rect.y + rect.h * 0.5)
    end

    click_button_by_label(self:find_localised("scene.menu.new_game"))
    self:step()
    -- Flip rows 2..N from Bot to Human via keyboard nav. The picker
    -- defaults to row 1 = Human, rows 2..N = Bot. Tab seeds focus on
    -- row 1; subsequent Tab + Enter cycles each Bot row to Human;
    -- final Tab + Enter activates Start.
    local app_templates = require("app.templates")
    local seat_count = app_templates.resolve_active_config().players.count
    self:press_key("tab")
    for _ = 2, seat_count do
        self:press_key("tab")
        self:press_key("return")
    end
    self:press_key("tab")
    self:press_key("return")
    self:step()
end

-- Phase 4.2: one-click Single Player — seat 1 = human, every other
-- seat = bot under the active template's player count. The bot driver
-- runs the rest. Useful for journeys that don't care about seat
-- composition specifics, only about reaching the table from the menu.
function Journey:start_single_player_game()
    local function smallest_rect_under_text(text)
        local best
        local draws = self:draws()
        for _, op in ipairs(draws) do
            if op.op == "rectangle" and op.mode == "fill" then
                for _, t in ipairs(draws) do
                    if
                        t.op == "text"
                        and t.text == text
                        and t.x >= op.x
                        and t.x <= op.x + op.w
                        and t.y >= op.y
                        and t.y <= op.y + op.h
                    then
                        if not best or (op.w * op.h) < (best.w * best.h) then
                            best = op
                        end
                    end
                end
            end
        end
        return best
    end
    local rect = smallest_rect_under_text(self:find_localised("scene.menu.single_player"))
    assert(rect, "no button rectangle found for label: Single Player")
    self:click(rect.x + rect.w * 0.5, rect.y + rect.h * 0.5)
    self:step()
end

function Journey:find_localised(key, params)
    return self._i18n.t(key, params)
end

function Journey:draws()
    return self._mock.graphics.recording()
end

function Journey:screen()
    local clear, texts, rects = nil, {}, {}
    for _, op in ipairs(self._mock.graphics.recording()) do
        if op.op == "clear" then
            clear = op.color
        elseif op.op == "text" then
            texts[#texts + 1] = op
        elseif op.op == "rectangle" then
            rects[#rects + 1] = op
        end
    end
    return { clear = clear, texts = texts, rectangles = rects }
end

function Journey:stop()
    if self._stopped then
        return
    end
    self._mock:restore()
    self._stopped = true
end

return M
