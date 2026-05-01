-- The table scene. Renders the playable game state from a frozen-in-time
-- view-model derived from the manager's session. Input wiring lives in the
-- next Phase 2 task — today the scene only draws.
--
-- Region layout comes from `ui.layout.table_regions`. The Menu button stays
-- top-right for touch parity with the menu modal: iOS and Android have no
-- reliable Esc, so a visible back-out is mandatory. Keyboard users still
-- get Escape and Enter/Space.
--
-- Privacy: opponents (seats 2 and 3) render as face-down stacks even though
-- the engine state knows their cards. That keeps the eventual hand-off
-- privacy overlay (a separate task) additive — when it lands, the only
-- delta is that seat 1 also goes face-down until the player taps "ready".

local i18n = require("app.i18n")
local Button = require("ui.button")
local FocusGroup = require("ui.focus_group")
local layout = require("ui.layout")
local cards = require("ui.cards")
local view_model = require("app.table_view_model")
local t = i18n.t

local M = {}
M.__index = M

local MENU_BTN_W = 120
local MENU_BTN_H = 48

local CARD_GAP = 6
local OPPONENT_CARD_W = 38
local OPPONENT_CARD_H = 54
local TALON_CARD_W = 48
local TALON_CARD_H = 68

local SCOREBOARD_BG = { 0.04, 0.14, 0.08, 1 }
local SCOREBOARD_BORDER = { 0.12, 0.30, 0.18, 1 }
local CENTRE_BG = { 0.04, 0.14, 0.08, 0.55 }
-- The turn highlight is intentionally a different hue from the keyboard
-- focus outline (which is a saturated yellow in ui/button.lua). Cyan
-- reads as "this seat is the current actor" and never collides visually
-- with "this widget has keyboard focus".
local TURN_HIGHLIGHT = { 0.40, 0.80, 1.0, 1 }
local DEALER_BADGE_BG = { 0.95, 0.85, 0.30, 1 }
local DEALER_BADGE_FG = { 0.10, 0.10, 0.05, 1 }
local LABEL_COLOR = { 0.85, 0.92, 0.85, 1 }
local VALUE_COLOR = { 1, 1, 1, 1 }
local DIM_COLOR = { 0.65, 0.72, 0.65, 1 }

function M.new(manager)
    local self = setmetatable({
        _manager = manager,
        _view_model = nil,
    }, M)
    self._back_button = Button.new({
        id = "back_to_menu", -- i18n-ok
        label_key = "scene.table.back_to_menu",
        enabled = true,
        on_press = function()
            self:_return_to_menu()
        end,
    })
    self._focus = FocusGroup.new({ self._back_button })
    return self
end

function M:_return_to_menu()
    self._manager:switch_to("menu")
end

function M:_refresh_view_model()
    local session = self._manager.session and self._manager:session() or nil
    if session then
        self._view_model = view_model.from_session(session)
    else
        self._view_model = nil
    end
end

function M:enter(_prev_id, _params)
    self._back_button.hovered = false
    self._back_button.pressed = false
    -- Focus-on-Tab convention shared with menu and end-of-game: no focus
    -- ring on entry, surfaces on first Tab press.
    self._focus:clear()
    self:_refresh_view_model()
end

local function phase_label_key(phase)
    if phase == "auction" then
        return "scene.table.phase.auction"
    elseif phase == "talon" then
        return "scene.table.phase.talon"
    elseif phase == "tricks" then
        return "scene.table.phase.tricks"
    end
    return "scene.table.phase.done"
end

local function seat_label(seat)
    if seat == 1 then
        return t("scene.table.player_label.you")
    end
    return t("scene.table.player_label.other", { n = seat })
end

local function draw_dealer_badge(x, y)
    love.graphics.setColor(DEALER_BADGE_BG)
    love.graphics.rectangle("fill", x, y, 22, 22)
    love.graphics.setColor(DEALER_BADGE_FG)
    love.graphics.print(t("scene.table.dealer_badge"), x + 7, y + 4)
    love.graphics.setColor(1, 1, 1, 1)
end

local function draw_turn_ring(x, y, w, h)
    love.graphics.setColor(TURN_HIGHLIGHT)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x - 3, y - 3, w + 6, h + 6)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

