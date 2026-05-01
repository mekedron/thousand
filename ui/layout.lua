-- Layout primitives shared across UI scenes. Pure Lua — no love.* — so it
-- can be unit-tested under busted without the runtime.
--
-- Scope is intentionally narrow: only the helpers Phase 2's first reflowable
-- table needs. The richer table_regions(w, h) helper (scoreboard / hand /
-- talon / opponents / prompt rectangles) lands with the next task, when its
-- consumers exist.

local M = {}

-- Minimum hit-target for any clickable surface. The iOS HIG calls for 44 pt;
-- conf.lua sets t.window.usedpiscale = true so logical coordinates are
-- already DPI-scaled. 44 logical px equals 44 pt at 1x and 44 pt at 2x
-- retina — do NOT "fix" this to 88 on retina hardware.
M.MIN_HIT_TARGET = 44

-- Default outer margin for screen-edge controls, picked to clear iPhone
-- safe-area insets when running on iOS.
M.SAFE_MARGIN = 16

local function floor(n)
    return math.floor(n)
end

-- Place a rectangle of (btn_w, btn_h) flush against the top-right of an
-- (outer_w, outer_h) area, leaving `margin` pixels of breathing room.
-- outer_h is part of the signature for symmetry with center_panel and
-- so future variants (e.g. bottom_right) can take the same shape; the
-- top-right anchor itself only needs the width.
function M.top_right(outer_w, _outer_h, btn_w, btn_h, margin)
    margin = margin or M.SAFE_MARGIN
    return {
        x = outer_w - btn_w - margin,
        y = margin,
        w = btn_w,
        h = btn_h,
    }
end

-- Place a panel of (panel_w, panel_h) at the centre of (outer_w, outer_h).
-- Coordinates are floored so subsequent draw calls land on whole pixels.
function M.center_panel(outer_w, outer_h, panel_w, panel_h)
    return {
        x = floor(outer_w * 0.5 - panel_w * 0.5),
        y = floor(outer_h * 0.5 - panel_h * 0.5),
        w = panel_w,
        h = panel_h,
    }
end

-- True iff (w, h) clears the touch-target minimum on both axes.
function M.is_touch_target_ok(w, h)
    return w >= M.MIN_HIT_TARGET and h >= M.MIN_HIT_TARGET
end

return M
