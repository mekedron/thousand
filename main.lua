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
local new_game_scene = require("ui.scenes.new_game")
local table_scene = require("ui.scenes.table")
local end_of_game_scene = require("ui.scenes.end_of_game")
local settings_scene = require("ui.scenes.settings")
local template_picker_scene = require("ui.scenes.template_picker")
local template_editor_scene = require("ui.scenes.template_editor")
local auto_save = require("app.auto_save")

local manager = scene_manager.new()
local touch_active = false
local touch_active_clear_pending = false

-- Tracks the last (phase, deal_index) snapshot we wrote to disk so the
-- per-frame auto-save trigger only fires on real transitions. Cleared
-- whenever the manager has no active session (Quit/Abandon).
local last_save_phase_key = nil

local OFFSCREEN = -1e6

function love.load()
    manager:register("menu", menu_scene.new(manager))
    manager:register("new_game", new_game_scene.new(manager))
    manager:register("table", table_scene.new(manager))
    manager:register("end_of_game", end_of_game_scene.new(manager))
    manager:register("settings", settings_scene.new(manager))
    manager:register("template_picker", template_picker_scene.new(manager))
    manager:register("template_editor", template_editor_scene.new(manager))
    -- Restore an in-progress game from the previous launch, if any. The
    -- auto-save module returns nil for missing / corrupt / finished
    -- saves, so a fresh install boots straight to the menu.
    local restored = auto_save.load()
    if restored then
        manager:set_session(restored)
    end
    manager:switch_to("menu")
end

local function save_active_session()
    if not manager:is_game_active() then
        return
    end
    local s = manager:session()
    if s:current_phase() == "done" then
        return
    end
    auto_save.save(s)
end

function love.update(dt)
    if touch_active_clear_pending then
        touch_active = false
        touch_active_clear_pending = false
    end
    manager:update(dt)
    -- Auto-save trigger: poll for transitions into deal_done / done. The
    -- session derives current_phase from internal state, so each scored
    -- deal (and the final deal that ends the game) is exactly one
    -- transition we observe and save against. Game-over also clears
    -- the file so a future launch doesn't restore a finished match.
    if manager:is_game_active() then
        local s = manager:session()
        local key = s:current_phase() .. ":" .. tostring(s._deal_index or 0)
        if last_save_phase_key ~= key then
            last_save_phase_key = key
            local phase = s:current_phase()
            if phase == "deal_done" then
                auto_save.save(s)
            elseif phase == "done" then
                auto_save.clear()
            end
        end
    else
        last_save_phase_key = nil
    end
end

function love.quit()
    save_active_session()
    return false
end

function love.focus(focused)
    if not focused then
        save_active_session()
    end
end

function love.visible(visible)
    if not visible then
        save_active_session()
    end
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

function love.wheelmoved(dx, dy)
    manager:wheelmoved(dx, dy)
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
