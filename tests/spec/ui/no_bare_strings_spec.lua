-- Renders the i18n routing guarantee at the rendering boundary: every
-- love.graphics.print / love.graphics.printf call in the ui/ tree must
-- pass a non-literal first argument (typically t(...) or a variable
-- holding a t() result, or tostring(number)).
--
-- The shell-level gate at tools/check_i18n.sh scans for any whitespace
-- string literal in ui/ and app/. This spec narrows the scope to
-- love.graphics.print* call sites specifically — the actual rendering
-- surface — and runs in the same suite as the rest of the unit tests
-- so a regression breaks `make test`, not just `make check`.
--
-- Implementation note: works on the file content as text via simple
-- pattern matching. We don't need a Lua parser because the codebase
-- never builds print arguments inline beyond either a t(...) call or
-- a pre-localised variable, and we explicitly look for the dangerous
-- shape (quoted-string literal as first argument).

local function list_lua_files(dir)
    local files = {}
    local handle = io.popen('find "' .. dir .. '" -type f -name "*.lua"')
    if not handle then
        return files
    end
    for line in handle:lines() do
        files[#files + 1] = line
    end
    handle:close()
    table.sort(files)
    return files
end

local function read_file(path)
    local f = assert(io.open(path, "rb"))
    local content = f:read("*a")
    f:close()
    return content
end

-- Returns a list of {line, snippet} entries for every love.graphics.print
-- and love.graphics.printf call site whose first argument is a bare string
-- literal (double or single quoted).
local function find_bare_print_literals(content)
    local hits = {}
    -- Match `love.graphics.print` or `love.graphics.printf`, optional
    -- whitespace, opening paren, optional whitespace, then the start of
    -- the first argument. The first argument is bare-literal when it
    -- begins with " or '.
    local pattern = "love%.graphics%.printf?%s*%(%s*(['\"])"
    local cursor = 1
    while true do
        local s, e, quote = content:find(pattern, cursor)
        if not s then
            break
        end
        -- Compute line number for the match.
        local prefix = content:sub(1, s)
        local _, line_count = prefix:gsub("\n", "\n")
        local line_num = line_count + 1
        -- Capture the literal content (up to the matching close quote).
        local lit_start = e
        local lit_end = content:find(quote, lit_start + 1, true) or lit_start
        local snippet = content:sub(s, math.min(lit_end, s + 80))
        hits[#hits + 1] = { line = line_num, snippet = snippet }
        cursor = e + 1
    end
    return hits
end

describe("ui/ rendering surface — no bare strings in love.graphics.print*", function()
    it("scans every .lua file under ui/", function()
        local files = list_lua_files("ui")
        assert.is_true(#files > 0, "expected at least one .lua file under ui/")
        local violations = {}
        for _, path in ipairs(files) do
            local content = read_file(path)
            local hits = find_bare_print_literals(content)
            for _, hit in ipairs(hits) do
                violations[#violations + 1] = path .. ":" .. hit.line .. ": " .. hit.snippet
            end
        end
        if #violations > 0 then
            error(
                "love.graphics.print* called with a literal string argument:\n  "
                    .. table.concat(violations, "\n  ")
                    .. "\nRoute through i18n.t(<key>) or store the localised"
                    .. " value in a variable first.",
                2
            )
        end
    end)

    it("would catch a regression that prints a literal string", function()
        local sample = [[
            love.graphics.print("New Game", x, y)
        ]]
        local hits = find_bare_print_literals(sample)
        assert.are.equal(1, #hits)
        assert.is_truthy(hits[1].snippet:find("New Game", 1, true))
    end)

    it("ignores t() calls", function()
        local sample = [[
            love.graphics.print(t("scene.menu.new_game"), x, y)
        ]]
        local hits = find_bare_print_literals(sample)
        assert.are.equal(0, #hits)
    end)

    it("ignores variable arguments", function()
        local sample = [[
            love.graphics.print(label, x, y)
            love.graphics.printf(prompt, x, y, w, "center")
        ]]
        local hits = find_bare_print_literals(sample)
        assert.are.equal(0, #hits)
    end)

    it("ignores tostring() arguments", function()
        local sample = [[
            love.graphics.print(tostring(view.current_bid), x, y)
        ]]
        local hits = find_bare_print_literals(sample)
        assert.are.equal(0, #hits)
    end)

    it("catches single-quoted literals too", function()
        local sample = [[
            love.graphics.print('Bid', x, y)
        ]]
        local hits = find_bare_print_literals(sample)
        assert.are.equal(1, #hits)
    end)
end)
