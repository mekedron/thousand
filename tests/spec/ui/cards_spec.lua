-- Unit coverage for the card rendering helpers. Drives them against the
-- pure-Lua love-mock so we can assert the recorded ops without needing a
-- Love2D runtime.

local love_mock = require("tests.e2e.support.love_mock")

local function with_mock(fn)
    local i18n = require("app.i18n")
    i18n._reset()
    i18n._set_logger(function() end)
    i18n.set_locale("en")
    local mock = love_mock.new({ width = 800, height = 600 })
    mock:install()
    -- Force re-require of cards so it binds to the freshly installed love.
    package.loaded["ui.cards"] = nil
    local cards = require("ui.cards")
    local ok, err = pcall(fn, cards, mock)
    mock:restore()
    if not ok then
        error(err)
    end
end

local function rectangles(mock)
    local out = {}
    for _, op in ipairs(mock.graphics.recording()) do
        if op.op == "rectangle" then
            out[#out + 1] = op
        end
    end
    return out
end

local function texts(mock)
    local out = {}
    for _, op in ipairs(mock.graphics.recording()) do
        if op.op == "text" then
            out[#out + 1] = op
        end
    end
    return out
end

local function find_unstubbed(mock, name)
    -- Mock records primitive draws (polygon, circle) via the unstubbed
    -- fallback because the love-mock stubs only the calls Phase 0/1 used.
    -- Returns the first matching op or nil.
    for _, op in ipairs(mock.graphics.recording()) do
        if op.op == "unstubbed" and op.api == "graphics." .. name then
            return op
        end
    end
    return nil
end

describe("ui.cards", function()
    describe("draw_face_up", function()
        it("draws a card-shape rectangle and the rank text", function()
            with_mock(function(cards, mock)
                cards.draw_face_up({ suit = "hearts", rank = "A" }, 100, 50, 60, 90)
                local rects = rectangles(mock)
                local fills = 0
                for _, r in ipairs(rects) do
                    if r.mode == "fill" and r.w == 60 and r.h == 90 then
                        fills = fills + 1
                    end
                end
                assert.is_true(fills >= 1, "at least one card-shape fill rectangle")

                local found_rank = false
                for _, t in ipairs(texts(mock)) do
                    if t.text == "A" then
                        found_rank = true
                        break
                    end
                end
                assert.is_true(found_rank, "rank text drawn")
            end)
        end)

        it("draws a hearts suit primitive (red colour, polygon + circles)", function()
            with_mock(function(cards, mock)
                cards.draw_face_up({ suit = "hearts", rank = "A" }, 0, 0, 60, 90)
                -- LÖVE's default font has no glyph coverage for ♥, so the
                -- card renderer paints the suit symbol from primitives.
                -- Both circle (lobes) and polygon (triangle) calls land
                -- through the love-mock's unstubbed recorder.
                assert.is_not_nil(find_unstubbed(mock, "circle"), "circle for hearts lobes")
                assert.is_not_nil(find_unstubbed(mock, "polygon"), "polygon for hearts body")
            end)
        end)

        it("paints the diamond suit colour for diamond cards", function()
            with_mock(function(cards, mock)
                cards.draw_face_up({ suit = "diamonds", rank = "K" }, 0, 0, 50, 70)
                local saw_red = false
                for _, op in ipairs(mock.graphics.recording()) do
                    if op.op == "setColor" then
                        local c = op.color
                        if c[1] > 0.6 and c[2] < 0.3 and c[3] < 0.3 then
                            saw_red = true
                            break
                        end
                    end
                end
                assert.is_true(saw_red, "red set for diamonds suit")
            end)
        end)
    end)

    describe("draw_face_down", function()
        it("draws no text and at least one card-shape rectangle", function()
            with_mock(function(cards, mock)
                cards.draw_face_down(0, 0, 60, 90)
                assert.are.equal(0, #texts(mock))
                local rects = rectangles(mock)
                assert.is_true(#rects >= 1)
            end)
        end)
    end)

    describe("draw_stack", function()
        it("draws nothing when count is zero", function()
            with_mock(function(cards, mock)
                cards.draw_stack(0, 0, 0, 60, 90)
                assert.are.equal(0, #rectangles(mock))
            end)
        end)

        it("caps the visible depth at three offsets even when count is large", function()
            with_mock(function(cards, mock)
                cards.draw_stack(8, 0, 0, 60, 90)
                local fills = 0
                for _, r in ipairs(rectangles(mock)) do
                    if r.mode == "fill" and r.w == 60 and r.h == 90 then
                        fills = fills + 1
                    end
                end
                -- Each face-down draws a fill + an inner pattern fill.
                -- Three offsets means at most 3 face-downs, i.e. <= 6 fills.
                assert.is_true(fills <= 6, "depth-capped at 3 face-downs (got " .. fills .. ")")
                assert.is_true(fills >= 2, "at least two fills (top of stack)")
            end)
        end)
    end)
end)
