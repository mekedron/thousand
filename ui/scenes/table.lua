-- The table scene. Renders the playable game state from a frozen-in-time
-- view-model derived from the manager's session AND wires every input
-- back into Session mutators so a hot-seat game can drive the engine
-- end-to-end. The scene never owns engine vocabulary — every input goes
-- through the session and every render reads from the view-model.
--
-- Region layout comes from `ui.layout.table_regions`. Per-mode panels
-- (bid buttons, take-talon, pass-to-opponent, raise/skip, deal-done's
-- next-deal button) are added below the centre band. The Menu button
-- stays top-right for touch parity with the menu modal: iOS and Android
-- have no reliable Esc, so a visible back-out is mandatory. Keyboard
-- users still get Escape and Enter/Space.
--
-- Mode dispatch. The view-model's `phase` (auction / talon / tricks /
-- deal_done / done) plus the `talon_phase.status` field decide which
-- panel renders this frame. Each mode owns its own button list which
-- is stitched together with the always-visible back button into a
-- single FocusGroup so keyboard navigation works across all controls.
--
-- Marriage flow. In tricks mode a tap on a K/Q of an available marriage
-- suit opens a modal asking whether to declare. Declare runs
-- session:declare_marriage then session:play; Just play runs only
-- session:play; Esc cancels and the player is back at hand selection.
-- The trump-flip-from-next-trick timing rule lives in app/session.lua.
--
-- Privacy: opponents render as face-down stacks even though the engine
-- state knows their cards. The privacy hand-off task layers a
-- between-turns overlay on top of this — when it lands, the only delta
-- is that the active seat also goes face-down until the player taps
-- "ready". Today the active seat is whichever hand has perspective ==
-- "self" in the view-model.

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
local TURN_HIGHLIGHT = { 0.40, 0.80, 1.0, 1 }
local DEALER_BADGE_BG = { 0.95, 0.85, 0.30, 1 }
local DEALER_BADGE_FG = { 0.10, 0.10, 0.05, 1 }
local LABEL_COLOR = { 0.85, 0.92, 0.85, 1 }
local VALUE_COLOR = { 1, 1, 1, 1 }
local DIM_COLOR = { 0.65, 0.72, 0.65, 1 }
local TOAST_BG = { 0.30, 0.06, 0.06, 0.92 }
local TOAST_FG = { 1.0, 0.92, 0.85, 1 }
local MODAL_BG = { 0.12, 0.18, 0.14, 1 }
local MODAL_DIM = { 0, 0, 0, 0.6 }
local FOCUS_OUTLINE = { 0.95, 0.95, 0.55, 1 }
local ILLEGAL_DIM = { 0, 0, 0, 0.55 }

-- Visual lift applied to whichever card is hovered or keyboard-focused.
-- Pure rendering offset — the hit-rect stays put so the cursor doesn't
-- have to track the card upward.
local CARD_HOVER_LIFT = 12
-- Half-gap forgiveness applied to the click rect on each side so the
-- 6-pixel gap between cards never lands a click in dead space.
local CARD_HIT_PAD_X = 3

local PANEL_BTN_W = 112
local PANEL_BTN_H = 48
local PANEL_BTN_GAP = 8
local PANEL_LABEL_BAND = 22

local TOAST_TTL = 2.0

-- Construction ---------------------------------------------------------

