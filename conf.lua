-- LÖVE configuration for Thousand. See https://love2d.org/wiki/Config_Files.

function love.conf(t)
    t.identity = "thousand"
    t.version = "11.5"
    t.console = false

    t.window.title = "Thousand"
    t.window.width = 1280
    t.window.height = 720
    t.window.resizable = true
    t.window.minwidth = 800
    t.window.minheight = 600
    t.window.highdpi = true
    t.window.usedpiscale = true

    -- A card game does not need physics, video, or joystick input.
    t.modules.physics = false
    t.modules.video = false
    t.modules.joystick = false
end
