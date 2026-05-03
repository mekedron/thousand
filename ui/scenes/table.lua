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
-- state knows their cards. The hot-seat hand-off layers a full-opacity
-- between-turns curtain on top of the normal render pass — see
-- `_apply_curtain_trigger` and `draw_privacy_curtain`. The curtain is
-- raised whenever `current_turn` changes to a seat the curtain has not
-- yet revealed for, and dismissed by a tap, Enter, or Space; Esc
-- routes back to the menu. The active seat is whichever hand has
-- perspective == "self" in the view-model — the curtain hides that
-- hand entirely until the new player taps Ready.

local i18n = require("app.i18n")
local Button = require("ui.button")
local FocusGroup = require("ui.focus_group")
local layout = require("ui.layout")
local cards = require("ui.cards")
local view_model = require("app.table_view_model")
local settings = require("app.settings")
local bot_driver = require("app.bot.driver")
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
local PARTNER_SIDE_1_BG = { 0.40, 0.65, 0.95, 1 }
local PARTNER_SIDE_2_BG = { 0.95, 0.50, 0.40, 1 }
local PARTNER_BADGE_FG = { 0.06, 0.06, 0.10, 1 }
local LABEL_COLOR = { 0.85, 0.92, 0.85, 1 }
local VALUE_COLOR = { 1, 1, 1, 1 }
local DIM_COLOR = { 0.65, 0.72, 0.65, 1 }
local SITS_OUT_DIM = { 0.45, 0.50, 0.45, 1 }
local TOAST_BG = { 0.30, 0.06, 0.06, 0.92 }
local TOAST_FG = { 1.0, 0.92, 0.85, 1 }
local MODAL_BG = { 0.12, 0.18, 0.14, 1 }
local MODAL_DIM = { 0, 0, 0, 0.6 }
-- The privacy curtain backdrop is fully opaque so the previous player's
-- hand cannot leak through, even for a frame. The 0.6-alpha MODAL_DIM
-- used for the marriage prompt would not be private enough.
local CURTAIN_BG = { 0, 0, 0, 1 }
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
        _modal = nil, -- i18n-ok: nil | "marriage" | "redeal" | "bad_talon" | "rebuy" enum
        _marriage_payload = nil,
        -- Redeal prompt modal state. _redeal_payload mirrors the
        -- view-model's redeal_prompt block while the modal is open;
        -- _redeal_signature is the prompt's identity (kind+seat+forced)
        -- so a re-render with the same offer leaves the modal alone.
        _redeal_payload = nil,
        _redeal_signature = nil,
        -- Bad-talon prompt modal state. Mirrors the redeal-modal
        -- pattern: payload tracks what the modal is showing;
        -- signature (kind+declarer+points) is identity.
        _bad_talon_payload = nil,
        _bad_talon_signature = nil,
        -- Rebuy prompt modal state. Mirrors the bad-talon-modal
        -- pattern: payload tracks the head defender's offer details;
        -- signature (seat+contract+from_declarer) is identity so
        -- consecutive renders for the same head leave the modal alone.
        _rebuy_payload = nil,
        _rebuy_signature = nil,
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
        -- Most recent input source — nil before any input, then
        -- "mouse" or "keyboard". Mouse and keyboard navigation are
        -- mutually exclusive on the hand: hovering with the cursor
        -- elevates a card; pressing Tab/arrows shows the keyboard
        -- focus ring instead and suppresses the hover lift. The mode
        -- flips back the moment the other input fires.
        _input_mode = nil,
        -- Hot-seat privacy. When the active seat changes, _curtain is
        -- raised — a full-opacity overlay that hides the table until
        -- the new player taps Ready. _last_revealed_seat tracks which
        -- seat the curtain has most recently dismissed for, so the
        -- trigger logic in draw() can compare it to view.turn_player.
        _curtain = nil,
        _last_revealed_seat = nil,
        _curtain_button = nil,
        _curtain_focus = nil,
        -- Phase 4.2 bot driver wiring. `_seat_kinds` is one entry per
        -- seat ("human" | "bot"); the driver's tick polls current_turn
        -- and asks the bot module for an action when the responsible
        -- seat is a bot. The binding is supplied by the new-game picker
        -- (and the Single Player menu entry) via switch_to params, with
        -- a fallback to `session:seat_kinds()` for the auto-save Continue
        -- path. A nil binding leaves the driver no-op'd — Phase 2
        -- hot-seat semantics.
        _seat_kinds = nil,
        -- Phase 4.2 per-seat bot difficulty parallel to `_seat_kinds`.
        -- The driver passes the per-seat value to each chooser at tick
        -- time; nil means the driver defaults each seat to "normal".
        _seat_difficulties = nil,
        _bot_driver = nil,
        -- Phase 4.2 viewer lock. When `_seat_kinds` is set, the view-model
        -- treats `_viewer_seat` as "self" instead of following
        -- current_turn. Single-player pins it to the lone human; mixed
        -- multi-human follows current_turn between humans and stays put
        -- while a bot is on turn. Recomputed each frame in
        -- _refresh_viewer; nil means legacy hot-seat behaviour.
        _viewer_seat = nil,
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
        self:_refresh_viewer(session)
        self._view_model = view_model.from_session(session, self._viewer_seat)
    else
        self._viewer_seat = nil
        self._view_model = nil
    end
end

-- Phase 4.2: derive the persistent viewer seat from seat_kinds and the
-- current turn. Sticky last-human-viewer carries forward across frames
-- (single-player resolves to a constant; multi-human snaps between
-- humans on turn change but ignores bot-on-turn intermediate states).
function M:_refresh_viewer(session)
    if not self._seat_kinds then
        self._viewer_seat = nil
        return
    end
    session = session or self:_session()
    local turn = session and session:current_turn() or nil
    self._viewer_seat = view_model.derive_viewer(self._seat_kinds, turn, self._viewer_seat)
end

function M:enter(_prev_id, params)
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
    self._input_mode = nil
    -- Re-entering the table always re-curtains: whoever picks the
    -- device up after leaving the menu hasn't yet asserted their seat
    -- identity. The first draw() will raise the curtain for whichever
    -- seat current_turn returns.
    self._curtain = nil
    self._last_revealed_seat = nil
    self._curtain_button = nil
    self._curtain_focus = nil
    -- Phase 4.2: reset the viewer lock on re-entry. _refresh_view_model
    -- below recomputes it from the resolved seat_kinds; clearing here
    -- ensures the sticky last-human-viewer state from a previous deal
    -- doesn't leak into the new one.
    self._viewer_seat = nil
    -- Phase 4.2: per-seat human/bot binding flows from the new-game
    -- picker (or Single Player one-click) via switch_to params. The
    -- Continue path comes through main.lua → manager:set_session(...) →
    -- switch_to("table") with no params, so we fall back to whatever
    -- binding the restored session carries (auto_save round-trips it).
    -- A nil binding leaves the bot driver no-op'd, preserving Phase 2
    -- hot-seat semantics for any pre-4.2 save and any test that didn't
    -- supply one.
    local session = self:_session()
    self._seat_kinds = (params and params.seat_kinds) or (session and session:seat_kinds())
    self._seat_difficulties = (params and params.seat_difficulties)
        or (session and session:seat_difficulties())
    self._bot_driver = bot_driver.new({})
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
    -- Phase 4.2: never let the human tap into a bot's hand. For tricks
    -- this is implicit (the perspective change makes the bot's hand
    -- "other"), but talon awaiting_pass / awaiting_discard branches
    -- below don't check perspective, so the explicit gate is
    -- load-bearing for those.
    if self._seat_kinds and view.turn_player ~= nil and self:_seat_is_bot(view.turn_player) then
        return false
    end
    if view.phase == "tricks" or view.phase == "raspassy_play" then -- i18n-ok: phase enums
        return view.turn_player ~= nil
            and view.hands[view.turn_player]
            and view.hands[view.turn_player].perspective == "self"
    end
    -- Phase 3.9 follow-up: the pre-tricks write-off offer keeps the
    -- talon alive and the hand fully interactive; card taps fire pass
    -- mutators that auto-clear the offer in the engine.
    local pass_phase = view.phase == "talon" -- i18n-ok: phase enums
        or view.phase == "awaiting_write_off_decision" -- i18n-ok
    if pass_phase and view.talon_phase then
        local status = view.talon_phase.status
        return status == "awaiting_pass" or status == "awaiting_discard" -- i18n-ok: engine enums
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
-- panel-buttons-only). Bound to Left/Right so the player can walk
-- their hand left↔right or sweep the bid panel without overshooting.
-- The back-to-menu button is reachable via Tab but NOT via arrow
-- keys — arrows are for primary actions (cards, bid amounts), and
-- the exit button shouldn't sit in that cycle.
function M:_advance_within_group(direction)
    local card_count = self:_focus_card_count()
    local panel_count = #self._panel_buttons -- excludes back button
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
    if target == "panel" then -- i18n-ok
        rel = self._focus_index - card_count
    else
        -- target is nil or "back": seed/jump into the panel group at
        -- whichever end the direction implies.
        rel = direction > 0 and 0 or panel_count + 1
    end
    rel = ((rel - 1 + direction) % panel_count) + 1
    self._focus_index = card_count + rel
end

