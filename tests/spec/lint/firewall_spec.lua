-- Phase 4.1 algorithm-vs-LLM firewall lint.
--
-- The hard architectural rule: app/bot/ and app/llm/ never import each
-- other, and app/bot/ never imports ui/. The bot module observes a
-- read-only session view and returns engine actions; the LLM client
-- writes character chat. Neither layer may call into the other, and
-- the bot may not depend on UI types either. This spec walks every
-- Lua file under each directory and asserts no forbidden `require`
-- slipped in.

local function list_lua_files(dir)
    local cmd = string.format("find %s -type f -name '*.lua' 2>/dev/null", dir)
    local handle = io.popen(cmd)
    if not handle then
        return {}
    end
    local files = {}
    for line in handle:lines() do
        files[#files + 1] = line
    end
    handle:close()
    table.sort(files)
    return files
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then
        error("firewall spec: could not open " .. path, 2)
    end
    local text = f:read("*a")
    f:close()
    return text
end

-- Strip Lua comments so doc strings like `require("app.llm.*")` in
-- header comments don't read as real imports. Handles line comments
-- (`-- ... EOL`) and the simplest block-comment form (`--[[ ... ]]`).
-- Higher-level `=`-padded block comments are uncommon in this repo;
-- the lint will at worst over-report on them, which the maintainer
-- would catch immediately.
local function strip_lua_comments(text)
    text = text:gsub("%-%-%[%[.-%]%]", " ")
    text = text:gsub("%-%-[^\n]*", "")
    return text
end

-- Scrape every `require(...)` call in `text` and yield the module
-- names referenced. Catches `require("foo.bar")`, `require'foo.bar'`,
-- and the paren-less `require"foo.bar"` form.
local function required_modules(text)
    local stripped = strip_lua_comments(text)
    local modules = {}
    local pattern = "require%s*%(?%s*[\"']([^\"']+)[\"']"
    for module in stripped:gmatch(pattern) do
        modules[#modules + 1] = module
    end
    return modules
end

local function assert_no_imports(file, forbidden_prefixes)
    local text = read_file(file)
    for _, module in ipairs(required_modules(text)) do
        for _, prefix in ipairs(forbidden_prefixes) do
            local hits_exact = module == prefix
            local hits_prefix = module:sub(1, #prefix + 1) == (prefix .. ".")
            assert.is_false(
                hits_exact or hits_prefix,
                file .. " imports forbidden module '" .. module .. "'"
            )
        end
    end
end

describe("algorithm-vs-LLM firewall", function()
    describe("app/bot/", function()
        local files = list_lua_files("app/bot")

        it("contains at least one Lua file (sanity check)", function()
            assert.is_true(#files > 0, "no Lua files found under app/bot/")
        end)

        for _, file in ipairs(files) do
            it(file .. " does not import ui.* or app.llm.*", function()
                assert_no_imports(file, { "ui", "app.llm" })
            end)
        end
    end)

    describe("app/llm/", function()
        local files = list_lua_files("app/llm")

        for _, file in ipairs(files) do
            it(file .. " does not import app.bot.*", function()
                assert_no_imports(file, { "app.bot" })
            end)
        end
    end)
end)