local function draw_opponents(view, region)
    if not view then
        return
    end
    local opponents = {}
    for _, hand in ipairs(view.hands) do
        if hand.perspective == "other" then
            opponents[#opponents + 1] = hand
        end
    end
    if #opponents == 0 then
        return
    end

    local slot_w = math.floor(region.w / #opponents)
    for i, hand in ipairs(opponents) do
        local slot_x = region.x + (i - 1) * slot_w
        local label = seat_label(hand.player)
        if hand.is_turn then
            love.graphics.setColor(TURN_HIGHLIGHT)
        else
            love.graphics.setColor(LABEL_COLOR)
        end
        love.graphics.print(label, slot_x + 8, region.y + 4)

        if hand.is_dealer then
            draw_dealer_badge(slot_x + 100, region.y)
        end

        local stack_x = slot_x + 8
        local stack_y = region.y + 32
        cards.draw_stack(hand.count, stack_x, stack_y, OPPONENT_CARD_W, OPPONENT_CARD_H)

        if hand.is_turn then
            draw_turn_ring(stack_x, stack_y, OPPONENT_CARD_W, OPPONENT_CARD_H)
        end

        love.graphics.setColor(DIM_COLOR)
        love.graphics.print(
            t("scene.table.deck.size", { n = hand.count }),
            stack_x + OPPONENT_CARD_W + 12,
            stack_y + 18
        )

        love.graphics.setColor(1, 1, 1, 1)
    end
end

local function draw_centre(view, region)
    love.graphics.setColor(CENTRE_BG)
    love.graphics.rectangle("fill", region.x, region.y, region.w, region.h)
    love.graphics.setColor(1, 1, 1, 1)

    if not view then
        return
    end

    -- Talon block on the left of the centre band.
    local talon = view.talon
    local talon_label_x = region.x + 16
    local talon_label_y = region.y + 8
    love.graphics.setColor(LABEL_COLOR)
    love.graphics.print(t("scene.table.talon.label"), talon_label_x, talon_label_y)

    local talon_x = talon_label_x
    local talon_y = talon_label_y + 24
    if talon.count == 0 then
        love.graphics.setColor(DIM_COLOR)
        love.graphics.print(t("scene.table.bid.none"), talon_x, talon_y + 20)
    elseif talon.face_down then
        cards.draw_stack(talon.count, talon_x, talon_y, TALON_CARD_W, TALON_CARD_H)
    else
        for i = 1, talon.count do
            cards.draw_face_up(
                talon.cards[i],
                talon_x + (i - 1) * (TALON_CARD_W + CARD_GAP),
                talon_y,
                TALON_CARD_W,
                TALON_CARD_H
            )
        end
    end

    -- Bid / Turn / Trump / Phase labels on the right of the centre band.
    local info_x = region.x + math.floor(region.w * 0.55)
    local info_y = region.y + 8
    local row_h = 22

    love.graphics.setColor(LABEL_COLOR)
    love.graphics.print(t("scene.table.bid.label"), info_x, info_y)
    love.graphics.setColor(VALUE_COLOR)
    if view.current_bid then
        love.graphics.print(tostring(view.current_bid), info_x + 80, info_y)
        if view.leader then
            love.graphics.print(seat_label(view.leader), info_x + 140, info_y)
        end
    else
        love.graphics.setColor(DIM_COLOR)
        love.graphics.print(t("scene.table.bid.none"), info_x + 80, info_y)
    end

    love.graphics.setColor(LABEL_COLOR)
    love.graphics.print(t("scene.table.turn.label"), info_x, info_y + row_h)
    love.graphics.setColor(VALUE_COLOR)
    if view.turn_player then
        love.graphics.print(seat_label(view.turn_player), info_x + 80, info_y + row_h)
    else
        love.graphics.setColor(DIM_COLOR)
        love.graphics.print(t("scene.table.bid.none"), info_x + 80, info_y + row_h)
    end

    love.graphics.setColor(LABEL_COLOR)
    love.graphics.print(t("scene.table.trump.label"), info_x, info_y + row_h * 2)
    if view.trump then
        cards.draw_suit(view.trump, info_x + 88, info_y + row_h * 2 + 8, 14)
    else
        love.graphics.setColor(DIM_COLOR)
        love.graphics.print(t("scene.table.bid.none"), info_x + 80, info_y + row_h * 2)
    end

    love.graphics.setColor(LABEL_COLOR)
    love.graphics.print(t("scene.table.phase.label"), info_x, info_y + row_h * 3)
    love.graphics.setColor(VALUE_COLOR)
    love.graphics.print(t(phase_label_key(view.phase)), info_x + 80, info_y + row_h * 3)

    love.graphics.setColor(1, 1, 1, 1)
end

-- Compute the card width and height for a face-up hand of `count` cards
-- inside `region`, keeping each card at least MIN_HIT_TARGET wide so the
-- next task's hit-tests are touch-safe and respecting the region height.
local function compute_hand_card_size(region, count)
    if count <= 0 then
        return 0, 0
    end
    local available_w = region.w - 16
    local card_w = math.floor((available_w - (count - 1) * CARD_GAP) / count)
    local min_w = layout.MIN_HIT_TARGET
    if card_w < min_w then
        card_w = min_w
    end
    -- Maintain a roughly 1.4 height/width ratio without overflowing the
    -- region's height. Leave a 28-pixel band at the top of the region for
    -- the "Your hand" label.
    local label_band = 28
    local max_h = region.h - label_band - 8
    local card_h = math.min(max_h, math.floor(card_w * 1.4))
    if card_h < layout.MIN_HIT_TARGET then
        card_h = math.min(max_h, layout.MIN_HIT_TARGET)
    end
    return card_w, card_h, label_band
end

local function draw_hand(view, region)
    if not view then
        return
    end
    local self_hand
    for _, hand in ipairs(view.hands) do
        if hand.perspective == "self" then
            self_hand = hand
            break
        end
    end
    if not self_hand then
        return
    end

    if self_hand.is_turn then
        love.graphics.setColor(TURN_HIGHLIGHT)
    else
        love.graphics.setColor(LABEL_COLOR)
    end
    love.graphics.print(t("scene.table.player_label.you"), region.x + 8, region.y + 4)

    if self_hand.is_dealer then
        draw_dealer_badge(region.x + 100, region.y)
    end

    local count = self_hand.count
    if count == 0 then
        return
    end
    local card_w, card_h, label_band = compute_hand_card_size(region, count)
    local hand_y = region.y + label_band

    for i = 1, count do
        local card = self_hand.cards[i]
        local x = region.x + 8 + (i - 1) * (card_w + CARD_GAP)
        cards.draw_face_up(card, x, hand_y, card_w, card_h)
    end

    if self_hand.is_turn then
        local total_w = count * (card_w + CARD_GAP) - CARD_GAP
        draw_turn_ring(region.x + 8, hand_y, total_w, card_h)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

local function draw_scoreboard(view, region)
    love.graphics.setColor(SCOREBOARD_BG)
    love.graphics.rectangle("fill", region.x, region.y, region.w, region.h)
    love.graphics.setColor(SCOREBOARD_BORDER)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", region.x, region.y, region.w, region.h)

    love.graphics.setColor(LABEL_COLOR)
    love.graphics.print(t("scene.table.scoreboard.title"), region.x + 12, region.y + 8)

    if not view then
        love.graphics.setColor(1, 1, 1, 1)
        return
    end

    local row_y = region.y + 36
    local row_h = 32
    for _, entry in ipairs(view.scoreboard) do
        local label
        if entry.player == 1 then
            label = t("scene.table.player_label.you")
        else
            label = t("scene.table.player_label.other", { n = entry.player })
        end

        if entry.is_winner then
            love.graphics.setColor(1.0, 0.85, 0.30, 1)
        elseif entry.is_turn then
            love.graphics.setColor(TURN_HIGHLIGHT)
        else
            love.graphics.setColor(LABEL_COLOR)
        end
        love.graphics.print(label, region.x + 12, row_y)

        love.graphics.setColor(VALUE_COLOR)
        love.graphics.print(tostring(entry.total), region.x + region.w - 56, row_y)

        if entry.barrel.on_barrel then
            love.graphics.setColor(0.95, 0.75, 0.30, 1)
            local hint = t("scene.table.scoreboard.barrel", {
                n = entry.barrel.deals_remaining or 0,
            })
            love.graphics.print(hint, region.x + 12, row_y + 14)
        end

        if entry.is_dealer then
            draw_dealer_badge(region.x + region.w - 28, row_y - 4)
        end

        row_y = row_y + row_h
    end

    love.graphics.setColor(1, 1, 1, 1)
end

function M:draw(w, h)
    w = w or 800
    h = h or 600

    love.graphics.clear(0.07, 0.22, 0.12)

    self:_refresh_view_model()

    local regions = layout.table_regions(w, h, {
        menu_btn_w = MENU_BTN_W,
        menu_btn_h = MENU_BTN_H,
    })

    draw_opponents(self._view_model, regions.opponents)
    draw_centre(self._view_model, regions.centre)
    draw_hand(self._view_model, regions.hand)
    draw_scoreboard(self._view_model, regions.scoreboard)

    self._back_button:set_rect(
        regions.menu_button.x,
        regions.menu_button.y,
        regions.menu_button.w,
        regions.menu_button.h
    )
    self._back_button:draw()

    love.graphics.setColor(1, 1, 1, 1)
end

function M:mousemoved(x, y, _dx, _dy)
    self._back_button:on_mousemoved(x, y)
end

function M:mousepressed(x, y, button)
    self._back_button:on_mousepressed(x, y, button)
end

function M:mousereleased(x, y, button)
    self._back_button:on_mousereleased(x, y, button)
end

local function shift_held()
    if not (love.keyboard and love.keyboard.isDown) then
        return false
    end
    return love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") -- i18n-ok
end

function M:keypressed(key)
    if key == "escape" then -- i18n-ok
        self:_return_to_menu()
    elseif key == "tab" then -- i18n-ok
        self._focus:advance(shift_held() and -1 or 1)
    elseif key == "down" or key == "right" then -- i18n-ok
        self._focus:advance(1)
    elseif key == "up" or key == "left" then -- i18n-ok
        self._focus:advance(-1)
    elseif key == "return" or key == "space" or key == "kpenter" then -- i18n-ok
        -- Single-button scene: Enter activates regardless of focus state
        -- so a keyboard user doesn't have to Tab first.
        self._back_button:activate()
    end
end

return M