-- Up/Down walks the three vertical focus groups in screen order:
-- Menu (top-right) → panel buttons (mid) → hand cards (bottom). Up
-- moves toward the top of the screen, Down toward the bottom; both
-- wrap. Left/Right still stay inside whichever group focus is on,
-- and Tab cycles through every focusable in declaration order.
function M:_jump_focus_groups(direction)
    direction = direction or 1
    local card_count = self:_focus_card_count()
    local panel_count = #self._panel_buttons

    -- Top-to-bottom screen order. The Menu button is always present;
    -- the other groups appear only when populated.
    local groups = { "back" } -- i18n-ok
    if panel_count > 0 then
        groups[#groups + 1] = "panel" -- i18n-ok
    end
    if card_count > 0 then
        groups[#groups + 1] = "card" -- i18n-ok
    end
    if #groups <= 1 then
        return
    end

    local target = self:_focus_target()
    local cur = 0
    for i, g in ipairs(groups) do
        if g == target then
            cur = i
            break
        end
    end

    local next_idx
    if cur == 0 then
        -- No prior focus. Down lands on the bottom-most group
        -- (#groups in our top-to-bottom list); Up lands on the
        -- top-most (1). The screen direction the player pressed is
        -- the screen direction the focus should land in.
        next_idx = direction > 0 and #groups or 1
    else
        next_idx = ((cur - 1 + direction) % #groups) + 1
    end

    local next_group = groups[next_idx]
    if next_group == "card" then -- i18n-ok
        self._focus_index = 1
    elseif next_group == "panel" then -- i18n-ok
        self._focus_index = card_count + 1
    elseif next_group == "back" then -- i18n-ok
        self._focus_index = card_count + panel_count + 1
    end
end

-- Focus follows the focus-visible idiom: the yellow outline only
-- appears after the user explicitly navs with Tab/arrows. Hovering or
-- entering an interactive phase does NOT seed focus on its own — that
-- collides with the hover-only "elevate the card" affordance the
-- player already gets from a mouse / touch.

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

-- Reconcile keyboard focus with a hand that just shrank. Card-removing
-- mutations (play, talon-pass, marriage+play) either reduce the active
-- hand by one (talon awaiting_pass) or rotate to the next seat whose
-- count may also be lower (a closing trick play). Without an
-- adjustment the unified _focus_index slides into the panel/back
-- range and the yellow ring silently lands on the Menu button.
--
-- Pre-mutation target is captured by the call site so we can tell
-- "focus was on a card" from "focus was on Back". When focus was on
-- a card we keep it on a card: snap to the new last card if the
-- index is now beyond range, or clear it when the new hand is
-- empty (deal_done after the eighth trick).
function M:_reconcile_card_focus_after_mutation(pre_target)
    if pre_target ~= "card" then
        return
    end
    if not self._focus_index then
        return
    end
    local card_count = self:_focus_card_count()
    if card_count == 0 then
        self._focus_index = nil
    elseif self._focus_index > card_count then
        self._focus_index = card_count
    end
end

-- Input → session boundary ---------------------------------------------

-- Map an engine error code to a localised toast. The trick-taking rules
-- (`must_follow_violation`, `must_beat_violation`, `must_trump_violation`,
-- `must_overtrump_violation`) each carry their relevant suit (`led_suit`
-- or `trump`) on the error envelope; we surface that suit through the
-- localised `card.suit.*` glyph so the toast tells the player exactly
-- which constraint they hit. Unknown codes fall through to the generic
-- `illegal_play` reason path so a future engine error never produces a
-- bare English string at the table.
local function suit_glyph(suit)
    if not suit then
        return "" -- i18n-ok: empty fallback when the engine error omits the suit
    end
    return i18n.t("card.suit." .. suit) -- i18n-ok: lookup builds an i18n key
end

local function err_to_toast_key(err)
    if not err then
        return "scene.table.toast.illegal_play", { reason = "" } -- i18n-ok
    end
    local code = err.code
    if code == "not_your_turn" then
        return "scene.table.toast.not_your_turn", {}
    elseif code == "must_follow_violation" then
        return "scene.table.toast.must_follow", { suit = suit_glyph(err.led_suit) }
    elseif code == "must_beat_violation" then
        return "scene.table.toast.must_beat", { suit = suit_glyph(err.led_suit) }
    elseif code == "must_trump_violation" then
        return "scene.table.toast.must_trump", { suit = suit_glyph(err.trump) }
    elseif code == "must_overtrump_violation" then
        return "scene.table.toast.must_overtrump", { suit = suit_glyph(err.trump) }
    elseif code == "card_not_in_hand" then
        return "scene.table.toast.card_not_in_hand", {}
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
    local pre_target = self:_focus_target()
    self:_invoke(session:pass_talon(target, card))
    self:_refresh_view_model()
    self:_reconcile_card_focus_after_mutation(pre_target)
end

function M:_do_discard_talon(card)
    local session = self:_session()
    if not session then
        return
    end
    local pre_target = self:_focus_target()
    self:_invoke(session:discard_talon(card))
    self:_refresh_view_model()
    self:_reconcile_card_focus_after_mutation(pre_target)
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

-- Polish Tysiąc direct pass. The first cut auto-distributes the two
-- talon cards in clockwise order from the declarer (talon[1] to the
-- next opponent, talon[2] to the one after). The engine API takes
-- explicit `(target, talon_index)` arguments so a future agency-mode
-- UI can hand the choice back to the player without changing
-- core/talon.lua.
function M:_do_pass_polish_talon()
    local session = self:_session()
    if not session then
        return
    end
    local view = self._view_model
    local talon_phase = view and view.talon_phase
    if not talon_phase or not talon_phase.polish_pass_pending then
        return
    end
    local remaining = talon_phase.polish_pass_remaining_seats or {}
    for _, seat in ipairs(remaining) do
        local result = session:pass_polish_talon(seat, 1)
        self:_invoke(result)
        if not result.ok then
            break
        end
    end
    self:_refresh_view_model()
end

function M:_do_concede_deal()
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:concede_deal())
    self:_refresh_view_model()
end

-- Phase 3.7 / 3.9 write-off / сдача: declarer concedes the contract
-- in response to the pre-tricks `awaiting_write_off_decision` prompt.
-- Replaces the inline mid-tricks button removed in Phase 3.9.
function M:_do_write_off()
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:write_off())
    self:_refresh_view_model()
end

-- Phase 3.8: invoke the procedural cut. The action carries no
-- decision (the engine inspects the bottom card and routes between
-- good_cut / bad_cut / threshold_penalty internally) so the handler
-- is identical in shape to write_off — just dispatch and refresh.
function M:_do_cut_deck()
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:cut_deck())
    self:_refresh_view_model()
end

function M:_do_buyback_hand()
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:buyback_hand())
    self:_refresh_view_model()
end

-- Phase 3.6 bidding-house-rules handlers ------------------------------

function M:_do_bid_blind(player)
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:declare_blind(player))
    self:_refresh_view_model()
end

function M:_do_re_enter_auction(player, amount)
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:bid_re_entry(player, amount))
    self:_refresh_view_model()
end

function M:_do_declare_contra(defender)
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:declare_contra(defender))
    self:_refresh_view_model()
end

function M:_do_declare_redouble(declarer)
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:declare_redouble(declarer))
    self:_refresh_view_model()
end

function M:_do_skip_contra(defender)
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:skip_contra(defender))
    self:_refresh_view_model()
end

function M:_do_concede_forced_bid()
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:concede_forced_bid())
    self:_refresh_view_model()
end

function M:_do_decline_forced_bid()
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:decline_forced_bid())
    self:_refresh_view_model()
end

function M:_do_bid_named_contract(player, kind)
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:bid_named_contract(player, kind))
    self:_refresh_view_model()
end

function M:_do_accept_bad_talon_redeal()
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:accept_bad_talon_redeal())
    self:_refresh_view_model()
end

function M:_do_decline_bad_talon_redeal()
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:decline_bad_talon_redeal())
    self:_refresh_view_model()
end

function M:_do_claim_rebuy(seat)
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:claim_rebuy(seat))
    self:_refresh_view_model()
end

function M:_do_decline_rebuy(seat)
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:decline_rebuy(seat))
    self:_refresh_view_model()
end

function M:_do_play(player, card)
    local session = self:_session()
    if not session then
        return
    end
    local pre_target = self:_focus_target()
    self:_invoke(session:play(player, card))
    self:_refresh_view_model()
    self:_reconcile_card_focus_after_mutation(pre_target)
end

function M:_do_declare_then_play(player, suit, card)
    local session = self:_session()
    if not session then
        return
    end
    local pre_target = self:_focus_target()
    if not self:_invoke(session:declare_marriage(player, suit)) then
        return
    end
    self:_invoke(session:play(player, card))
    self:_refresh_view_model()
    self:_reconcile_card_focus_after_mutation(pre_target)
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

-- Phase 3.6 marriage_announcement_timing = "hand_announcement"
-- handler: announce a marriage without leading the K or Q.
function M:_do_announce_hand_marriage(player, suit)
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:announce_marriage(player, suit))
    self:_refresh_view_model()
end

-- Phase 3.6 marriage_announcement_timing = "pre_first_trick" handlers.
function M:_do_announce_pre_first_trick(player, suit)
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:announce_marriage(player, suit))
    self:_refresh_view_model()
end

function M:_do_skip_pre_first_trick(player)
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:skip_pre_first_trick_marriage(player))
    self:_refresh_view_model()
end

-- Phase 3.6 ace_marriage handler: declare the four-Aces bonus.
function M:_do_declare_ace_marriage(player)
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:declare_ace_marriage(player))
    self:_refresh_view_model()
end

-- Redeal prompt modal -------------------------------------------------

local function redeal_signature(prompt)
    if not prompt then
        return nil
    end
    -- i18n-ok: internal signature, joined with ":" and never rendered.
    local parts = { tostring(prompt.kind), tostring(prompt.seat), tostring(prompt.forced) }
    return table.concat(parts, ":") -- i18n-ok: ":" is a separator, never rendered
end

function M:_do_accept_redeal()
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:accept_redeal())
end

function M:_do_decline_redeal()
    local session = self:_session()
    if not session then
        return
    end
    self:_invoke(session:decline_redeal())
end

function M:_open_redeal_modal(prompt)
    self._modal = "redeal" -- i18n-ok
    self._redeal_payload = {
        kind = prompt.kind,
        seat = prompt.seat,
        forced = prompt.forced or false,
    }
    self._redeal_signature = redeal_signature(prompt)
    if self._redeal_payload.forced then
        -- Forced offers are shown as a non-dismissible banner with no
        -- buttons. The session auto-applies them in
        -- evaluate_entitlement_with_forced_loop, so production code
        -- never reaches this branch — but tests can inject a forced
        -- offer through Session.from_state, and the UI must render
        -- something rather than crashing.
        self._modal_buttons = {}
        self._modal_focus = nil
        return
    end
    local accept = Button.new({
        id = "redeal_accept", -- i18n-ok
        label_key = "scene.table.redeal_prompt.accept",
        enabled = true,
        on_press = function()
            self:_do_accept_redeal()
            self:_close_redeal_modal()
        end,
    })
    local decline = Button.new({
        id = "redeal_decline", -- i18n-ok
        label_key = "scene.table.redeal_prompt.decline",
        enabled = true,
        on_press = function()
            self:_do_decline_redeal()
            self:_close_redeal_modal()
        end,
    })
    self._modal_buttons = { accept, decline }
    self._modal_focus = FocusGroup.new(self._modal_buttons)
    -- Default focus on Accept — the entitled player tapped a redeal
    -- option deliberately, so the high-information branch is to redeal
    -- (the alternative is to play out a documented bad hand).
    self._modal_focus:focus(accept)
end

function M:_close_redeal_modal()
    if self._modal == "redeal" then
        self._modal = nil
    end
    self._redeal_payload = nil
    self._redeal_signature = nil
    self._modal_buttons = {}
    self._modal_focus = nil
end

-- Open / close the redeal modal in lock-step with the view-model. Called
-- once per draw before the panel is rebuilt so the modal reflects the
-- session's current redeal_offer state.
function M:_apply_redeal_modal_trigger(view)
    local prompt = view and view.redeal_prompt
    if not prompt then
        if self._modal == "redeal" then
            self:_close_redeal_modal()
        end
        return
    end
    local sig = redeal_signature(prompt)
    if self._modal == "redeal" and self._redeal_signature == sig then
        return
    end
    self:_open_redeal_modal(prompt)
end

-- Bad-talon prompt modal ----------------------------------------------

local function bad_talon_signature(prompt)
    if not prompt then
        return nil
    end
    -- i18n-ok: internal signature, joined with ":" and never rendered.
    local parts = { tostring(prompt.kind), tostring(prompt.declarer), tostring(prompt.points) }
    return table.concat(parts, ":") -- i18n-ok: ":" is a separator, never rendered
end

function M:_open_bad_talon_modal(prompt)
    self._modal = "bad_talon" -- i18n-ok
    self._bad_talon_payload = {
        kind = prompt.kind,
        declarer = prompt.declarer,
        points = prompt.points,
    }
    self._bad_talon_signature = bad_talon_signature(prompt)
    local accept = Button.new({
        id = "bad_talon_accept", -- i18n-ok
        label_key = "scene.table.bad_talon_prompt.accept",
        enabled = true,
        on_press = function()
            self:_do_accept_bad_talon_redeal()
            self:_close_bad_talon_modal()
        end,
    })
    local decline = Button.new({
        id = "bad_talon_decline", -- i18n-ok
        label_key = "scene.table.bad_talon_prompt.decline",
        enabled = true,
        on_press = function()
            self:_do_decline_bad_talon_redeal()
            self:_close_bad_talon_modal()
        end,
    })
    self._modal_buttons = { accept, decline }
    self._modal_focus = FocusGroup.new(self._modal_buttons)
    -- Default focus on Accept — the player just saw a documented-bad
    -- talon, the high-information branch is to redeal.
    self._modal_focus:focus(accept)
