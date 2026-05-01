-- Layout primitives shared across UI scenes. Pure Lua — no love.* — so it
-- can be unit-tested under busted without the runtime.
--
-- Scope is intentionally narrow: helpers for Phase 2's reflowable table.
-- top_right, center_panel and the touch-target floor live here from day
-- one; table_regions joined them when the table-rendering task landed
-- and divides the table into the five rectangles the scene draws into:
-- scoreboard, opponents strip, centre band, active-player hand and the
-- top-right Menu button.

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

-- Divide the table window into the five regions the table scene draws.
--
--   ┌────────────────────────────────────────┬───────────┐
--   │              opponents strip            │           │
--   ├────────────────────────────────────────┤           │
--   │                                         │ scoreboard│
--   │             centre band                 │           │
--   │                                         │           │
--   ├────────────────────────────────────────┤           │
--   │            active-player hand           │           │
--   └────────────────────────────────────────┴───────────┘
--   menu_button is a small rect anchored to the very top-right corner,
--   above the scoreboard column.
--
-- All five rectangles use floored integer coordinates so subsequent draw
-- calls land on whole pixels regardless of the input window size.
--
-- `opts` is optional and overrides:
--   margin       — outer/inter-region gap (default M.SAFE_MARGIN)
--   scoreboard_w — fixed width of the right column
--   hand_h       — fixed height of the bottom strip
--   opponents_h  — fixed height of the top strip
--   menu_btn_w   — Menu button width
--   menu_btn_h   — Menu button height (must clear MIN_HIT_TARGET)
function M.table_regions(outer_w, outer_h, opts)
    opts = opts or {}
    local margin = opts.margin or M.SAFE_MARGIN
    local scoreboard_w = opts.scoreboard_w or 200
    local hand_h = opts.hand_h or 140
    local opponents_h = opts.opponents_h or 120
    local menu_btn_w = opts.menu_btn_w or 120
    local menu_btn_h = opts.menu_btn_h or 48

    -- Reserve a band at the top of the right column for the menu button so
    -- the scoreboard never overlaps it. The scoreboard starts below the
    -- button + a margin's worth of breathing room.
    local right_x = outer_w - scoreboard_w - margin
    local scoreboard_y = margin + menu_btn_h + margin
    local scoreboard_h = outer_h - scoreboard_y - margin
    if scoreboard_h < 0 then
        scoreboard_h = 0
    end

    local left_w = outer_w - scoreboard_w - margin * 3
    if left_w < 0 then
        left_w = 0
    end

    local opponents = {
        x = floor(margin),
        y = floor(margin),
        w = floor(left_w),
        h = floor(opponents_h),
    }
    local hand = {
        x = floor(margin),
        y = floor(outer_h - hand_h - margin),
        w = floor(left_w),
        h = floor(hand_h),
    }
    local centre_y = opponents.y + opponents.h + margin
    local centre_h = hand.y - centre_y - margin
    if centre_h < 0 then
        centre_h = 0
    end
    local centre = {
        x = floor(margin),
        y = floor(centre_y),
        w = floor(left_w),
        h = floor(centre_h),
    }
    local scoreboard = {
        x = floor(right_x),
        y = floor(scoreboard_y),
        w = floor(scoreboard_w),
        h = floor(scoreboard_h),
    }
    local menu_button = M.top_right(outer_w, outer_h, menu_btn_w, menu_btn_h, margin)

    return {
        opponents = opponents,
        centre = centre,
        hand = hand,
        scoreboard = scoreboard,
        menu_button = menu_button,
    }
end

return M