function M.new(manager)
    local self = setmetatable({
        _manager = manager,
        _view_model = nil,
        _panel_buttons = {},
        _panel_signature = nil,
        _modal_buttons = {},
        _modal = nil, -- nil | "marriage"
        _marriage_payload = nil,
        _toast = nil,
        _hand_card_rects = {},
        _opponent_seat_rects = {},
        _last_regions = nil,
        _hovered_card_index = nil,
        -- Unified keyboard focus index. When the player's hand is
        -- interactive (tricks phase or talon awaiting_pass) the focus
        -- ring covers cards first, then panel buttons, then the back
        -- button — Tab/arrow keys cycle through every clickable
        -- target, Enter activates whichever is focused.
        _focus_index = nil,
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

function M:_session()
    return self._manager.session and self._manager:session() or nil
end

function M:_refresh_view_model()
    local session = self:_session()
    if session then
        self._view_model = view_model.from_session(session)
    else
        self._view_model = nil
    end
end

function M:enter(_prev_id, _params)
    self._back_button.hovered = false
    self._back_button.pressed = false
    self._modal = nil
    self._marriage_payload = nil
    self._toast = nil
    self._panel_buttons = {}
    self._panel_signature = nil
    self._modal_buttons = {}
    self._hand_card_rects = {}
    self._opponent_seat_rects = {}
    self._focus = FocusGroup.new({ self._back_button })
    self._hovered_card_index = nil
    self._focus_index = nil
    self:_refresh_view_model()
end

-- Focus model -----------------------------------------------------------
--
-- Keyboard focus walks a single ordered list:
--   1..card_count                 — cards in the active hand (when
--                                   the hand is interactive)
--   card_count+1..+panel_count    — panel buttons (bid amounts, take,
--                                   raise, skip, next-deal, …)
--   last                          — the back-to-menu button
--
-- self._focus_index addresses this list. nil means no focus visible
-- (the focus-visible idiom — focus only surfaces after the user navs
-- in; clicks don't show the ring).

function M:_hand_is_interactive(view)
    view = view or self._view_model
    if not view then
        return false
    end
    if view.phase == "tricks" then
        return view.turn_player ~= nil
            and view.hands[view.turn_player]
            and view.hands[view.turn_player].perspective == "self"
    end
    if view.phase == "talon" and view.talon_phase then
        return view.talon_phase.status == "awaiting_pass"
    end
    return false
end

function M:_focus_card_count()
    if not self:_hand_is_interactive() then
        return 0
    end
    local view = self._view_model
    if not view or not view.turn_player then
        return 0
    end
    local hand = view.hands[view.turn_player]
    return hand and hand.count or 0
end

function M:_focusable_count()
    return self:_focus_card_count() + #self._panel_buttons + 1
end

-- Map _focus_index → "card" | "panel" | "back". Returns nil when no
-- focus is visible. Side-effect: clamps a stale index that was left
-- behind by a card play or turn rotation that shrank the focusable
-- list.
function M:_focus_target()
    local idx = self._focus_index
    if not idx then
        return nil
    end
    local total = self:_focusable_count()
    if total == 0 or idx < 1 or idx > total then
        self._focus_index = nil
        return nil
    end
    local card_count = self:_focus_card_count()
    if idx <= card_count then
        return "card" -- i18n-ok
    end
    if idx <= card_count + #self._panel_buttons then
        return "panel" -- i18n-ok
    end
    return "back" -- i18n-ok
end

function M:_focused_panel_button()
    if self:_focus_target() ~= "panel" then
        return nil
    end
    local card_count = self:_focus_card_count()
    return self._panel_buttons[self._focus_index - card_count]
end

function M:_advance_focus(direction)
    local total = self:_focusable_count()
    if total == 0 then
        return
    end
    local cur = self._focus_index
    if not cur then
        cur = direction > 0 and 0 or total + 1
    end
    cur = ((cur - 1 + direction) % total) + 1
    self._focus_index = cur
end

-- Cycle keyboard focus within the current group (cards-only OR
-- panel-buttons-and-back-only). Bound to Left/Right so the player can
-- walk their hand left↔right without overshooting into the bid panel.
-- When no focus is set yet, seed it on the first element of whichever
-- group the hand state suggests (interactive hand → cards; otherwise
-- panel buttons + back).
function M:_advance_within_group(direction)
    local card_count = self:_focus_card_count()
    local panel_count = #self._panel_buttons + 1 -- +1 for back button
    local target = self:_focus_target()

    if target == "card" or (target == nil and card_count > 0) then
        if card_count == 0 then
            return
        end
        local cur = self._focus_index or (direction > 0 and 0 or card_count + 1)
        cur = ((cur - 1 + direction) % card_count) + 1
        self._focus_index = cur
        return
    end

    if panel_count == 0 then
        return
    end
    local rel
    local in_panel_group = target == "panel" or target == "back" -- i18n-ok
    if in_panel_group then
        rel = self._focus_index - card_count
    else
        rel = direction > 0 and 0 or panel_count + 1
    end
    rel = ((rel - 1 + direction) % panel_count) + 1
    self._focus_index = card_count + rel
end

-- Up/Down jumps focus between the hand-card group and the panel group.
-- A pure focus-cycling Tab still cycles through everything.
function M:_jump_focus_groups()
    local target = self:_focus_target()
    local card_count = self:_focus_card_count()
    local on_card = target == "card" -- i18n-ok
    local on_panel = target == "panel" or target == "back" -- i18n-ok
    if on_card then
        if #self._panel_buttons + 1 > 0 then
            self._focus_index = card_count + 1
        end
        return
    end
    if on_panel then
        if card_count > 0 then
            self._focus_index = 1
        end
        return
    end
    if card_count > 0 then
        self._focus_index = 1
    elseif #self._panel_buttons + 1 > 0 then
        self._focus_index = 1
    end
end

-- Seed focus on the first card when the hand becomes interactive and
-- no focus is currently visible. The discoverability win matters more
-- than strict focus-visible — players need to see "this card is what
-- I'd play right now" to understand left/right are wired.
function M:_seed_focus_if_idle()
    if self._focus_index then
        return
    end
    if self:_hand_is_interactive() and self:_focus_card_count() > 0 then
        self._focus_index = 1
    end
end

function M:_activate_focus()
    local target = self:_focus_target()
    if target == "card" then
        local entry = self._hand_card_rects[self._focus_index]
        if entry then
            self:_handle_card_tap(self._view_model, entry)
        end
    elseif target == "panel" then
        local b = self:_focused_panel_button()
        if b then
            b:activate()
        end
    elseif target == "back" then
        self._back_button:activate()
    end
end

function M:_apply_button_focus_marks()
    local panel_focus = self:_focused_panel_button()
    for _, b in ipairs(self._panel_buttons) do
        b.focused = (b == panel_focus)
    end
    self._back_button.focused = (self:_focus_target() == "back")
end

-- Input → session boundary ---------------------------------------------

local function err_to_toast_key(err)
    if not err then
        return "scene.table.toast.illegal_play", { reason = "" } -- i18n-ok
    end
    local code = err.code
    if code == "not_your_turn" then
        return "scene.table.toast.not_your_turn", {}
    end
    return "scene.table.toast.illegal_play", { reason = err.message or err.code or "" } -- i18n-ok
end

function M:_show_toast(key, params)
    self._toast = {
        key = key,
        params = params,
        remaining = TOAST_TTL,
    }
end

function M:_invoke(result)
    if result.ok then
        return true
    end
    local key, params = err_to_toast_key(result.error)
    self:_show_toast(key, params)
    return false
end

function M:_do_bid(player, amount)
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:bid(player, amount))
    self:_refresh_view_model()
end

function M:_do_pass(player)
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:pass(player))
    self:_refresh_view_model()
end

function M:_do_take_talon()
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:take_talon())
    self:_refresh_view_model()
