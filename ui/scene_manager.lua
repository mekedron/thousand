-- Scene manager. Owns the active scene, forwards Love2D callbacks into it,
-- and tracks whether a game session is in progress so the menu can decide
-- whether to enable its "Abandon Game" affordance.
--
-- The API is shaped so a future stack-based push/pop model is an additive
-- change, not a rename: scenes never see manager.current as a field, and
-- the entry hook receives the previous scene id explicitly.
--
-- The scene contract is intentionally mouse-centric — touch events funnel
-- through the same mouse* dispatches at the layer 4 entry point (see
-- main.lua), so scenes never need to implement :touchpressed / etc. and
-- both input sources reach a single action path.
--
-- Scene contract — every callback is optional:
--   scene:enter(prev_id, params)
--   scene:leave(next_id)
--   scene:update(dt)
--   scene:draw(width, height)
--   scene:mousemoved(x, y, dx, dy)
--   scene:mousepressed(x, y, button)
--   scene:mousereleased(x, y, button)
--   scene:keypressed(key)
--   scene:keyreleased(key)
--   scene:resize(width, height)

local M = {}

local Manager = {}
Manager.__index = Manager

function M.new()
    return setmetatable({
        _scenes = {},
        _active_id = nil,
        _game_active = false,
    }, Manager)
end

function Manager:register(id, scene)
    assert(type(id) == "string", "scene id must be a string")
    assert(type(scene) == "table", "scene must be a table")
    self._scenes[id] = scene
end

function Manager:switch_to(id, params)
    local target = self._scenes[id]
    assert(target, "unknown scene id: " .. tostring(id))
    local prev_id = self._active_id
    if prev_id then
        local prev = self._scenes[prev_id]
        if prev and prev.leave then
            prev:leave(id)
        end
    end
    self._active_id = id
    if target.enter then
        target:enter(prev_id, params)
    end
end

function Manager:active()
    if not self._active_id then
        return nil, nil
    end
    return self._active_id, self._scenes[self._active_id]
end

function Manager:set_game_active(value)
    self._game_active = value and true or false
end

function Manager:is_game_active()
    return self._game_active
end

local function dispatch(self, name, ...)
    if not self._active_id then
        return
    end
    local scene = self._scenes[self._active_id]
    local fn = scene and scene[name]
    if fn then
        return fn(scene, ...)
    end
end

function Manager:update(dt)
    return dispatch(self, "update", dt)
end

function Manager:draw(w, h)
    return dispatch(self, "draw", w, h)
end

function Manager:mousemoved(x, y, dx, dy)
    return dispatch(self, "mousemoved", x, y, dx, dy)
end

function Manager:mousepressed(x, y, button)
    return dispatch(self, "mousepressed", x, y, button)
end

function Manager:mousereleased(x, y, button)
    return dispatch(self, "mousereleased", x, y, button)
end

function Manager:keypressed(key)
    return dispatch(self, "keypressed", key)
end

function Manager:keyreleased(key)
    return dispatch(self, "keyreleased", key)
end

function Manager:resize(w, h)
    return dispatch(self, "resize", w, h)
end

return M