end

function M:_close_bad_talon_modal()
    if self._modal == "bad_talon" then
        self._modal = nil
    end
    self._bad_talon_payload = nil
    self._bad_talon_signature = nil
    self._modal_buttons = {}
    self._modal_focus = nil
end

function M:_apply_bad_talon_modal_trigger(view)
    local prompt = view and view.bad_talon_prompt
    if not prompt then
        if self._modal == "bad_talon" then
            self:_close_bad_talon_modal()
        end
        return
    end
    local sig = bad_talon_signature(prompt)
    if self._modal == "bad_talon" and self._bad_talon_signature == sig then
        return
    end
    self:_open_bad_talon_modal(prompt)
end

local function rebuy_signature(prompt)
    if not prompt then
        return nil
    end
    -- i18n-ok: internal signature, joined with ":" and never rendered.
    local parts = {
        tostring(prompt.seat),
        tostring(prompt.contract),
        tostring(prompt.from_declarer),
    }
    return table.concat(parts, ":") -- i18n-ok: ":" is a separator, never rendered
end

function M:_open_rebuy_modal(prompt)
    self._modal = "rebuy" -- i18n-ok
    self._rebuy_payload = {
        seat = prompt.seat,
        contract = prompt.contract,
        from_declarer = prompt.from_declarer,
    }
    self._rebuy_signature = rebuy_signature(prompt)
    local seat = prompt.seat
    local contract = prompt.contract
    local accept = Button.new({
        id = "rebuy_accept", -- i18n-ok
        label_key = "scene.table.rebuy_prompt.accept",
        label_params = { value = contract },
        enabled = true,
        on_press = function()
            self:_do_claim_rebuy(seat)
            self:_close_rebuy_modal()
        end,
    })
    local decline = Button.new({
        id = "rebuy_decline", -- i18n-ok
        label_key = "scene.table.rebuy_prompt.decline",
        enabled = true,
        on_press = function()
            self:_do_decline_rebuy(seat)
            self:_close_rebuy_modal()
        end,
    })
    self._modal_buttons = { accept, decline }
    self._modal_focus = FocusGroup.new(self._modal_buttons)
    -- Default focus on Decline — accepting commits the seat to a steep
    -- fixed contract sight-half-unseen, so the safer branch is the
    -- default keyboard target.
    self._modal_focus:focus(decline)
end

function M:_close_rebuy_modal()
    if self._modal == "rebuy" then
        self._modal = nil
    end
    self._rebuy_payload = nil
    self._rebuy_signature = nil
    self._modal_buttons = {}
    self._modal_focus = nil
end

function M:_apply_rebuy_modal_trigger(view)
    local prompt = view and view.rebuy_prompt
    if not prompt then
        if self._modal == "rebuy" then
            self:_close_rebuy_modal()
        end
        return
    end
    local sig = rebuy_signature(prompt)
    if self._modal == "rebuy" and self._rebuy_signature == sig then
        return
    end
    self:_open_rebuy_modal(prompt)
end

-- Phase 3.9 write-off prompt modal -----------------------------------

local function write_off_prompt_signature(prompt)
    if not prompt then
        return nil
    end
    -- i18n-ok: internal signature, joined with ":" and never rendered.
    local parts = {
        tostring(prompt.declarer),
        tostring(prompt.bid),
        tostring(prompt.split_mode),
    }
    return table.concat(parts, ":") -- i18n-ok: ":" is a separator, never rendered
end

function M:_open_write_off_prompt_modal(prompt)
    self._modal = "write_off_prompt" -- i18n-ok
    self._write_off_prompt_payload = {
        declarer = prompt.declarer,
        bid = prompt.bid,
        split_mode = prompt.split_mode,
        share = prompt.share,
    }
    self._write_off_prompt_signature = write_off_prompt_signature(prompt)
    local accept = Button.new({
        id = "write_off_prompt_accept", -- i18n-ok
        label_key = "scene.table.write_off_prompt.accept",
        enabled = true,
        on_press = function()
            self:_do_write_off()
            self:_close_write_off_prompt_modal()
        end,
    })
    local decline = Button.new({
        id = "write_off_prompt_decline", -- i18n-ok
        label_key = "scene.table.write_off_prompt.decline",
        enabled = true,
        on_press = function()
            -- Phase 3.9 follow-up: Cancel just closes the confirmation
            -- modal. The write-off offer stays open and the inline
            -- button is still available until the declarer passes
            -- their first card (which auto-clears the offer in the
            -- engine).
            self:_close_write_off_prompt_modal()
        end,
    })
    self._modal_buttons = { accept, decline }
    self._modal_focus = FocusGroup.new(self._modal_buttons)
    -- Default focus on Cancel: writing off is the destructive branch
    -- (the declarer pays the contract immediately), so the safer
    -- keyboard target is to back out of the confirmation.
    self._modal_focus:focus(decline)
end

function M:_close_write_off_prompt_modal()
    if self._modal == "write_off_prompt" then
        self._modal = nil
    end
    self._write_off_prompt_payload = nil
    self._write_off_prompt_signature = nil
    self._modal_buttons = {}
    self._modal_focus = nil
end

function M:_apply_write_off_prompt_modal_trigger(view)
    -- Phase 3.9 follow-up: the modal opens only on user click of the
    -- inline Write-off button (see `build_write_off_decision_panel`).
    -- The auto-trigger now only auto-closes — fires when the offer
    -- clears under the modal (e.g. the declarer pressed Esc, then
    -- passed a card). Keeps the modal from outliving its prompt.
    local prompt = view and view.write_off_prompt
    if not prompt and self._modal == "write_off_prompt" then
        self:_close_write_off_prompt_modal()
    end
end

-- Privacy curtain ------------------------------------------------------

function M:_open_curtain(for_seat)
    self._curtain = { for_seat = for_seat }
    local ready = Button.new({
        id = "privacy_ready", -- i18n-ok
        label_key = "scene.table.privacy.ready_button",
        enabled = true,
        on_press = function()
            self:_close_curtain()
        end,
    })
    self._curtain_button = ready
    self._curtain_focus = FocusGroup.new({ ready })
    self._curtain_focus:focus(ready)
end

function M:_close_curtain()
    if self._curtain then
        self._last_revealed_seat = self._curtain.for_seat
    end
    self._curtain = nil
    self._curtain_button = nil
    self._curtain_focus = nil
end

-- Decide whether the curtain should be up this frame and (re)raise it
-- if so. Called from draw() right after the view-model is refreshed.
-- When the active seat is nil (deal_done or done), we clear the
-- last-revealed seat so the next non-nil turn always re-curtains —
-- the device sat on the table during the score banner, so any seat
-- picking it up next is a hand-off. The Settings scene exposes a
-- toggle that disables this entirely so a tester can drive every seat
-- without dismissing a curtain on each turn.
function M:_apply_curtain_trigger()
    if not settings.get("hot_seat_privacy") then
        if self._curtain then
            self:_close_curtain()
        end
        self._last_revealed_seat = nil
        return
    end
    local view = self._view_model
    if not view or view.turn_player == nil then
        self._last_revealed_seat = nil
        return
    end
    if self._curtain then
        return
    end
    -- Phase 4.1: bot seats never see the privacy curtain — there's no
    -- human eye to protect. The curtain re-fires when control returns
    -- to a different human seat (last_revealed_seat is only set by
    -- _close_curtain when an actual human dismisses the cover).
    if self:_seat_is_bot(view.turn_player) then
        return
    end
    if view.turn_player ~= self._last_revealed_seat then
        self:_open_curtain(view.turn_player)
    end
end

function M:_seat_is_bot(seat)
    if not seat or not self._seat_kinds then
        return false
    end
    return self._seat_kinds[seat] == "bot"
end

-- Per-frame panel building --------------------------------------------

local function build_auction_panel(self, view)
    local on_turn = view.auction.on_turn
    local panel = {}
    local disabled_set = view.auction.disabled_bid_amounts
    for _, amount in ipairs(view.auction.allowed_bid_amounts) do
        local disabled = disabled_set and disabled_set[amount] == true
        panel[#panel + 1] = Button.new({
            id = "bid_" .. amount, -- i18n-ok
            label_key = "scene.table.auction.bid_button",
            label_params = { amount = amount },
            enabled = not disabled,
            on_press = function()
                self:_do_bid(on_turn, amount)
            end,
        })
    end
    -- Phase 3.6 blind bid button.
    if view.auction.blind_bid_offer and view.auction.blind_bid_offer.seat == on_turn then
        local mult = view.auction.blind_bid_offer.multiplier_preview
        panel[#panel + 1] = Button.new({
            id = "auction_bid_blind", -- i18n-ok
            label_key = "scene.table.auction.bid_blind_button",
            label_params = { multiplier = mult },
            enabled = true,
            on_press = function()
                self:_do_bid_blind(on_turn)
            end,
        })
    end
    -- Phase 3.6 named contract buttons.
    if view.auction.named_contract_buttons then
        local NAMED_KEY_PREFIX = "scene.table.auction.named_" -- i18n-ok: prefix
        local NAMED_KEY_SUFFIX = "_button" -- i18n-ok: suffix
        for _, btn in ipairs(view.auction.named_contract_buttons) do
            local label_key = NAMED_KEY_PREFIX .. btn.kind .. NAMED_KEY_SUFFIX
            panel[#panel + 1] = Button.new({
                id = "auction_" .. btn.id, -- i18n-ok
                label_key = label_key,
                label_params = { value = btn.contract_value },
                enabled = true,
                on_press = function()
                    self:_do_bid_named_contract(on_turn, btn.kind)
                end,
            })
        end
    end
    -- Phase 3.6 re-entry: a passed seat may re-enter the auction once.
    -- Render the button for any eligible passed seat the active "self"
    -- view is showing — the agent's tests treat the button as visible
    -- whenever the seat is in the eligible list, regardless of whose
    -- turn it currently is.
    if view.auction.passed_seats_with_re_entry then
        for _, seat in ipairs(view.auction.passed_seats_with_re_entry) do
            local re_seat = seat
            panel[#panel + 1] = Button.new({
                id = "auction_re_enter", -- i18n-ok
                label_key = "scene.table.auction.re_enter_button",
                enabled = true,
                on_press = function()
                    -- Re-entry needs to overcall — bid one increment
                    -- above the current bid. The session validates the
                    -- amount; a more elaborate UI can let the user pick.
                    local bidding = view.auction
                    local amount = (bidding.current_bid or 0) + 5
                    self:_do_re_enter_auction(re_seat, amount)
                end,
            })
        end
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