end

function M:_do_pass_talon(target, card)
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:pass_talon(target, card))
    self:_refresh_view_model()
end

function M:_do_raise(amount)
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:raise(amount))
    self:_refresh_view_model()
end

function M:_do_skip_raise()
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:skip_raise())
    self:_refresh_view_model()
end

function M:_do_play(player, card)
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:play(player, card))
    self:_refresh_view_model()
end

function M:_do_declare_then_play(player, suit, card)
    local session = self:_session()
    if not session then
        return
    end
    if not self:_invoke(session:declare_marriage(player, suit)) then
        return
    end
    self:_invoke(session:play(player, card))
    self:_refresh_view_model()
end

function M:_do_start_next_deal()
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:start_next_deal())
    self:_refresh_view_model()
end

-- Modal: marriage prompt -----------------------------------------------

function M:_open_marriage_modal(player, suit, card)
    self._modal = "marriage" -- i18n-ok
    self._marriage_payload = { player = player, suit = suit, card = card }
    local declare = Button.new({
        id = "marriage_yes", -- i18n-ok
        label_key = "scene.table.marriage.yes",
        enabled = true,
        on_press = function()
            self:_do_declare_then_play(player, suit, card)
            self:_close_marriage_modal()
        end,
    })
    local just_play = Button.new({
        id = "marriage_no", -- i18n-ok
        label_key = "scene.table.marriage.no",
        enabled = true,
        on_press = function()
            self:_do_play(player, card)
            self:_close_marriage_modal()
        end,
    })
    self._modal_buttons = { declare, just_play }
    self._modal_focus = FocusGroup.new(self._modal_buttons)
    -- Default focus on Declare so an inadvertent Enter declares (the
    -- user explicitly tapped a K/Q of a marriage suit; declaring is
    -- the high-information branch).
    self._modal_focus:focus(declare)
end

function M:_close_marriage_modal()
    self._modal = nil
    self._marriage_payload = nil
    self._modal_buttons = {}
    self._modal_focus = nil
end

-- Per-frame panel building --------------------------------------------

