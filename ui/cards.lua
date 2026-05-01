-- Placeholder card rendering helpers. Stateless — every call paints into
-- the current love.graphics context with no persisted state of its own.
-- Phase 4 will replace these with real card-skin assets; the function
-- shapes are picked so the swap is "swap the body, not the call sites".
--
-- Suit symbols are drawn as primitive shapes (polygons + circles) rather
-- than Unicode glyphs because LÖVE's default font has no glyph coverage
-- for ♠♣♦♥ — a fresh `love .` would otherwise render tofu boxes for
-- every suit. A future card-skin asset pack (Phase 4) can override this
-- with bitmap art; until then primitives keep the placeholder readable
-- without bundling a font.
--
-- Rank labels are still routed through i18n.t("card.rank.*") so a future
-- accessibility skin or non-Latin rank notation has a hook.

local i18n = require("app.i18n")
local t = i18n.t

local M = {}

-- Suit colours. Hearts and diamonds render in red, clubs and spades in
-- near-black — the convention for every standard French-suited deck.
local SUIT_COLORS = {
    hearts = { 0.78, 0.18, 0.18, 1 },
    diamonds = { 0.78, 0.18, 0.18, 1 },
    clubs = { 0.10, 0.10, 0.12, 1 },
    spades = { 0.10, 0.10, 0.12, 1 },
}

local CARD_BG = { 0.97, 0.96, 0.90, 1 }
local CARD_BORDER = { 0.10, 0.20, 0.10, 1 }
local CARD_BACK_BG = { 0.16, 0.28, 0.42, 1 }
local CARD_BACK_INNER = { 0.32, 0.48, 0.66, 1 }
local CARD_BACK_PATTERN = { 0.55, 0.70, 0.86, 1 }

-- Suit primitives ------------------------------------------------------
--
-- Each helper paints a small filled shape centred on (cx, cy) within a
-- (size x size) bounding box. Caller has already set the suit colour.

local function draw_diamond(cx, cy, size)
    local hw, hh = size * 0.5, size * 0.6
    love.graphics.polygon("fill", cx, cy - hh, cx + hw, cy, cx, cy + hh, cx - hw, cy)
end

local function draw_heart(cx, cy, size)
    local r = size * 0.28
    -- Two lobes at the top, triangle filling the bottom so the silhouette
    -- closes into a heart. The lobe radii are eyeballed; this is a
    -- placeholder, not a glyph match.
    love.graphics.circle("fill", cx - r, cy - size * 0.1, r)
    love.graphics.circle("fill", cx + r, cy - size * 0.1, r)
    love.graphics.polygon(
        "fill",
        cx - size * 0.5,
        cy - size * 0.05,
        cx + size * 0.5,
        cy - size * 0.05,
        cx,
        cy + size * 0.55
    )
end

local function draw_spade(cx, cy, size)
    -- Inverted heart with a small stem.
    local r = size * 0.28
    love.graphics.circle("fill", cx - r, cy + size * 0.1, r)
    love.graphics.circle("fill", cx + r, cy + size * 0.1, r)
    love.graphics.polygon(
        "fill",
        cx - size * 0.5,
        cy + size * 0.05,
        cx + size * 0.5,
        cy + size * 0.05,
        cx,
        cy - size * 0.55
    )
    -- Stem.
    love.graphics.polygon(
        "fill",
        cx - size * 0.18,
        cy + size * 0.6,
        cx + size * 0.18,
        cy + size * 0.6,
        cx + size * 0.05,
        cy + size * 0.4,
        cx - size * 0.05,
        cy + size * 0.4
    )
end

local function draw_club(cx, cy, size)
    local r = size * 0.26
    love.graphics.circle("fill", cx, cy - size * 0.3, r)
    love.graphics.circle("fill", cx - r * 0.85, cy + size * 0.05, r)
    love.graphics.circle("fill", cx + r * 0.85, cy + size * 0.05, r)
    -- Stem.
    love.graphics.polygon(
        "fill",
        cx - size * 0.18,
        cy + size * 0.6,
        cx + size * 0.18,
        cy + size * 0.6,
        cx + size * 0.05,
        cy + size * 0.3,
        cx - size * 0.05,
        cy + size * 0.3
    )