local function build_talon_take_panel(self, view)
    local phase_block = view and view.talon_phase
    local panel = {}
    if phase_block and phase_block.polish_pass_pending then
        -- Polish Tysiąc: declarer never picks the talon up; one button
        -- distributes both talon cards to the two opponents.
        panel[#panel + 1] = Button.new({
            id = "talon_pass_polish", -- i18n-ok
            label_key = "scene.table.talon.pass_polish_button",
            enabled = true,
            on_press = function()
                self:_do_pass_polish_talon()
            end,
        })
    else
        panel[#panel + 1] = Button.new({
            id = "talon_take", -- i18n-ok
            label_key = "scene.table.talon.take_button",
            enabled = true,
            on_press = function()
                self:_do_take_talon()
            end,
        })
    end
    if phase_block and phase_block.declarer_can_concede then
        panel[#panel + 1] = Button.new({
            id = "talon_concede", -- i18n-ok
            label_key = "scene.table.talon.concede_button",
            enabled = true,
            on_press = function()
                self:_do_concede_deal()
            end,
        })
    end
    if phase_block and phase_block.declarer_can_buyback then
        panel[#panel + 1] = Button.new({
            id = "talon_buyback", -- i18n-ok
            label_key = "scene.table.talon.buyback_button",
            label_params = { penalty = phase_block.declarer_can_buyback.penalty },
            enabled = true,
            on_press = function()
                self:_do_buyback_hand()
            end,
        })
    end
    -- Phase 3.6 contra/redouble: defender contras and declarer
    -- redoubles. Mutually exclusive — `contra_offer.kind` indicates
    -- which one is currently active.
    if phase_block and phase_block.contra_offer then
        local offer = phase_block.contra_offer
        if offer.kind == "contra" then
            local defender = offer.seats[1]
            panel[#panel + 1] = Button.new({
                id = "talon_contra", -- i18n-ok
                label_key = "scene.table.auction.contra_button",
                enabled = true,
                on_press = function()
                    self:_do_declare_contra(defender)
                end,
            })
        elseif offer.kind == "redouble" then
            local declarer = offer.seats[1]
            panel[#panel + 1] = Button.new({
                id = "talon_redouble", -- i18n-ok
                label_key = "scene.table.auction.redouble_button",
                enabled = true,
                on_press = function()
                    self:_do_declare_redouble(declarer)
                end,
            })
        end
    end
    -- Phase 3.6 forced-bid concession: declarer concedes the forced
    -- minimum-100 contract before the talon is revealed.
    if phase_block and phase_block.concede_offer then
        local split = phase_block.concede_offer.split_preview
        panel[#panel + 1] = Button.new({
            id = "talon_concede_forced", -- i18n-ok
            label_key = "scene.table.auction.concede_button",
            label_params = { split = split },
            enabled = true,
            on_press = function()
                self:_do_concede_forced_bid()
            end,
        })
    end
    return panel
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