local function build_auction_panel(self, view)
    local on_turn = view.auction.on_turn
    local panel = {}
    for _, amount in ipairs(view.auction.allowed_bid_amounts) do
        panel[#panel + 1] = Button.new({
            id = "bid_" .. amount, -- i18n-ok
            label_key = "scene.table.auction.bid_button",
            label_params = { amount = amount },
            enabled = true,
            on_press = function()
                self:_do_bid(on_turn, amount)
            end,
        })
    end
    if view.auction.can_pass then
        panel[#panel + 1] = Button.new({
            id = "auction_pass", -- i18n-ok
            label_key = "scene.table.auction.pass_button",
            enabled = true,
            on_press = function()
                self:_do_pass(on_turn)
            end,
        })
    end
    return panel
end

local function build_talon_take_panel(self)
    return {
        Button.new({
            id = "talon_take", -- i18n-ok
            label_key = "scene.table.talon.take_button",
            enabled = true,
            on_press = function()
                self:_do_take_talon()
            end,
        }),
    }
end

local function build_talon_raise_panel(self, view)
    local panel = {}
    for _, amount in ipairs(view.talon_phase.allowed_raise_amounts or {}) do
        panel[#panel + 1] = Button.new({
            id = "talon_raise_" .. amount, -- i18n-ok
            label_key = "scene.table.talon.raise_button",
            label_params = { amount = amount },
            enabled = true,
            on_press = function()
                self:_do_raise(amount)
            end,
        })
        if #panel >= 4 then -- cap the raise panel so it fits the layout
            break
        end
    end
    panel[#panel + 1] = Button.new({
        id = "talon_skip_raise", -- i18n-ok
        label_key = "scene.table.talon.skip_raise_button",
        label_params = { amount = view.current_bid },
        enabled = true,
        on_press = function()
            self:_do_skip_raise()
        end,
    })
    return panel
end

local function build_deal_done_panel(self)
    return {
        Button.new({
            id = "deal_done_next", -- i18n-ok
            label_key = "scene.table.deal_done.next_deal",
            enabled = true,
            on_press = function()
                self:_do_start_next_deal()
            end,
        }),
    }
end

