-- Reusable keyboard-focus state for a list of buttons. One scene can hold
-- one or more groups (the menu has two: the main column and the abandon
-- modal). The contract every group enforces:
--
--   * On creation, NO button is focused. The focus outline only appears
--     after the first keyboard nav (Tab / arrow key). Clicks do not show
--     the focus outline — they go straight to the button's hover/pressed
--     visual states. This matches the focus-visible idiom in browsers
--     and modern desktop UI.
--
--   * advance(direction) is the one entry point for Tab / arrows / Shift+
--     Tab. direction > 0 advances; direction < 0 retreats. When focus is
--     unset, the first call seeds it on the first or last enabled button.
--
--   * activate() runs the focused button's on_press if it's enabled. A
--     scene's Enter/Space handler delegates straight to this.
--
-- The module is pure Lua — no love.* — so it is unit-testable under
-- busted alongside the other ui/ helpers.

local M = {}

local FocusGroup = {}
FocusGroup.__index = FocusGroup

local function apply_marks(self)
    for _, b in ipairs(self._buttons) do
        b.focused = (b == self._focused)
    end
end

local function index_of(list, item)
    for i, v in ipairs(list) do
        if v == item then
            return i
        end
    end
    return nil
end

-- Build a fresh group around `buttons`. Buttons are the same Button
-- instances the scene already draws — the group only flips their
-- `.focused` flag, never owns them.
function M.new(buttons)
    assert(type(buttons) == "table", "FocusGroup.new: buttons must be a list")
    local self = setmetatable({
        _buttons = buttons,
        _focused = nil,
    }, FocusGroup)
    apply_marks(self)
    return self
end

-- Replace the button list (used when a scene rebuilds its widgets, e.g.
-- the menu after a refresh_enabled_states pass). Focus is dropped — the
-- scene's user has not nav'd into the new list yet. Stale focus marks
-- on the previous list are cleared so a button that left the group does
-- not keep rendering as focused.
function FocusGroup:set_buttons(buttons)
    assert(type(buttons) == "table", "FocusGroup:set_buttons: buttons must be a list")
    for _, b in ipairs(self._buttons) do
        b.focused = false
    end
    self._buttons = buttons
    self._focused = nil
    apply_marks(self)
end

function FocusGroup:focused()
    return self._focused
end

-- Drop focus entirely. Useful when a modal closes or a scene leaves: the
-- next entry should start with no visible focus ring.
function FocusGroup:clear()
    self._focused = nil
    apply_marks(self)
end

-- Move focus by direction (+1 or -1). Skips disabled buttons. If focus
-- is currently nil, seeds it on the first / last enabled button as
-- determined by the direction.
function FocusGroup:advance(direction)
    local list = self._buttons
    if #list == 0 then
        return
    end
    local start
    if self._focused then
        start = index_of(list, self._focused) or 0
    else
        start = direction > 0 and 0 or (#list + 1)
    end
    local i = start
    for _ = 1, #list do
        i = ((i - 1 + direction) % #list) + 1
        if list[i].enabled then
            self._focused = list[i]
            apply_marks(self)
            return
        end
    end
end

-- Run the focused button's on_press if any. No-op if focus is unset or
-- the focused button has been disabled since focus landed there.
function FocusGroup:activate()
    if self._focused and self._focused.enabled then
        self._focused.on_press()
    end
end

-- Direct setter, for scenes that need to seed focus to a specific button
-- when a modal opens (the abandon modal opens with focus on Cancel so
-- pressing Enter dismisses the modal rather than abandoning the game).
function FocusGroup:focus(button)
    if button == nil then
        self:clear()
        return
    end
    self._focused = button
    apply_marks(self)
end

return M