-- Phase 3.9 follow-up: panel builder for `awaiting_write_off_decision`.
-- The take-then-pass distributions (Russian / 2-player B) sit at talon
-- status "awaiting_pass" here, where cards do the passing — the panel
-- needs only the inline Write-off button. The Polish 2-card direct-pass
-- distribution sits at status "revealed" instead, so we layer the
-- inline button on top of the existing take-panel buttons (Polish pass
-- talon, plus any concede / buyback siblings).
local function build_write_off_decision_panel(self, view)
    local talon_phase = (view and view.talon_phase) or {}
    local panel
    if talon_phase.status == "revealed" then
        panel = build_talon_take_panel(self, view)
    else
        panel = {}
    end
    panel[#panel + 1] = Button.new({
        id = "write_off_inline", -- i18n-ok
        label_key = "scene.table.write_off_inline.label",
        enabled = true,
        on_press = function()
            local prompt = self._view_model and self._view_model.write_off_prompt
            if prompt then
                self:_open_write_off_prompt_modal(prompt)
            end
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

-- Phase 3.7: tricks-phase panel buttons. Reserved for future tricks-
-- phase actions; the panel currently has no buttons.
--
-- Phase 3.9 dropped the inline write-off / сдача button — write-off is
-- now a one-shot pre-tricks decision driven by the
-- `awaiting_write_off_decision` phase modal (see
-- `_open_write_off_prompt_modal`).
local function build_tricks_panel(_self, _view)
    return {}
end

-- Phase 3.8: cut-deck-phase panel — a single "Cut the deck" button
-- visible while the procedural ritual is open. The active cutter is
-- carried in the view-model's cut_phase block; the button is the only
-- action available so there's nothing to enable/disable conditionally.
local function build_cut_panel(self)
    return {
        Button.new({
            id = "cut_deck", -- i18n-ok
            label_key = "scene.table.cut.cut_deck_button",
            enabled = true,
            on_press = function()
                self:_do_cut_deck()
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
        -- Phase 3.6 bidding-house-rules signature tokens.
        parts[#parts + 1] = view.auction.locked_bid_amount and "L" or "-" -- i18n-ok
        parts[#parts + 1] = view.auction.blind_bid_offer and "B" or "-" -- i18n-ok
        if view.auction.disabled_bid_amounts then
            local disabled_count = 0
            for _ in pairs(view.auction.disabled_bid_amounts) do
                disabled_count = disabled_count + 1
            end
            parts[#parts + 1] = "D" .. tostring(disabled_count)
        else
            parts[#parts + 1] = "-"
        end
        parts[#parts + 1] = view.auction.passed_seats_with_re_entry
                and ("R" .. tostring(#view.auction.passed_seats_with_re_entry))
            or "-"
        if view.auction.named_contract_buttons then
            for _, btn in ipairs(view.auction.named_contract_buttons) do
                parts[#parts + 1] = "N" .. btn.kind
            end
        end
        return table.concat(parts, ":")
    end
    local concession_phase = "awaiting_forced_concession_decision"
    if (phase == "talon" or phase == concession_phase) and view.talon_phase then
        local status = view.talon_phase.status
        local contra = view.talon_phase.contra_offer
        local contra_token = contra and contra.kind or "-" -- i18n-ok: signature token
        local concede = view.talon_phase.concede_offer and "K" or "-" -- i18n-ok
        if status == "awaiting_raise" then
            local parts = {
                "talon",
                "raise",
                tostring(view.current_bid),
                contra_token,
                concede,
            } -- i18n-ok
            for _, amount in ipairs(view.talon_phase.allowed_raise_amounts or {}) do
                parts[#parts + 1] = tostring(amount)
            end
            return table.concat(parts, ":")
        end
        if status == "revealed" then
            local can_concede = view.talon_phase.declarer_can_concede and "C" or "-" -- i18n-ok
            local buyback = view.talon_phase.declarer_can_buyback
            local penalty = buyback and tostring(buyback.penalty) or "-" -- i18n-ok
            local polish = view.talon_phase.polish_pass_pending and "P" or "-" -- i18n-ok
            return table.concat({
                "talon",
                "revealed",
                can_concede,
                penalty,
                polish,
                contra_token,
                concede,
            }, ":") -- i18n-ok
        end
        if status == nil then
            -- awaiting_forced_concession_decision phase: only concede_offer
            return table.concat({ "concession", concede }, ":") -- i18n-ok
        end
        return "talon:" .. status .. ":" .. contra_token .. ":" .. concede -- i18n-ok
    end
    if phase == "tricks" then
        -- Phase 3.9 removed the tricks-phase write-off signature token —
        -- the inline button is gone. Tricks panel currently has no
        -- buttons, so the signature is stable across the phase.
        return "tricks"
    end
    -- Phase 3.9 follow-up: pre-tricks write-off prompt. The inline
    -- panel sits on top of whatever the underlying talon status would
    -- normally render, so the signature carries the status to keep
    -- button identity stable across re-renders.
    if phase == "awaiting_write_off_decision" then
        local talon_phase = view.talon_phase or {}
        local status = talon_phase.status or "?" -- i18n-ok: signature token, never rendered
        return "writeoff:" .. tostring(status) -- i18n-ok: signature token
    end
    if phase == "cut" then
        local cp = view.cut_phase or {}
        local cutter = cp.active_cutter or "?" -- i18n-ok: signature token, never rendered
        local count = cp.bad_cut_count or 0
        return "cut:" .. tostring(cutter) .. ":" .. tostring(count) -- i18n-ok: signature token
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
    -- Phase 4.2: bot on turn — suppress all action affordances. The
    -- "Bot N thinking…" banner is the only on-turn surface so the human
    -- can't accidentally tap a bid button or take-talon on the bot's
    -- behalf. Auction signatures already encode `on_turn` and cut-phase
    -- signatures encode `active_cutter`, so the rebuild fires cleanly
    -- when control returns to a human; talon declarer is fixed for the
    -- whole talon phase, and the tricks panel is intentionally empty.
    if self._seat_kinds and view.turn_player ~= nil and self:_seat_is_bot(view.turn_player) then
        self._focus = FocusGroup.new(self:_concat_focus_buttons())
        self._focus_index = nil
        return
    end
    local phase = view.phase
    if phase == "auction" and view.auction then
        self._panel_buttons = build_auction_panel(self, view)
    elseif phase == "talon" and view.talon_phase then
        local status = view.talon_phase.status
        if status == "revealed" then
            self._panel_buttons = build_talon_take_panel(self, view)
        elseif status == "awaiting_pass" then
            -- Card hit-tests cover the pass action; no panel button.
            self._panel_buttons = {}
        elseif status == "awaiting_discard" then
            -- 2-player B: card hit-tests cover the face-down discard.
            self._panel_buttons = {}
        elseif status == "awaiting_raise" then
            self._panel_buttons = build_talon_raise_panel(self, view)
        end
    elseif phase == "awaiting_forced_concession_decision" and view.talon_phase then
        -- Phase 3.6 forced-bid concession surfaces only the concede
        -- button; the talon hasn't been revealed yet so the take/raise
        -- panel doesn't apply.
        self._panel_buttons = build_talon_take_panel(self, view)
    elseif phase == "awaiting_write_off_decision" and view.write_off_prompt then
        self._panel_buttons = build_write_off_decision_panel(self, view)
    elseif phase == "tricks" then
        self._panel_buttons = build_tricks_panel(self, view)
    elseif phase == "cut" then
        self._panel_buttons = build_cut_panel(self)
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
    elseif phase == "cut" then
        return "scene.table.phase.cut"
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

local function draw_partner_badge(x, y, side)
    if side == 1 then
        love.graphics.setColor(PARTNER_SIDE_1_BG)
    else
        love.graphics.setColor(PARTNER_SIDE_2_BG)
    end
    love.graphics.rectangle("fill", x, y, 22, 22)
    love.graphics.setColor(PARTNER_BADGE_FG)
    love.graphics.print(t("scene.table.partnership.badge", { n = side }), x + 7, y + 4)
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
        if hand.sits_out then
            love.graphics.setColor(SITS_OUT_DIM)
        elseif hand.is_turn then
            love.graphics.setColor(TURN_HIGHLIGHT)
        else
            love.graphics.setColor(LABEL_COLOR)
        end
        love.graphics.print(label, rect.x + 8, rect.y + 4)

        local badge_x = rect.x + 100
        if hand.is_dealer then
            draw_dealer_badge(badge_x, rect.y)
            badge_x = badge_x + 26
        end
        if hand.side then
            draw_partner_badge(badge_x, rect.y, hand.side)
        end

        local stack_x = rect.x + 8
        local stack_y = rect.y + 32

        local is_open_hand_declarer = view.declarer_hand_open
            and view.open_hand_seat
            and hand.player == view.open_hand_seat
        if hand.sits_out then
            love.graphics.setColor(SITS_OUT_DIM)
            love.graphics.print(t("scene.table.seat.sits_out"), stack_x, stack_y + 18)
            love.graphics.setColor(1, 1, 1, 1)
        elseif is_open_hand_declarer and hand.cards then
            -- Phase 3.6 open-hand visibility: the declarer's hand
            -- renders face-up to all seats for the duration of the
            -- deal. Lay the cards out as a row so the defenders can
            -- read every face.
            local card_x = stack_x
            for _, c in ipairs(hand.cards) do
                cards.draw_face_up(c, card_x, stack_y, OPPONENT_CARD_W, OPPONENT_CARD_H)
                card_x = card_x + OPPONENT_CARD_W + 4
            end
            if hand.is_turn then
                draw_turn_ring(stack_x, stack_y, OPPONENT_CARD_W, OPPONENT_CARD_H)
            end
            love.graphics.setColor(DIM_COLOR)
            love.graphics.print(
                t("scene.table.deck.size", { n = hand.count }),
                stack_x,
                stack_y + OPPONENT_CARD_H + 4
            )
        else
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
        end

        love.graphics.setColor(1, 1, 1, 1)
    end
end

local function draw_centre(self, view, region)
    love.graphics.setColor(CENTRE_BG)
    love.graphics.rectangle("fill", region.x, region.y, region.w, region.h)
    love.graphics.setColor(1, 1, 1, 1)

    if not view then
        return
    end

    -- Talon / stock block on the left of the centre band. The talon is
    -- the canonical 3-card pile; the stock is the 2-player Variant A
    -- closed-talon draw pile with the bottom card exposed as a trump
    -- indicator. Variants without a traditional talon (talon.size == 0)
    -- replace the talon area with the stock pile when one exists, or
    -- render the area as "none" when neither is present.
    local talon = view.talon
    local stock = view.stock
    local talon_label_x = region.x + 16
    local talon_label_y = region.y + 8
    local talon_x = talon_label_x
    local talon_y = talon_label_y + 24

    if stock then
        love.graphics.setColor(LABEL_COLOR)
        love.graphics.print(t("scene.table.stock.label"), talon_label_x, talon_label_y)
        if stock.count > 0 then
            cards.draw_stack(stock.count, talon_x, talon_y, TALON_CARD_W, TALON_CARD_H)
        else
            love.graphics.setColor(DIM_COLOR)
            love.graphics.print(t("scene.table.stock.empty"), talon_x, talon_y + 20)
        end
        if stock.trump_indicator then
            local indicator_x = talon_x + TALON_CARD_W + CARD_GAP
            cards.draw_face_up(
                stock.trump_indicator,
                indicator_x,
                talon_y,
                TALON_CARD_W,
                TALON_CARD_H
            )
            love.graphics.setColor(DIM_COLOR)
            love.graphics.print(
                t("scene.table.stock.trump_indicator"),
                indicator_x,
                talon_y + TALON_CARD_H + 4
            )
        end
        love.graphics.setColor(DIM_COLOR)
        love.graphics.print(
            t("scene.table.stock.count", { n = stock.count }),
            talon_x,
            talon_y + TALON_CARD_H + 4
        )
    else
        love.graphics.setColor(LABEL_COLOR)
        love.graphics.print(t("scene.table.talon.label"), talon_label_x, talon_label_y)

        -- Phase 3.6 talon-variants: hidden-on-minimum-100 hides the
        -- talon from defenders once the rule is active. Phase 4.2: when
        -- the viewer is locked to a human (single-player or mixed
        -- multi-human), the visibility decision uses that persistent
        -- seat instead of whichever bot is on turn — defenders should
        -- not get a peek just because a bot is currently passing
        -- talon cards.
        local hide_to_defender = false
        if talon.hidden_to_defenders then
            local declarer = view.talon_phase and view.talon_phase.declarer
            local viewer = self._viewer_seat or self._last_revealed_seat or view.turn_player
            if declarer and viewer and viewer ~= declarer then
                hide_to_defender = true
            end
        end
        if talon.count == 0 then
            love.graphics.setColor(DIM_COLOR)
            love.graphics.print(t("scene.table.bid.none"), talon_x, talon_y + 20)
        elseif talon.face_down or hide_to_defender then
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
    -- Mouse and keyboard input are mutually exclusive on the hand:
    -- whichever fired most recently wins, the other is suppressed
    -- until its source fires again. Hover lifts the card; focus
    -- adds the yellow outline + lift.
    local mode = self._input_mode
    local keyboard_mode = mode == "keyboard" -- i18n-ok
    local card_focus_active = interactive and keyboard_mode and self:_focus_target() == "card"
    local focused_card_index = card_focus_active and self._focus_index or nil
    local hover_active = interactive and not keyboard_mode
    local hovered_card_index = hover_active and self._hovered_card_index or nil

    if self_hand.is_turn and #card_rects > 0 then
        local first = card_rects[1]
        local last = card_rects[#card_rects]
        local total_w = (last.x + last.w) - first.x
        draw_turn_ring(first.x, first.y, total_w, first.h)
    end

    -- Legality affordance: an illegal card is dimmed and never lifts
    -- under hover. Suppressing the lift signals "not pickable" without
    -- adding extra visual chrome — the dim and the missing rise tell
    -- the player which card the engine would reject. Keyboard focus
    -- can still land on an illegal card so Enter surfaces the
    -- localised toast explaining the rule break.
    local lift_hovered_index
    if hovered_card_index then
        local legality = self_hand.card_legality and self_hand.card_legality[hovered_card_index]
        if legality ~= false then
            lift_hovered_index = hovered_card_index
        end
    end
    local lifted_index = lift_hovered_index or focused_card_index
    -- Draw cards from outside-in so the lifted (hovered or focused)
    -- card stays on top regardless of array order.
    for i = 1, count do
        if i ~= lifted_index then
            local card = self_hand.cards[i]
            local r = card_rects[i]
            local legality = self_hand.card_legality and self_hand.card_legality[i]
            cards.draw_face_up(card, r.x, r.y, r.w, r.h)
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

    -- Phase 3.6 penalty house-rules: when zero_tricks or cross is
    -- active the per-seat row needs an extra line per active counter
    -- below the optional state line. The view-model only sets
    -- `entry.bolts` / `entry.crosses` when the matching toggle is on,
    -- so we can scan once to decide the row height.
    -- Phase 3.7 adds two more counters: no-win streak and barrel
    -- falls. Same scan-once-then-add-line-height pattern.
    local has_bolts, has_crosses, has_write_offs = false, false, false
    local has_no_win, has_barrel_falls = false, false
    for _, entry in ipairs(view.scoreboard) do
        if entry.bolts then
            has_bolts = true
        end
        if entry.crosses then
            has_crosses = true
        end
        if entry.write_offs then
            has_write_offs = true
        end
        if entry.no_win then
            has_no_win = true
        end
        if entry.barrel_falls then
            has_barrel_falls = true
        end
    end

    local row_y = region.y + 36
    local row_h = 32
    if has_bolts then
        row_h = row_h + 14
    end
    if has_crosses then
        row_h = row_h + 14
    end
    if has_write_offs then
        row_h = row_h + 14
    end
    if has_no_win then
        row_h = row_h + 14
    end
    if has_barrel_falls then
        row_h = row_h + 14
    end
    for _, entry in ipairs(view.scoreboard) do
        local label
        if entry.player == view.turn_player and view.hands[entry.player].perspective == "self" then
            label = active_seat_label()
        else
            label = t("scene.table.player_label.other", { n = entry.player })
        end

        if entry.sits_out then
            love.graphics.setColor(SITS_OUT_DIM)
        elseif entry.is_winner then
            love.graphics.setColor(1.0, 0.85, 0.30, 1)
        elseif entry.is_turn then
            love.graphics.setColor(TURN_HIGHLIGHT)
        else
            love.graphics.setColor(LABEL_COLOR)
        end
        love.graphics.print(label, region.x + 12, row_y)

        if entry.sits_out then
            love.graphics.setColor(SITS_OUT_DIM)
            love.graphics.print(t("scene.table.seat.sits_out"), region.x + 12, row_y + 14)
        else
            love.graphics.setColor(VALUE_COLOR)
            love.graphics.print(tostring(entry.total), region.x + region.w - 56, row_y)
            if entry.barrel.on_barrel then
                love.graphics.setColor(0.95, 0.75, 0.30, 1)
                local hint = t("scene.table.scoreboard.barrel", {
                    n = entry.barrel.deals_remaining or 0,
                })
                love.graphics.print(hint, region.x + 12, row_y + 14)
            elseif entry.reverse_barrel and entry.reverse_barrel.on then
                -- Phase 3.6 reverse-barrel marker. Distinct red tint
                -- so the symmetric state machine reads instantly
                -- against the gold forward-barrel marker.
                love.graphics.setColor(0.85, 0.30, 0.30, 1)
                local hint = t("scene.table.scoreboard.reverse_barrel", {
                    n = entry.reverse_barrel.deals_remaining or 0,
                })
                love.graphics.print(hint, region.x + 12, row_y + 14)
            elseif entry.pit_locked then
                -- Phase 3.6 pit-lock-in marker. Distinct teal tint to
                -- separate it from the barrel and reverse-barrel
                -- markers.
                love.graphics.setColor(0.30, 0.75, 0.75, 1)
                love.graphics.print(
                    t("scene.table.scoreboard.pit_locked"),
                    region.x + 12,
                    row_y + 14
                )
            elseif entry.eliminated then
                love.graphics.setColor(0.55, 0.30, 0.30, 1)
                love.graphics.print(
                    t("scene.table.scoreboard.eliminated"),
                    region.x + 12,
                    row_y + 14
                )
            end

            -- Phase 3.6 penalty house-rules: bolt and cross counters.
            -- Always rendered below the optional state line so the
            -- "1 / 3" progress is visible at a glance. Hidden when
            -- the matching toggle is off (entry.bolts/crosses nil).
            local extra_y = row_y + 28
            if entry.bolts then
                love.graphics.setColor(0.85, 0.55, 0.30, 1)
                love.graphics.print(
                    t("scene.table.scoreboard.bolts_counter", {
                        count = entry.bolts.count,
                        threshold = entry.bolts.threshold,
                    }),
                    region.x + 12,
                    extra_y
                )
                extra_y = extra_y + 14
            end
            if entry.crosses then
                love.graphics.setColor(0.75, 0.40, 0.55, 1)
                love.graphics.print(
                    t("scene.table.scoreboard.crosses_counter", {
                        count = entry.crosses.count,
                        threshold = entry.crosses.threshold,
                    }),
                    region.x + 12,
                    extra_y
                )
                extra_y = extra_y + 14
            end
            -- Phase 3.7 write-off counter. Distinct blue-grey tint so
            -- the every-third-write-off progress reads independently
            -- from the orange bolt and purple cross counters.
            if entry.write_offs then
                love.graphics.setColor(0.45, 0.60, 0.80, 1)
                love.graphics.print(
                    t("scene.table.scoreboard.write_off_counter", {
                        count = entry.write_offs.count,
                        threshold = entry.write_offs.threshold,
                    }),
                    region.x + 12,
                    extra_y
                )
                extra_y = extra_y + 14
            end
            -- Phase 3.7 no-win streak counter. Muted teal sets it
            -- apart from the other counters at a glance.
            if entry.no_win then
                love.graphics.setColor(0.40, 0.70, 0.65, 1)
                love.graphics.print(
                    t("scene.table.scoreboard.no_win_counter", {
                        count = entry.no_win.count,
                        threshold = entry.no_win.threshold,
                    }),
                    region.x + 12,
                    extra_y
                )
                extra_y = extra_y + 14
            end
            -- Phase 3.7 barrel-fall counter. Warm red — rare event,
            -- and matches the falling-off-the-barrel mood.
            if entry.barrel_falls then
                love.graphics.setColor(0.85, 0.40, 0.35, 1)
                love.graphics.print(
                    t("scene.table.scoreboard.barrel_fall_counter", {
                        count = entry.barrel_falls.count,
                    }),
                    region.x + 12,
                    extra_y
                )
            end
        end

        local badge_x = region.x + region.w - 28
        if entry.is_dealer then
            draw_dealer_badge(badge_x, row_y - 4)
            badge_x = badge_x - 26
        end
        if entry.side then
            draw_partner_badge(badge_x, row_y - 4, entry.side)
        end

        row_y = row_y + row_h
    end

    -- Phase 3.6 endgame house-rules. Show the active target line at the
    -- bottom of the scoreboard. Under
    -- `endgame.going_over_target == "exact_only"` an extra "must land
    -- exactly" line sits above the target.
    if view.effective_target then
        row_y = row_y + 4
        love.graphics.setColor(SCOREBOARD_BORDER)
        love.graphics.line(region.x + 12, row_y, region.x + region.w - 12, row_y)
        row_y = row_y + 6
        if view.exact_only_indicator then
            love.graphics.setColor(0.95, 0.75, 0.30, 1)
            love.graphics.print(
                t("scene.table.scoreboard.exact_only", { target = view.effective_target }),
                region.x + 12,
                row_y
            )
            row_y = row_y + 18
        end
        love.graphics.setColor(LABEL_COLOR)
        love.graphics.print(
            t("scene.table.scoreboard.effective_target", { target = view.effective_target }),
            region.x + 12,
            row_y
        )
        row_y = row_y + row_h
    end

    if view.partnership and view.partnership.totals then
        row_y = row_y + 4
        love.graphics.setColor(SCOREBOARD_BORDER)
        love.graphics.line(region.x + 12, row_y, region.x + region.w - 12, row_y)
        row_y = row_y + 6
        for side = 1, 2 do
            local label = t("scene.table.partnership.score_row", { n = side })
            love.graphics.setColor(LABEL_COLOR)
            love.graphics.print(label, region.x + 12, row_y)
            love.graphics.setColor(VALUE_COLOR)
            love.graphics.print(
                tostring(view.partnership.totals[side] or 0),
                region.x + region.w - 56,
                row_y
            )
            draw_partner_badge(region.x + region.w - 28, row_y - 4, side)
            row_y = row_y + row_h
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

local function lay_out_panel_buttons(self, regions)
    local count = #self._panel_buttons
    if count == 0 then
        return
    end
    local centre = regions.centre
    -- Available width for the row, leaving 8px breathing room on each
    -- side of the centre band.
    local available = centre.w - 16
    if available < 1 then
        available = centre.w
    end
    local btn_w = PANEL_BTN_W
    local desired = count * btn_w + (count - 1) * PANEL_BTN_GAP
    if desired > available then
        -- Shrink button width proportionally so the whole row still
        -- fits on a narrow window. Touch-target floor wins on the
        -- smallest screens — the row will overflow before MIN_HIT_TARGET
        -- shrinks; that's the correct tradeoff (better to scroll the
        -- window than to ship sub-touch buttons).
        btn_w = math.floor((available - (count - 1) * PANEL_BTN_GAP) / count)
        if btn_w < layout.MIN_HIT_TARGET then
            btn_w = layout.MIN_HIT_TARGET
        end
    end
    local total_w = count * btn_w + (count - 1) * PANEL_BTN_GAP
    local start_x = centre.x + math.max(8, math.floor((centre.w - total_w) * 0.5))
    local y = centre.y + centre.h - PANEL_BTN_H - 8
    for i, b in ipairs(self._panel_buttons) do
        b:set_rect(start_x + (i - 1) * (btn_w + PANEL_BTN_GAP), y, btn_w, PANEL_BTN_H)
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
    if not view or not view.talon_phase then
        return
    end
    local status = view.talon_phase.status
    if status == "awaiting_pass" then
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
        return
    end
    if status == "awaiting_discard" then
        love.graphics.setColor(LABEL_COLOR)
        love.graphics.print(
            t("scene.table.talon.discard_prompt"),
            regions.hand.x + 8,
            regions.hand.y - 22
        )
        love.graphics.setColor(1, 1, 1, 1)
        return
    end
end

-- Pick the localised deal-done banner key for the given view-model. The
-- legacy reasons "scored" and "all_pass" map to existing keys; the
-- all-pass house-rule reasons (pass_out, raspassy_scored) reuse the
-- shared `scene.table.all_pass_banner.*` namespace via the view-model's
-- `all_pass_banner.mode` field.
local function deal_done_banner_key(view)
    local payload = view.deal_done
    if not payload then
        return nil
    end
    if payload.reason == "scored" then
        return "scene.table.deal_done.scored"
    end
    if payload.reason == "write_off" then
        return "scene.table.deal_done.write_off"
    end
    if view.all_pass_banner then
        local mode = view.all_pass_banner.mode
        if mode == "redeal" then
            return "scene.table.all_pass_banner.redeal"
        end
        if mode == "pass_out" then
            return "scene.table.all_pass_banner.pass_out"
        end
        if mode == "raspassy" then
            return "scene.table.all_pass_banner.raspassy"
        end
    end
    -- Legacy fallback for older save-game payloads without the banner
    -- view-model field.
    if payload.reason == "all_pass" then
        return "scene.table.deal_done.all_pass"
    end
    return "scene.table.deal_done.scored"
end

local function draw_deal_done_banner(view, regions)
    if not view or not view.deal_done then
        return
    end
    local centre = regions.centre
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", centre.x, centre.y, centre.w, centre.h)
    love.graphics.setColor(1, 1, 1, 1)
    local key = deal_done_banner_key(view)
    if key then
        love.graphics.print(t(key), centre.x + 24, centre.y + 24)
    end
    local cursor_y = centre.y + 50
    if view.deal_done.running_totals then
        local totals = view.deal_done.running_totals
        for i, total in ipairs(totals) do
            love.graphics.print(
                t("scene.table.player_label.other", { n = i }) .. " " .. tostring(total),
                centre.x + 24,
                cursor_y
            )
            cursor_y = cursor_y + 18
        end
    end
    -- Phase 3.6 score-breakdown rows. One row per non-zero bonus /
    -- penalty contributor (marriage, half-marriage capture, ace
    -- marriage, last-trick, slam, slam-against, failed-contract
    -- distribution, actual-points override, pooled-defender,
    -- dump-truck reset, pit-lock-in cap, overshoot penalty,
    -- tiebreaker-continuation banner). Future-Phase-5.1 will replace
    -- the static text with an enter animation per row.
    local breakdown = view.deal_done.score_breakdown
    if breakdown and #breakdown > 0 then
        cursor_y = cursor_y + 12
        for _, row in ipairs(breakdown) do
            local text
            if row.kind == "tiebreaker_continuation" then
                text = t(row.label_key, { new = row.new_target })
            else
                text = t(row.label_key) .. " " .. tostring(row.total)
            end
            love.graphics.print(text, centre.x + 24, cursor_y)
            cursor_y = cursor_y + 18
        end
    end
    -- Phase 3.6 declarer_rounding_before_contract_check = "off":
    -- inline "(raw X, rounded Y)" indicator showing how the strict
    -- rule applied to the declarer's check value.
    local strict = view.deal_done.declarer_rounding_strict
    if strict then
        cursor_y = cursor_y + 6
        love.graphics.print(
            t("scene.table.scoreboard.declarer_rounding_strict_suffix", {
                raw = strict.raw,
                rounded = strict.rounded,
            }),
            centre.x + 24,
            cursor_y
        )
    end
end

-- Persistent misdeal banner. Sits above the centre band so it stays
-- visible across the auction phase the misdeal redealt into.
local function draw_misdeal_banner(view, regions)
    if not view or not view.misdeal_banner then
        return
    end
    local mb = view.misdeal_banner
    local key
    if mb.handling == "soft_penalty" then
        key = "scene.table.misdeal_banner.soft_penalty"
    elseif mb.handling == "flat_penalty" then
        key = "scene.table.misdeal_banner.flat_penalty"
    else
        key = "scene.table.misdeal_banner.standard"
    end
    local centre = regions.centre
    local y = centre.y - 26
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", centre.x, y, centre.w, 22)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(t(key, { dealer = mb.dealer, penalty = mb.penalty }), centre.x + 12, y + 4)
end

-- Phase 3.8 cut-deck banner. Renders the latest entry from the
-- per-deal cut-deck log: the bad-cut counter while the ritual is in
-- progress, the threshold-penalty notification afterwards. Sits in
-- the same lane as draw_misdeal_banner.
local function draw_cut_deck_banner(view, regions)
    if not view then
        return
    end
    if not view.cut_phase and not view.cut_deck_banner then
        return
    end
    local centre = regions.centre
    local y = centre.y - 26
    if view.cut_phase then
        local cp = view.cut_phase
        love.graphics.setColor(0.30, 0.20, 0.45, 0.85)
        love.graphics.rectangle("fill", centre.x, y, centre.w, 22)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print(
            t("scene.table.cut.bad_cut_indicator", {
                count = cp.bad_cut_count,
                threshold = cp.threshold,
            }),
            centre.x + 12,
            y + 4
        )
        return
    end
    local b = view.cut_deck_banner
    if b.kind ~= "threshold_penalty" then
        return
    end
    love.graphics.setColor(0.55, 0.20, 0.20, 0.85)
    love.graphics.rectangle("fill", centre.x, y, centre.w, 22)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(
        t("scene.table.cut.threshold_penalty_banner", {
            seat = b.dealer,
            amount = -b.amount,
        }),
        centre.x + 12,
        y + 4
    )
end

-- Phase 3.6 forced-dealer-bid banner. Sits in the same lane as
-- draw_misdeal_banner; informational, no input gate.
local function draw_dealer_forced_banner(view, regions)
    if not view or not view.auction or not view.auction.dealer_forced_banner then
        return
    end
    local b = view.auction.dealer_forced_banner
    local centre = regions.centre
    local y = centre.y - 26
    love.graphics.setColor(0.20, 0.30, 0.50, 0.85)
    love.graphics.rectangle("fill", centre.x, y, centre.w, 22)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(
        t("scene.table.auction.dealer_forced_banner", { seat = b.dealer_seat, amount = b.amount }),
        centre.x + 12,
        y + 4
    )
end

-- Phase 3.6 opening-game / golden-deal banner. Sits in the same lane
-- as draw_dealer_forced_banner: informational, no input gate. Renders
-- only during the opening N forced-120 deals.
local function draw_golden_deal_banner(view, regions)
    if not view or not view.golden_deal_banner then
        return
    end
    local b = view.golden_deal_banner
    local centre = regions.centre
    local y = centre.y - 50
    love.graphics.setColor(0.85, 0.65, 0.10, 0.85)
    love.graphics.rectangle("fill", centre.x, y, centre.w, 44)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(
        t("scene.table.golden_deal.banner", { seat = b.seat, amount = b.amount }),
        centre.x + 12,
        y + 4
    )
    if b.deal_index and b.opening_count then
        love.graphics.print(
            t("scene.table.golden_deal.subtitle", {
                deal = b.deal_index,
                count = b.opening_count,
            }),
            centre.x + 12,
            y + 22
        )
    end
end

-- Phase 3.6 contract-multiplier badge. Surfaces ×2 / ×4 / ×8 next to
-- the panel label whenever blind / contra / redouble is active.
local function draw_contract_multiplier_badge(self, view, regions)
    local _ = view
    local session = self:_session()
    if not session or not session.contract_multiplier then
        return
    end
    local mult = session:contract_multiplier()
    if not mult or mult <= 1 then
        return
    end
    local centre = regions.centre
    local y = centre.y - 26
    love.graphics.setColor(0.50, 0.30, 0.10, 0.85)
    love.graphics.rectangle("fill", centre.x + centre.w - 60, y, 60, 22)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(
        t("scene.table.auction.contract_multiplier_badge", { n = mult }),
        centre.x + centre.w - 50,
        y + 4
    )
end

-- Phase 3.6 bid-panel hints. Renders the "(no marriage)" subscript
-- when bids ≥ 120 are disabled and the "Take 100 (negative score)"
-- banner when the seat is locked.
local function draw_bidding_status_hints(view, regions)
    if not view or not view.auction then
        return
    end
    local centre = regions.centre
    if view.auction.disabled_bid_amounts then
        love.graphics.setColor(0.7, 0.7, 0.7, 1)
        love.graphics.print(
            t("scene.table.auction.bid_disabled_no_marriage"),
            centre.x + 12,
            centre.y - 50
        )
    end
    if view.auction.locked_bid_amount then
        love.graphics.setColor(0.7, 0.5, 0.5, 1)
        love.graphics.print(
            t("scene.table.auction.locked_to_minimum", { amount = view.auction.locked_bid_amount }),
            centre.x + 12,
            centre.y - 70
        )
    end
end

-- In-progress raspassy banner. Active during the raspassy_play phase so
-- the player can see they are in a no-contract reverse-scoring deal.
local function draw_raspassy_status_banner(view, regions)
    if not view or not view.raspassy_active then
        return
    end
    local centre = regions.centre
    local y = centre.y - 26
    love.graphics.setColor(0.30, 0.10, 0.10, 0.85)
    love.graphics.rectangle("fill", centre.x, y, centre.w, 22)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(t("scene.table.all_pass_banner.raspassy"), centre.x + 12, y + 4)
end

-- Phase 3.6 special-contracts banner. Surfaces the active named
-- contract (mizère / slam / open hand) above the table during the
-- talon and tricks phases so every seat can see what's been
-- declared. The view-model carries the i18n key so this scene only
-- routes through `t()`.
local function draw_active_contract_banner(view, regions)
    if not view or not view.active_contract_banner then
        return
    end
    local centre = regions.centre
    local y = centre.y - 72
    love.graphics.setColor(0.20, 0.10, 0.45, 0.85)
    love.graphics.rectangle("fill", centre.x, y, centre.w, 22)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(
        t(view.active_contract_banner.i18n_key, { value = view.active_contract_banner.value }),
        centre.x + 12,
        y + 4
    )
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

local function draw_redeal_modal(self, w, h)
    if self._modal ~= "redeal" or not self._redeal_payload then
        return
    end
    love.graphics.setColor(MODAL_DIM)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local panel_w, panel_h = 520, 240
    local px = math.floor(w * 0.5 - panel_w * 0.5)
    local py = math.floor(h * 0.5 - panel_h * 0.5)
    love.graphics.setColor(MODAL_BG)
    love.graphics.rectangle("fill", px, py, panel_w, panel_h)
    love.graphics.setColor(1, 1, 1, 1)

    local payload = self._redeal_payload
    local body_key = "scene.table.redeal_prompt.body." .. tostring(payload.kind)
    if payload.forced then
        love.graphics.print(
            t("scene.table.redeal_prompt.forced_banner", { seat = payload.seat }),
            px + 32,
            py + 40
        )
    else
        love.graphics.print(t("scene.table.redeal_prompt.title"), px + 32, py + 40)
    end
    love.graphics.print(t(body_key, { seat = payload.seat }), px + 32, py + 80)

    if payload.forced or #self._modal_buttons == 0 then
        return
    end

    local btn_w, btn_h, btn_gap = 220, 48, 24
    local total_w = btn_w * 2 + btn_gap
    local btn_y = py + panel_h - btn_h - 28
    local left_x = px + math.floor(panel_w * 0.5 - total_w * 0.5)
    self._modal_buttons[1]:set_rect(left_x, btn_y, btn_w, btn_h)
    self._modal_buttons[2]:set_rect(left_x + btn_w + btn_gap, btn_y, btn_w, btn_h)
    for _, b in ipairs(self._modal_buttons) do
        b:draw()
    end
end

local function draw_bad_talon_modal(self, w, h)
    if self._modal ~= "bad_talon" or not self._bad_talon_payload then
        return
    end
    love.graphics.setColor(MODAL_DIM)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local panel_w, panel_h = 520, 240
    local px = math.floor(w * 0.5 - panel_w * 0.5)
    local py = math.floor(h * 0.5 - panel_h * 0.5)
    love.graphics.setColor(MODAL_BG)
    love.graphics.rectangle("fill", px, py, panel_w, panel_h)
    love.graphics.setColor(1, 1, 1, 1)

    local payload = self._bad_talon_payload
    love.graphics.print(t("scene.table.bad_talon_prompt.title"), px + 32, py + 40)
    love.graphics.print(
        t("scene.table.bad_talon_prompt.body", { points = payload.points }),
        px + 32,
        py + 80
    )

    if #self._modal_buttons == 0 then
        return
    end

    local btn_w, btn_h, btn_gap = 220, 48, 24
    local total_w = btn_w * 2 + btn_gap
    local btn_y = py + panel_h - btn_h - 28
    local left_x = px + math.floor(panel_w * 0.5 - total_w * 0.5)
    self._modal_buttons[1]:set_rect(left_x, btn_y, btn_w, btn_h)
    self._modal_buttons[2]:set_rect(left_x + btn_w + btn_gap, btn_y, btn_w, btn_h)
    for _, b in ipairs(self._modal_buttons) do
        b:draw()
    end
end

local function draw_rebuy_modal(self, w, h)
    if self._modal ~= "rebuy" or not self._rebuy_payload then
        return
    end
    love.graphics.setColor(MODAL_DIM)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local panel_w, panel_h = 520, 240
    local px = math.floor(w * 0.5 - panel_w * 0.5)
    local py = math.floor(h * 0.5 - panel_h * 0.5)
    love.graphics.setColor(MODAL_BG)
    love.graphics.rectangle("fill", px, py, panel_w, panel_h)
    love.graphics.setColor(1, 1, 1, 1)

    local payload = self._rebuy_payload
    love.graphics.print(t("scene.table.rebuy_prompt.title"), px + 32, py + 40)
    love.graphics.print(
        t("scene.table.rebuy_prompt.body", {
            seat = payload.seat,
            value = payload.contract,
        }),
        px + 32,
        py + 80
    )

    if #self._modal_buttons == 0 then
        return
    end

    local btn_w, btn_h, btn_gap = 220, 48, 24
    local total_w = btn_w * 2 + btn_gap
    local btn_y = py + panel_h - btn_h - 28
    local left_x = px + math.floor(panel_w * 0.5 - total_w * 0.5)
    self._modal_buttons[1]:set_rect(left_x, btn_y, btn_w, btn_h)
    self._modal_buttons[2]:set_rect(left_x + btn_w + btn_gap, btn_y, btn_w, btn_h)
    for _, b in ipairs(self._modal_buttons) do
        b:draw()
    end
end

-- Phase 3.9 write-off prompt modal: dimmed overlay + 520×240 panel.
-- Title + body line + Play / Write-off buttons centred at the bottom.
local function draw_write_off_prompt_modal(self, w, h)
    if self._modal ~= "write_off_prompt" or not self._write_off_prompt_payload then
        return
    end
    love.graphics.setColor(MODAL_DIM)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local panel_w, panel_h = 520, 240
    local px = math.floor(w * 0.5 - panel_w * 0.5)
    local py = math.floor(h * 0.5 - panel_h * 0.5)
    love.graphics.setColor(MODAL_BG)
    love.graphics.rectangle("fill", px, py, panel_w, panel_h)
    love.graphics.setColor(1, 1, 1, 1)

    local payload = self._write_off_prompt_payload
    love.graphics.print(t("scene.table.write_off_prompt.title"), px + 32, py + 40)
    local body_key
    if payload.split_mode == "half_to_each" then
        body_key = "scene.table.write_off_prompt.body.half_to_each"
    else
        body_key = "scene.table.write_off_prompt.body.equal_split"
    end
    love.graphics.print(
        t(body_key, {
            bid = payload.bid,
            share = payload.share or 0,
        }),
        px + 32,
        py + 80
    )

    if #self._modal_buttons == 0 then
        return
    end

    local btn_w, btn_h, btn_gap = 220, 48, 24
    local total_w = btn_w * 2 + btn_gap
    local btn_y = py + panel_h - btn_h - 28
    local left_x = px + math.floor(panel_w * 0.5 - total_w * 0.5)
    self._modal_buttons[1]:set_rect(left_x, btn_y, btn_w, btn_h)
    self._modal_buttons[2]:set_rect(left_x + btn_w + btn_gap, btn_y, btn_w, btn_h)
    for _, b in ipairs(self._modal_buttons) do
        b:draw()
    end
end

local function draw_privacy_curtain(self, w, h)
    if not self._curtain or not self._curtain_button then
        return
    end
    -- Full-opacity backdrop — full screen, drawn last, before any
    -- buttons. The active seat's hand renders behind this rectangle but
    -- alpha 1 hides it entirely.
    love.graphics.setColor(CURTAIN_BG)
    love.graphics.rectangle("fill", 0, 0, w, h)

    local panel_w, panel_h = 480, 220
    local px = math.floor(w * 0.5 - panel_w * 0.5)
    local py = math.floor(h * 0.5 - panel_h * 0.5)
    love.graphics.setColor(MODAL_BG)
    love.graphics.rectangle("fill", px, py, panel_w, panel_h)

    love.graphics.setColor(1, 1, 1, 1)
    local prompt = t("scene.table.privacy.prompt", { n = self._curtain.for_seat })
    local subtitle = t("scene.table.privacy.subtitle")
    love.graphics.printf(prompt, px + 24, py + 48, panel_w - 48, "center")
    love.graphics.printf(subtitle, px + 24, py + 84, panel_w - 48, "center")

    local btn_w, btn_h = 200, 48
    local btn_x = px + math.floor(panel_w * 0.5 - btn_w * 0.5)
    local btn_y = py + panel_h - btn_h - 28
    self._curtain_button:set_rect(btn_x, btn_y, btn_w, btn_h)
    self._curtain_button:draw()
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

-- Phase 4.1: render the "Bot N thinking…" banner while the driver is
-- holding a pending decision. Sits at the top of the centre region so
-- it never collides with the toast (bottom) or the panel (below).
local function draw_bot_thinking_banner(self, regions)
    if not self._bot_driver or not self._bot_driver:is_thinking() then
        return
    end
    local seat = self._bot_driver:thinking_seat()
    if not seat then
        return
    end
    local centre = regions.centre
    local text = t("scene.table.bot_thinking", { n = seat })
    local banner_w = math.min(centre.w - 32, 320)
    local banner_h = 28
    local x = centre.x + math.floor((centre.w - banner_w) * 0.5)
    local y = centre.y + 4
    love.graphics.setColor(TOAST_BG)
    love.graphics.rectangle("fill", x, y, banner_w, banner_h)
    love.graphics.setColor(TOAST_FG)
    love.graphics.print(text, x + 12, y + 6)
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
    -- Phase 4.1: drive bot seats. The driver self-throttles via its
    -- own clock so a "thinking…" indicator can render between the
    -- decision and the apply. No-op if seat_kinds is nil (no bot
    -- seats configured) or the active seat is human.
    if self._bot_driver and self._seat_kinds then
        local session = self:_session()
        if session then
            self._bot_driver:tick(session, self._seat_kinds, self._seat_difficulties)
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
    self:_apply_curtain_trigger()
    self:_apply_redeal_modal_trigger(self._view_model)
    self:_apply_bad_talon_modal_trigger(self._view_model)
    self:_apply_rebuy_modal_trigger(self._view_model)
    self:_apply_write_off_prompt_modal_trigger(self._view_model)
    self:_rebuild_panel_if_needed(self._view_model)

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
    -- Phase 3.6 banners. The deal_done banner renders first so its
    -- backdrop sits *under* the Next-deal button the panel renders
    -- next. The misdeal and raspassy status banners are persistent
    -- one-line indicators above the centre band; they don't block
    -- input on the panel area.
    draw_misdeal_banner(self._view_model, regions)
    draw_cut_deck_banner(self._view_model, regions)
    draw_raspassy_status_banner(self._view_model, regions)
    draw_active_contract_banner(self._view_model, regions)
    draw_dealer_forced_banner(self._view_model, regions)
    draw_golden_deal_banner(self._view_model, regions)
    draw_contract_multiplier_badge(self, self._view_model, regions)
    draw_bidding_status_hints(self._view_model, regions)
    draw_deal_done_banner(self._view_model, regions)

    lay_out_panel_buttons(self, regions)
    self:_sync_focus_marks()
    draw_panel_buttons(self)

    self._back_button:set_rect(
        regions.menu_button.x,
        regions.menu_button.y,
        regions.menu_button.w,
        regions.menu_button.h
    )
    self._back_button:draw()

    draw_toast(self, regions)
    draw_bot_thinking_banner(self, regions)
    draw_marriage_modal(self, w, h)
    draw_redeal_modal(self, w, h)
    draw_bad_talon_modal(self, w, h)
    draw_rebuy_modal(self, w, h)
    draw_write_off_prompt_modal(self, w, h)
    -- Privacy curtain renders last so its full-opacity backdrop sits
    -- above every other layer, including the marriage and redeal
    -- modals — those states are mutually exclusive in practice.
    draw_privacy_curtain(self, w, h)

    love.graphics.setColor(1, 1, 1, 1)
end

-- Hit-tests + input dispatch -------------------------------------------

local function rect_contains(rect, x, y)
    return x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h
end

function M:_active_buttons()
    if self._curtain and self._curtain_button then
        return { self._curtain_button }
    end
    local modal = self._modal -- i18n-ok: modal enum
    if
        modal == "marriage" -- i18n-ok
        or modal == "redeal" -- i18n-ok
        or modal == "bad_talon" -- i18n-ok
        or modal == "rebuy" -- i18n-ok
        or modal == "write_off_prompt" -- i18n-ok
    then
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
    -- Phase 3.9 follow-up: card taps also fire during the pre-tricks
    -- write-off offer, where they implicitly accept play (engine
    -- auto-clears the offer in the pass mutator) and pass the card in
    -- a single gesture.
    local pass_phase = view.phase == "talon" -- i18n-ok: phase enum
        or view.phase == "awaiting_write_off_decision" -- i18n-ok: phase enum
    if pass_phase and awaiting then
        local target = talon_phase.pass_target_seat
        if target then
            self:_do_pass_talon(target, entry.card)
        end
        return
    end
    if
        pass_phase
        and talon_phase
        and talon_phase.status == "awaiting_discard" -- i18n-ok
    then
        self:_do_discard_talon(entry.card)
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
    if view.phase == "raspassy_play" then
        local turn = view.turn_player
        if turn and view.hands[turn] and view.hands[turn].perspective == "self" then
            -- Marriages are disabled in raspassy; card plays go straight
            -- to the tricks engine.
            self:_do_play(turn, entry.card)
        end
    end
end

function M:mousemoved(x, y, _dx, _dy)
    self._input_mode = "mouse" -- i18n-ok
    for _, b in ipairs(self:_active_buttons()) do
        b:on_mousemoved(x, y)
    end
    -- Card hover — purely visual; keyboard focus stays separate.
    -- Only track hover when the hand is interactive. During auction
    -- the cards are visible but the player should be choosing a bid,
    -- not their card; hovering them suggests playability that isn't
    -- there yet. The privacy curtain hides the hand entirely, so no
    -- hover tracking either.
    if self._curtain then
        self._hovered_card_index = nil
    elseif self:_hand_is_interactive() then
        local _, idx = self:_card_hit(x, y)
        self._hovered_card_index = idx
    else
        self._hovered_card_index = nil
    end
end

function M:mousepressed(x, y, button)
    if button ~= 1 then
        return
    end
    if self._curtain then
        -- Tap-anywhere dismisses the curtain. Route to the Ready
        -- button first so it can flip its pressed state for visual
        -- feedback; the release handler clears the curtain regardless
        -- of where the click landed.
        if self._curtain_button then
            self._curtain_button:on_mousepressed(x, y, button)
        end
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
    -- Fall through to card hit-test only when no button arms AND the
    -- hand is interactive (auction is bid-or-pass — cards aren't
    -- pickable yet). Card rects are rebuilt every draw, so we cache
    -- the *card identity* (suit + rank) rather than the rect entry —
    -- release on the next frame would otherwise see a different
    -- table reference even though the card under the cursor hasn't
    -- changed.
    if self:_hand_is_interactive() then
        local entry = self:_card_hit(x, y)
        if entry then
            self._pending_card = { suit = entry.card.suit, rank = entry.card.rank }
            return
        end
    end
    -- Click landed in dead space. Drop the keyboard focus ring so the
    -- next yellow outline only surfaces when the user explicitly navs
    -- back in with Tab or arrows.
    self._focus_index = nil
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
    if self._curtain then
        local btn = self._curtain_button
        if btn then
            -- Try the button rect first for the standard release-inside
            -- semantics (it fires its on_press and clears the curtain
            -- via _close_curtain). If the release lands outside the
            -- rect we still want tap-anywhere dismissal, so close the
            -- curtain manually.
            local fired = btn:on_mousereleased(x, y, button)
            if not fired then
                btn.pressed = false
                self:_close_curtain()
            end
        else
            self:_close_curtain()
        end
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
    if self._curtain then
        if key == "escape" then -- i18n-ok
            self:_return_to_menu()
        elseif key == "tab" then -- i18n-ok
            -- Single-element focus group; advance is a visual no-op
            -- but keeps the focus ring lit if the user presses Tab.
            if self._curtain_focus then
                self._curtain_focus:advance(shift_held() and -1 or 1)
            end
        elseif key == "return" or key == "space" or key == "kpenter" then -- i18n-ok
            if self._curtain_focus then
                self._curtain_focus:activate()
            else
                self:_close_curtain()
            end
        end
        return
    end
    if self._modal == "marriage" then -- i18n-ok: modal enum
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
    if self._modal == "redeal" then -- i18n-ok: modal enum
        -- Forced offers render no buttons — the session auto-applies
        -- the redeal on the next frame. There's nothing to focus, so
        -- key input is a no-op until the modal closes itself.
        if not self._modal_focus then
            return
        end
        if key == "tab" then -- i18n-ok
            self._modal_focus:advance(shift_held() and -1 or 1)
        elseif key == "left" or key == "up" then -- i18n-ok
            self._modal_focus:advance(-1)
        elseif key == "right" or key == "down" then -- i18n-ok
            self._modal_focus:advance(1)
        elseif key == "return" or key == "space" or key == "kpenter" then -- i18n-ok
            self._modal_focus:activate()
        elseif key == "escape" then -- i18n-ok
            -- Treat Escape as Decline — the offer has to be resolved
            -- before the auction can proceed, and Decline is the safe
            -- "don't redeal, play this hand" branch.
            self:_do_decline_redeal()
            self:_close_redeal_modal()
        end
        return
    end
    if self._modal == "bad_talon" then -- i18n-ok: modal enum
        if not self._modal_focus then
            return
        end
        if key == "tab" then -- i18n-ok
            self._modal_focus:advance(shift_held() and -1 or 1)
        elseif key == "left" or key == "up" then -- i18n-ok
            self._modal_focus:advance(-1)
        elseif key == "right" or key == "down" then -- i18n-ok
            self._modal_focus:advance(1)
        elseif key == "return" or key == "space" or key == "kpenter" then -- i18n-ok
            self._modal_focus:activate()
        elseif key == "escape" then -- i18n-ok
            -- Escape declines: a bad-talon offer has to be resolved
            -- before take_talon, and Decline is the safe
            -- "play this hand" branch.
            self:_do_decline_bad_talon_redeal()
            self:_close_bad_talon_modal()
        end
        return
    end
    if self._modal == "rebuy" then -- i18n-ok: modal enum
        if not self._modal_focus then
            return
        end
        if key == "tab" then -- i18n-ok
            self._modal_focus:advance(shift_held() and -1 or 1)
        elseif key == "left" or key == "up" then -- i18n-ok
            self._modal_focus:advance(-1)
        elseif key == "right" or key == "down" then -- i18n-ok
            self._modal_focus:advance(1)
        elseif key == "return" or key == "space" or key == "kpenter" then -- i18n-ok
            self._modal_focus:activate()
        elseif key == "escape" then -- i18n-ok
            -- Escape passes the rebuy: the head defender's safe branch
            -- is to decline rather than commit to a fixed-contract buy.
            local seat = self._rebuy_payload and self._rebuy_payload.seat
            if seat then
                self:_do_decline_rebuy(seat)
            end
            self:_close_rebuy_modal()
        end
        return
    end
    if key == "escape" then -- i18n-ok
        self:_return_to_menu()
    elseif key == "tab" then -- i18n-ok
        self._input_mode = "keyboard" -- i18n-ok
        self:_advance_focus(shift_held() and -1 or 1)
    elseif key == "left" then -- i18n-ok
        self._input_mode = "keyboard" -- i18n-ok
        self:_advance_within_group(-1)
    elseif key == "right" then -- i18n-ok
        self._input_mode = "keyboard" -- i18n-ok
        self:_advance_within_group(1)
    elseif key == "up" then -- i18n-ok
        self._input_mode = "keyboard" -- i18n-ok
        self:_jump_focus_groups(-1)
    elseif key == "down" then -- i18n-ok
        self._input_mode = "keyboard" -- i18n-ok
        self:_jump_focus_groups(1)
    elseif key == "return" or key == "space" or key == "kpenter" then -- i18n-ok
        self._input_mode = "keyboard" -- i18n-ok
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
