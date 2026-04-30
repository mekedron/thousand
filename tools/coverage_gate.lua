#!/usr/bin/env lua
-- Coverage gate for the Thousand engine.
--
-- Reads `luacov.report.out` (produced by `luacov` after `busted
-- --coverage`), computes weighted line coverage across `core/*.lua`,
-- and exits non-zero when the total is below the threshold or when
-- any `core/*.lua` file on disk has no row in the report.
--
-- Weighting: total = Σ(hits) / Σ(hits + missed), NOT the arithmetic
-- mean of file percentages. Otherwise a 1-line file at 100% would
-- mask a 1000-line file at 0%.
--
-- Usage:
--   lua tools/coverage_gate.lua [report-file] [threshold]
-- Defaults: luacov.report.out, 80.

local report_file = arg[1] or "luacov.report.out"
local threshold = tonumber(arg[2]) or 80

local function fail(message)
    io.stderr:write("coverage_gate: " .. message .. "\n")
    os.exit(1)
end

local function read_file(path)
    local fh, err = io.open(path, "r")
    if not fh then
        fail(
            "could not open report '"
                .. path
                .. "' ("
                .. tostring(err)
                .. ")."
                .. " Run `make coverage` to produce it."
        )
    end
    local body = fh:read("*all")
    fh:close()
    return body
end

local function list_core_files()
    local handle = io.popen("ls core/*.lua 2>/dev/null")
    if not handle then
        fail("could not list core/*.lua files")
    end
    local seen = {}
    for line in handle:lines() do
        seen[line] = true
    end
    handle:close()
    return seen
end

-- Parse rows of the form `core/foo.lua  HITS  MISSED  PCT%`. Empty
-- and separator lines are ignored. Returns a list of row tables and
-- a set keyed by path.
local function parse_core_rows(report)
    local rows = {}
    local seen = {}
    for line in report:gmatch("[^\n]+") do
        local path, hits, missed = line:match("^(core/[%w_/%-%.]+%.lua)%s+(%d+)%s+(%d+)%s+")
        if path then
            local row = { path = path, hits = tonumber(hits), missed = tonumber(missed) }
            rows[#rows + 1] = row
            seen[path] = row
        end
    end
    return rows, seen
end

local report = read_file(report_file)
local rows, seen = parse_core_rows(report)

if #rows == 0 then
    fail(
        "no core/*.lua rows found in "
            .. report_file
            .. ". Did luacov run? Did `.luacov` include core/?"
    )
end

local on_disk = list_core_files()
local missing_from_report = {}
for path in pairs(on_disk) do
    if not seen[path] then
        missing_from_report[#missing_from_report + 1] = path
    end
end
if #missing_from_report > 0 then
    table.sort(missing_from_report)
    fail(
        "the following core/*.lua files are not exercised by any test "
            .. "(no row in "
            .. report_file
            .. "): "
            .. table.concat(missing_from_report, ", ")
    )
end

local total_hits = 0
local total_missed = 0
for _, row in ipairs(rows) do
    total_hits = total_hits + row.hits
    total_missed = total_missed + row.missed
end

local executable = total_hits + total_missed
if executable == 0 then
    fail("core/ has zero executable lines tracked — nothing to gate")
end

local pct = (total_hits / executable) * 100
local label = string.format("%.2f%%", pct)
local threshold_label = string.format("%.2f%%", threshold)

if pct + 1e-9 < threshold then
    io.stderr:write(
        string.format(
            "FAIL: core coverage is %s, below threshold %s.\n"
                .. "      hits=%d  missed=%d  files=%d\n",
            label,
            threshold_label,
            total_hits,
            total_missed,
            #rows
        )
    )
    os.exit(1)
end

io.write(
    string.format(
        "PASS: core coverage is %s (threshold %s, hits=%d missed=%d files=%d).\n",
        label,
        threshold_label,
        total_hits,
        total_missed,
        #rows
    )
)
os.exit(0)