end

local SUIT_DRAWERS = {
    hearts = draw_heart,
    diamonds = draw_diamond,
    spades = draw_spade,
    clubs = draw_club,
}

local function suit_color(suit)
    return SUIT_COLORS[suit] or { 0.10, 0.10, 0.12, 1 }
end

-- Public: paint a suit symbol for `suit` centred at (cx, cy) at the given
-- pixel `size`. The trump indicator and any future "name a suit" UI use
-- this directly so the rendering stays consistent across surfaces.
function M.draw_suit(suit, cx, cy, size)
    local drawer = SUIT_DRAWERS[suit]
    if not drawer then
        return
    end
    love.graphics.setColor(suit_color(suit))
    drawer(cx, cy, size)
    love.graphics.setColor(1, 1, 1, 1)
end

local function inset_rect(x, y, w, h, padding)
    return x + padding, y + padding, w - padding * 2, h - padding * 2
end

-- Draw a face-up card placeholder: cream background, dark border, suit-
-- coloured rank text in the top-left and a primitive suit shape below
-- it. The card's bottom-right gets a small mirrored copy.
function M.draw_face_up(card, x, y, w, h)
    assert(card and card.suit and card.rank, "draw_face_up: card must have suit and rank")

    love.graphics.setColor(CARD_BG)
    love.graphics.rectangle("fill", x, y, w, h)

    love.graphics.setColor(CARD_BORDER)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, w, h)

    local rank_text = t("card.rank." .. card.rank)

    love.graphics.setColor(suit_color(card.suit))
    love.graphics.print(rank_text, x + 6, y + 4)

    local suit_size = math.min(w, h) * 0.22
    M.draw_suit(card.suit, x + 12, y + 32, suit_size)

    -- Bottom-right mirror — anchored to the card's right edge so it stays
    -- on-card even when the card is narrow.
    love.graphics.setColor(suit_color(card.suit))
    love.graphics.print(rank_text, x + w - 18, y + h - 36)
    M.draw_suit(card.suit, x + w - 14, y + h - 14, suit_size * 0.7)

    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw a face-down card placeholder: navy background with a paler inner
-- frame and a centre block. The inner shapes give the card a recognisable
-- silhouette in screenshots without depending on a font glyph.
function M.draw_face_down(x, y, w, h)
    love.graphics.setColor(CARD_BACK_BG)
    love.graphics.rectangle("fill", x, y, w, h)

    love.graphics.setColor(CARD_BORDER)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, w, h)

    local ix, iy, iw, ih = inset_rect(x, y, w, h, 4)
    love.graphics.setColor(CARD_BACK_INNER)
    love.graphics.rectangle("line", ix, iy, iw, ih)

    local cx, cy, cw, ch = inset_rect(x, y, w, h, math.floor(math.min(w, h) * 0.25))
    love.graphics.setColor(CARD_BACK_PATTERN)
    love.graphics.rectangle("fill", cx, cy, cw, ch)

    love.graphics.setColor(1, 1, 1, 1)
end

-- Draw a face-down stack of `count` cards at (x, y) with the given card
-- size. Up to 3 stacked offsets are drawn so the silhouette reads as a
-- pile; the topmost rectangle sits at the (x, y) origin so a hit-test
-- against the topmost card is just rect contains.
function M.draw_stack(count, x, y, w, h)
    if count <= 0 then
        return
    end
    local depth = math.min(count, 3)
    local offset = 3
    for i = depth - 1, 1, -1 do
        M.draw_face_down(x + i * offset, y - i * offset, w, h)
    end
    M.draw_face_down(x, y, w, h)
end

return M