-- A short signature for the current panel's contents — phase + relevant
-- view-model fields. When this signature stays the same across frames
-- the existing button instances are preserved, which means a press on
-- frame N can be released on frame N+1 (the buttons are the same
-- objects), the keyboard focus group survives Tab navigation, and the
-- mouse-hover state isn't reset each frame.
local function panel_signature(view)
    if not view then
        return "nil"
    end
    local phase = view.phase
    -- i18n-ok: all string literals below are internal signature tokens, never rendered.
    if phase == "auction" and view.auction then
        local parts = { "auction", tostring(view.auction.on_turn) }
        for _, amount in ipairs(view.auction.allowed_bid_amounts) do
            parts[#parts + 1] = tostring(amount)
        end
        parts[#parts + 1] = view.auction.can_pass and "P" or "-" -- i18n-ok
        return table.concat(parts, ":")
    end
    if phase == "talon" and view.talon_phase then
        local status = view.talon_phase.status
        if status == "awaiting_raise" then
            local parts = { "talon", "raise", tostring(view.current_bid) } -- i18n-ok
            for _, amount in ipairs(view.talon_phase.allowed_raise_amounts or {}) do
                parts[#parts + 1] = tostring(amount)
            end
            return table.concat(parts, ":")
        end
        return "talon:" .. status
    end
    if phase == "tricks" then
        return "tricks"
    end
    if phase == "deal_done" then
        return "deal_done"
    end
    return phase or "unknown"
end

function M:_rebuild_panel_if_needed(view)
    local sig = panel_signature(view)
    if sig == self._panel_signature then
        return
    end
    self._panel_signature = sig
    self._panel_buttons = {}
    if not view then
        return
    end
    local phase = view.phase
    if phase == "auction" and view.auction then
        self._panel_buttons = build_auction_panel(self, view)
    elseif phase == "talon" and view.talon_phase then
        local status = view.talon_phase.status
        if status == "revealed" then
            self._panel_buttons = build_talon_take_panel(self)
        elseif status == "awaiting_pass" then
            -- Card hit-tests cover the pass action; no panel button.
            self._panel_buttons = {}
        elseif status == "awaiting_raise" then
            self._panel_buttons = build_talon_raise_panel(self, view)
        end
    elseif phase == "tricks" then
        self._panel_buttons = {}
    elseif phase == "deal_done" then
        self._panel_buttons = build_deal_done_panel(self)
    end
    -- Drop focus when the panel changes — focus-visible idiom: focus
    -- only surfaces after the user navigates into the new layout.
    self._focus = FocusGroup.new(self:_concat_focus_buttons())
    self._focus_index = nil
end

-- Render helpers --------------------------------------------------------

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
    return t("scene.table.player_label.other", { n = seat })
end

local function active_seat_label()
    return t("scene.table.player_label.you")
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

local function draw_opponents(self, view, region)
    self._opponent_seat_rects = {}
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

    local rects = layout.opponent_seat_rects(region, #opponents)
    for i, hand in ipairs(opponents) do
        local rect = rects[i]
        self._opponent_seat_rects[#self._opponent_seat_rects + 1] = {
            seat = hand.player,
            rect = rect,
        }
        local label = seat_label(hand.player)
        if hand.is_turn then
            love.graphics.setColor(TURN_HIGHLIGHT)
        else
            love.graphics.setColor(LABEL_COLOR)
        end
        love.graphics.print(label, rect.x + 8, rect.y + 4)

        if hand.is_dealer then
            draw_dealer_badge(rect.x + 100, rect.y)
        end

        local stack_x = rect.x + 8
        local stack_y = rect.y + 32
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

local function draw_centre(_self, view, region)
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
        if view.hands[view.turn_player] and view.hands[view.turn_player].perspective == "self" then
            love.graphics.print(active_seat_label(), info_x + 80, info_y + row_h)
        else
            love.graphics.print(seat_label(view.turn_player), info_x + 80, info_y + row_h)
        end
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

    -- Current trick plays — drawn under the centre labels in the tricks
    -- phase so the player can see who has played what this round.
    if view.current_trick and #view.current_trick.plays > 0 then
        local trick_y = info_y + row_h * 4 + 6
        love.graphics.setColor(LABEL_COLOR)
        love.graphics.print(t("scene.table.tricks.led"), info_x, trick_y)
        if view.current_trick.lead_suit then
            -- LÖVE's default font has no glyph for ♠♣♦♥; render the
            -- led suit as a primitive shape, same as the Trump
            -- indicator above, so it shows up on a fresh `love .` run
            -- without bundling a Unicode font.
            cards.draw_suit(view.current_trick.lead_suit, info_x + 48, trick_y + 8, 14)
        end
        for i, play in ipairs(view.current_trick.plays) do
            cards.draw_face_up(
                play.card,
                info_x + (i - 1) * (TALON_CARD_W + CARD_GAP),
                trick_y + 22,
                TALON_CARD_W,
                TALON_CARD_H
            )
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

local function draw_hand(self, view, region)
    self._hand_card_rects = {}
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
    love.graphics.print(active_seat_label(), region.x + 8, region.y + 4)

    if self_hand.is_dealer then
        draw_dealer_badge(region.x + 100, region.y)
    end

    local count = self_hand.count
    if count == 0 then
        return
    end
    local card_rects = layout.hand_card_rects(region, count)
    local interactive = self:_hand_is_interactive(view)
    local card_focus_active = interactive and self:_focus_target() == "card"
    local focused_card_index = card_focus_active and self._focus_index or nil

    if self_hand.is_turn and #card_rects > 0 then
        local first = card_rects[1]
        local last = card_rects[#card_rects]
        local total_w = (last.x + last.w) - first.x
        draw_turn_ring(first.x, first.y, total_w, first.h)
    end

    -- Draw cards from outside-in so the lifted (hovered or focused)
    -- card stays on top regardless of array order.
    local lifted_index = self._hovered_card_index or focused_card_index
    for i = 1, count do
        if i ~= lifted_index then
            local card = self_hand.cards[i]
            local r = card_rects[i]
            local legality = self_hand.card_legality and self_hand.card_legality[i]
            cards.draw_face_up(card, r.x, r.y, r.w, r.h)
            -- Hit-rect is wider than the visible card so half-gap clicks
            -- still register on whichever card the cursor is closer to.
            local hit_rect = {
                x = r.x - CARD_HIT_PAD_X,
                y = r.y,
                w = r.w + CARD_HIT_PAD_X * 2,
                h = r.h,
            }
            self._hand_card_rects[i] = {
                card = card,
                rect = r,
                hit = hit_rect,
                owner = self_hand.player,
                legal = (legality ~= false),
            }
            -- Dim cards the engine would currently reject (legality
            -- affordance: the next-task work will refine the visuals,
            -- but the dim state already tells the player which cards
            -- are pickable).
            if interactive and legality == false then
                love.graphics.setColor(ILLEGAL_DIM)
                love.graphics.rectangle("fill", r.x, r.y, r.w, r.h)
                love.graphics.setColor(1, 1, 1, 1)
            end
        end
    end

    if lifted_index then
        local card = self_hand.cards[lifted_index]
        local r = card_rects[lifted_index]
        if r and card then
            local lifted_y = r.y - CARD_HOVER_LIFT
            cards.draw_face_up(card, r.x, lifted_y, r.w, r.h)
            local hit_rect = {
                x = r.x - CARD_HIT_PAD_X,
                y = r.y,
                w = r.w + CARD_HIT_PAD_X * 2,
                h = r.h,
            }
            local legality = self_hand.card_legality and self_hand.card_legality[lifted_index]
            self._hand_card_rects[lifted_index] = {
                card = card,
                rect = r,
                hit = hit_rect,
                owner = self_hand.player,
                legal = (legality ~= false),
            }
            if interactive and legality == false then
                love.graphics.setColor(ILLEGAL_DIM)
                love.graphics.rectangle("fill", r.x, lifted_y, r.w, r.h)
                love.graphics.setColor(1, 1, 1, 1)
            end
            if lifted_index == focused_card_index then
                love.graphics.setColor(FOCUS_OUTLINE)
                love.graphics.setLineWidth(3)
                love.graphics.rectangle("line", r.x - 2, lifted_y - 2, r.w + 4, r.h + 4)
                love.graphics.setLineWidth(1)
                love.graphics.setColor(1, 1, 1, 1)
            end
        end
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
        if entry.player == view.turn_player and view.hands[entry.player].perspective == "self" then
            label = active_seat_label()
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

local function lay_out_panel_buttons(self, regions)
    local count = #self._panel_buttons
    if count == 0 then
        return
    end
    local total_w = count * PANEL_BTN_W + (count - 1) * PANEL_BTN_GAP
    local centre = regions.centre
    local start_x = centre.x + math.max(8, math.floor((centre.w - total_w) * 0.5))
    local y = centre.y + centre.h - PANEL_BTN_H - 8
    for i, b in ipairs(self._panel_buttons) do
        b:set_rect(start_x + (i - 1) * (PANEL_BTN_W + PANEL_BTN_GAP), y, PANEL_BTN_W, PANEL_BTN_H)
    end
end

local function draw_panel_label(view, region)
    if not view then
        return
    end
    local key
    if view.phase == "auction" then
        key = "scene.table.auction.your_turn"
    elseif view.phase == "tricks" then
        key = "scene.table.tricks.your_turn"
    elseif view.phase == "talon" and view.talon_phase then
        if view.talon_phase.status == "awaiting_pass" then
            return -- the talon-pass label is drawn over the active hand below.
        end
    end
    if key then
        love.graphics.setColor(LABEL_COLOR)
        local label_y = region.y + region.h - PANEL_BTN_H - PANEL_LABEL_BAND - 8
        love.graphics.print(t(key), region.x + 16, label_y)
        love.graphics.setColor(1, 1, 1, 1)
    end
end

local function draw_panel_buttons(self)
    for _, b in ipairs(self._panel_buttons) do
        b:draw()
    end
end

local function draw_pass_target_label(view, regions)
    if not view or not view.talon_phase or view.talon_phase.status ~= "awaiting_pass" then
        return
    end
    local target = view.talon_phase.pass_target_seat
    if not target then
        return
    end
    love.graphics.setColor(LABEL_COLOR)
    love.graphics.print(
        t("scene.table.talon.pass_to", { n = target }),
        regions.hand.x + 8,
        regions.hand.y - 22
    )
    love.graphics.setColor(1, 1, 1, 1)
end

local function draw_deal_done_banner(view, regions)
    if not view or not view.deal_done then
        return
    end
    local centre = regions.centre
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", centre.x, centre.y, centre.w, centre.h)
    love.graphics.setColor(1, 1, 1, 1)
    local key = view.deal_done.reason == "all_pass" -- i18n-ok
            and "scene.table.deal_done.all_pass"
        or "scene.table.deal_done.scored"
    love.graphics.print(t(key), centre.x + 24, centre.y + 24)
    if view.deal_done.running_totals then
        local totals = view.deal_done.running_totals
        for i, total in ipairs(totals) do
            love.graphics.print(
                t("scene.table.player_label.other", { n = i }) .. " " .. tostring(total),
                centre.x + 24,
                centre.y + 50 + (i - 1) * 18
            )
        end
    end
end

local function draw_marriage_modal(self, w, h)
    if self._modal ~= "marriage" or not self._marriage_payload then
        return
    end
    love.graphics.setColor(MODAL_DIM)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local panel_w, panel_h = 480, 220
    local px = math.floor(w * 0.5 - panel_w * 0.5)
    local py = math.floor(h * 0.5 - panel_h * 0.5)
    love.graphics.setColor(MODAL_BG)
    love.graphics.rectangle("fill", px, py, panel_w, panel_h)
    love.graphics.setColor(1, 1, 1, 1)

    local prompt = t("scene.table.marriage.prompt")
    love.graphics.print(prompt, px + 40, py + 60)
    -- Draw the suit as a primitive next to the prompt — same reason as
    -- the trump and lead-suit indicators: the default LÖVE font has no
    -- glyph for ♠♣♦♥.
    cards.draw_suit(self._marriage_payload.suit, px + 40 + 160, py + 68, 16)

    local btn_w, btn_h, btn_gap = 200, 48, 24
    local total_w = btn_w * 2 + btn_gap
    local btn_y = py + panel_h - btn_h - 28
    local left_x = px + math.floor(panel_w * 0.5 - total_w * 0.5)
    self._modal_buttons[1]:set_rect(left_x, btn_y, btn_w, btn_h)
    self._modal_buttons[2]:set_rect(left_x + btn_w + btn_gap, btn_y, btn_w, btn_h)
    for _, b in ipairs(self._modal_buttons) do
        b:draw()
    end
end

local function draw_toast(self, regions)
    if not self._toast then
        return
    end
    local centre = regions.centre
    local text = t(self._toast.key, self._toast.params)
    local toast_w = math.min(centre.w - 32, 480)
    local toast_h = 36
    local x = centre.x + math.floor((centre.w - toast_w) * 0.5)
    local y = centre.y + centre.h - toast_h - 4
    love.graphics.setColor(TOAST_BG)
    love.graphics.rectangle("fill", x, y, toast_w, toast_h)
    love.graphics.setColor(TOAST_FG)
    love.graphics.print(text, x + 12, y + 10)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Lifecycle ------------------------------------------------------------

function M:update(dt)
    if self._toast then
        self._toast.remaining = self._toast.remaining - (dt or 0)
        if self._toast.remaining <= 0 then
            self._toast = nil
        end
    end
end

function M:_concat_focus_buttons()
    local list = {}
    for _, b in ipairs(self._panel_buttons) do
        list[#list + 1] = b
    end
    list[#list + 1] = self._back_button
    return list
end

function M:draw(w, h)
    w = w or 800
    h = h or 600

    love.graphics.clear(0.07, 0.22, 0.12)

    self:_refresh_view_model()
    self:_rebuild_panel_if_needed(self._view_model)
    self:_seed_focus_if_idle()

    local regions = layout.table_regions(w, h, {
        menu_btn_w = MENU_BTN_W,
        menu_btn_h = MENU_BTN_H,
    })
    self._last_regions = regions

    draw_opponents(self, self._view_model, regions.opponents)
    draw_centre(self, self._view_model, regions.centre)
    draw_hand(self, self._view_model, regions.hand)
    draw_scoreboard(self._view_model, regions.scoreboard)
    draw_pass_target_label(self._view_model, regions)
    draw_panel_label(self._view_model, regions.centre)

    lay_out_panel_buttons(self, regions)
    self:_sync_focus_marks()
    draw_panel_buttons(self)
    draw_deal_done_banner(self._view_model, regions)

    self._back_button:set_rect(
        regions.menu_button.x,
        regions.menu_button.y,
        regions.menu_button.w,
        regions.menu_button.h
    )
    self._back_button:draw()

    draw_toast(self, regions)
    draw_marriage_modal(self, w, h)

    love.graphics.setColor(1, 1, 1, 1)
end

-- Hit-tests + input dispatch -------------------------------------------

local function rect_contains(rect, x, y)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

function M:_active_buttons()
    if self._modal == "marriage" then
        return self._modal_buttons
    end
    local list = {}
    for _, b in ipairs(self._panel_buttons) do
        list[#list + 1] = b
    end
    list[#list + 1] = self._back_button
    return list
end

function M:_card_hit(x, y)
    -- Only the active player's hand is tappable; opponents are face-down
    -- and tap targets become meaningful only in the privacy hand-off
    -- (next task). Each rect carries a wider .hit version that covers
    -- half the inter-card gap on each side so a click in the gap still
    -- registers on whichever card is closest.
    for i = 1, #self._hand_card_rects do
        local entry = self._hand_card_rects[i]
        local hit = entry.hit or entry.rect
        if rect_contains(hit, x, y) then
            return entry, i
        end
    end
    return nil, nil
end

function M:_handle_card_tap(view, entry)
    if not view or not entry then
        return
    end
    -- i18n-ok: phase / status / rank tokens are engine enums, never rendered.
    local talon_phase = view.talon_phase
    local awaiting = talon_phase and talon_phase.status == "awaiting_pass" -- i18n-ok
    if view.phase == "talon" and awaiting then
        local target = talon_phase.pass_target_seat
        if target then
            self:_do_pass_talon(target, entry.card)
        end
        return
    end
    if view.phase == "tricks" then
        local turn = view.turn_player
        if turn and view.hands[turn] and view.hands[turn].perspective == "self" then
            local marriage_offer = view.marriage_offer
            if marriage_offer and (entry.card.rank == "K" or entry.card.rank == "Q") then -- i18n-ok
                for _, suit in ipairs(marriage_offer.suits) do
                    if entry.card.suit == suit then
                        self:_open_marriage_modal(turn, suit, entry.card)
                        return
                    end
                end
            end
            self:_do_play(turn, entry.card)
        end
    end
end

function M:mousemoved(x, y, _dx, _dy)
    for _, b in ipairs(self:_active_buttons()) do
        b:on_mousemoved(x, y)
    end
    -- Card hover — purely visual; keyboard focus stays separate.
    local _, idx = self:_card_hit(x, y)
    self._hovered_card_index = idx
end

function M:mousepressed(x, y, button)
    if button ~= 1 then
        return
    end
    if self._modal == "marriage" then
        for _, b in ipairs(self._modal_buttons) do
            if b:on_mousepressed(x, y, button) then
                return
            end
        end
        return
    end
    for _, b in ipairs(self:_active_buttons()) do
        if b:on_mousepressed(x, y, button) then
            return
        end
    end
    -- Fall through to card hit-test only when no button arms. The hand
    -- card rects are rebuilt every draw, so we cache the *card identity*
    -- (suit + rank) rather than the rect entry — release on the next
    -- frame would otherwise see a different table reference even though
    -- the card under the cursor hasn't changed.
    local entry = self:_card_hit(x, y)
    if entry then
        self._pending_card = { suit = entry.card.suit, rank = entry.card.rank }
    end
end

-- Update the panel buttons' focused flag from _focus_index. Called
-- before draw_panel_buttons so the focus ring tracks _focus_index even
-- when the panel was just rebuilt.
function M:_sync_focus_marks()
    self:_apply_button_focus_marks()
end

function M:mousereleased(x, y, button)
    if button ~= 1 then
        return
    end
    if self._modal == "marriage" then
        for _, b in ipairs(self._modal_buttons) do
            if b:on_mousereleased(x, y, button) then
                return
            end
        end
        return
    end
    local fired_button = false
    for _, b in ipairs(self:_active_buttons()) do
        if b:on_mousereleased(x, y, button) then
            fired_button = true
            break
        end
    end
    if not fired_button and self._pending_card then
        local entry = self:_card_hit(x, y)
        if
            entry
            and entry.card.suit == self._pending_card.suit
            and entry.card.rank == self._pending_card.rank
        then
            self:_handle_card_tap(self._view_model, entry)
        end
    end
    self._pending_card = nil
end

local function shift_held()
    if not (love.keyboard and love.keyboard.isDown) then
        return false
    end
    return love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") -- i18n-ok
end

function M:keypressed(key)
    if self._modal == "marriage" then
        if key == "tab" then -- i18n-ok
            self._modal_focus:advance(shift_held() and -1 or 1)
        elseif key == "left" or key == "up" then -- i18n-ok
            self._modal_focus:advance(-1)
        elseif key == "right" or key == "down" then -- i18n-ok
            self._modal_focus:advance(1)
        elseif key == "return" or key == "space" or key == "kpenter" then -- i18n-ok
            self._modal_focus:activate()
        elseif key == "escape" then -- i18n-ok
            self:_close_marriage_modal()
        end
        return
    end
    if key == "escape" then -- i18n-ok
        self:_return_to_menu()
    elseif key == "tab" then -- i18n-ok
        self:_advance_focus(shift_held() and -1 or 1)
    elseif key == "left" then -- i18n-ok
        self:_advance_within_group(-1)
    elseif key == "right" then -- i18n-ok
        self:_advance_within_group(1)
    elseif key == "up" or key == "down" then -- i18n-ok
        self:_jump_focus_groups()
    elseif key == "return" or key == "space" or key == "kpenter" then -- i18n-ok
        if self._focus_index then
            self:_activate_focus()
        elseif #self._panel_buttons == 1 then
            -- Single-action mode (e.g. talon take) — Enter without prior
            -- Tab activates it so a keyboard user does not have to nav.
            self._panel_buttons[1]:activate()
        else
            self._back_button:activate()
        end
    end
end

return M
