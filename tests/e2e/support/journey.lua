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

function M.start(opts)
    opts = opts or {}
    local locale = opts.locale or "en"

    local i18n = reset_i18n(locale)

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

function Journey:find_text(needle)
    return self._mock.graphics.find_text(needle)
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
