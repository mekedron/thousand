-- Layer 4 entry point. Builds the scene manager, registers the three
-- Phase 2 scenes, and forwards LÖVE callbacks. Keep this file small —
-- everything interesting lives in ui/.
--
-- Touch / mouse parity
-- --------------------
-- Touch events funnel into the same manager:mouse* pipeline scenes
-- already use, so the scene contract stays mouse-centric and there is
-- exactly one action path for both input sources. Two iOS-specific
-- pitfalls are handled here at layer 4:
--
--   * Mouse-from-touch double-fire. LÖVE 11.x synthesises mouse events
--     from the first touch on touchscreen platforms. We track a
--     `touch_active` flag set in love.touchpressed and cleared one frame
--     after love.touchreleased (via love.update); the mouse callbacks
--     return early while it is set, so the synthesised events do not
--     reach the scene. The next-frame deferral catches synthesised
--     mouse events that fire AFTER touchreleased in the same event
--     drain.
--   * Stuck hover state. Touch has no "cursor leaves" event, so a touch
--     drag that lands on a button would leave it visually hovered after
--     release. love.touchreleased dispatches a far-off-screen mousemoved
--     so every button's :on_mousemoved miss-tests and clears `hovered`.

local scene_manager = require("ui.scene_manager")
local menu_scene = require("ui.scenes.menu")
local table_scene = require("ui.scenes.table")
local end_of_game_scene = require("ui.scenes.end_of_game")

local manager = scene_manager.new()
local touch_active = false
local touch_active_clear_pending = false

local OFFSCREEN = -1e6

function love.load()
    manager:register("menu", menu_scene.new(manager))
    manager:register("table", table_scene.new(manager))
    manager:register("end_of_game", end_of_game_scene.new(manager))
    manager:switch_to("menu")
end

function love.update(dt)
    if touch_active_clear_pending then
        touch_active = false
        touch_active_clear_pending = false
    end
    manager:update(dt)
end

function love.draw()
    local w, h = love.graphics.getDimensions()
    manager:draw(w, h)
end

function love.mousemoved(x, y, dx, dy)
    if touch_active then
        return
    end
    manager:mousemoved(x, y, dx, dy)
end

function love.mousepressed(x, y, button)
    if touch_active then
        return
    end
    manager:mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
    if touch_active then
        return
    end
    manager:mousereleased(x, y, button)
end

function love.keypressed(key)
    manager:keypressed(key)
end

function love.keyreleased(key)
    manager:keyreleased(key)
end

function love.resize(w, h)
    manager:resize(w, h)
end

function love.touchpressed(_id, x, y, _dx, _dy, _pressure)
    touch_active = true
    manager:mousepressed(x, y, 1)
end

function love.touchmoved(_id, x, y, dx, dy, _pressure)
    manager:mousemoved(x, y, dx or 0, dy or 0)
end

function love.touchreleased(_id, x, y, _dx, _dy, _pressure)
    manager:mousereleased(x, y, 1)
    -- Touch has no "cursor leaves" event; clear lingering button hover.
    manager:mousemoved(OFFSCREEN, OFFSCREEN, 0, 0)
    -- Defer flag clear until next frame's update so synthesised mouse
    -- events that fire AFTER touchreleased in the same event drain are
    -- still suppressed.
    touch_active_clear_pending = true
end
