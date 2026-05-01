-- Layer 4 entry point. Builds the scene manager, registers the three
-- Phase 2 scenes, and forwards LÖVE callbacks. Keep this file small —
-- everything interesting lives in ui/.

local scene_manager = require("ui.scene_manager")
local menu_scene = require("ui.scenes.menu")
local table_scene = require("ui.scenes.table")
local end_of_game_scene = require("ui.scenes.end_of_game")

local manager = scene_manager.new()

function love.load()
    manager:register("menu", menu_scene.new(manager))
    manager:register("table", table_scene.new(manager))
    manager:register("end_of_game", end_of_game_scene.new(manager))
    manager:switch_to("menu")
end

function love.update(dt)
    manager:update(dt)
end

function love.draw()
    local w, h = love.graphics.getDimensions()
    manager:draw(w, h)
end

function love.mousemoved(x, y, dx, dy)
    manager:mousemoved(x, y, dx, dy)
end

function love.mousepressed(x, y, button)
    manager:mousepressed(x, y, button)
end

function love.mousereleased(x, y, button)
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
