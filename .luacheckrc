-- Luacheck configuration for the Thousand Love2D project.
-- LÖVE 11.x runs on LuaJIT (Lua 5.1 with extensions).

std = "luajit"

-- LÖVE injects `love` as a global; it is the only global the engine adds.
read_globals = { "love" }

-- Tests run under busted, which injects describe/it/before_each/after_each/setup/teardown
-- and the assert/spy/stub/mock helpers.
files["tests/**/*.lua"] = {
    std = "+busted",
    read_globals = { "describe", "it", "before_each", "after_each", "setup", "teardown" },
}

-- Locale tables are pure data files keyed by locale code; they should not
-- trigger "module returns nothing useful" warnings.
files["assets/i18n/*.lua"] = {
    ignore = { "631" }, -- line is too long (translations may exceed)
}

-- Conventional placeholder for unused arguments / loop variables.
ignore = {
    "212/_.*", -- unused argument starting with _
    "213/_.*", -- unused loop variable starting with _
}

max_line_length = 100
