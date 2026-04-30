-- Luacheck configuration for the Thousand Love2D project.
-- LÖVE 11.x runs on LuaJIT (Lua 5.1 with extensions).

std = "luajit"

-- LÖVE injects `love` as a global, and the project assigns its entry-point
-- callbacks (love.load, love.draw, love.update, …) — so `love` is a writable
-- global, not a read-only one.
globals = { "love" }

-- Third-party clone of the love2d-mcp bridge — ignored at the repo root via
-- .gitignore, but if a developer clones it locally, do not lint it.
exclude_files = {
    "love2d-mcp/",
    "docs-site/",
}

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
