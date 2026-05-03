-- Phase 4.1: read-only view over a Session, used by every bot chooser.
--
-- The bot operates on a SessionView, never on the raw Session, so it
-- cannot reach engine mutators by accident. Only the 13 read-only
-- accessors named in the Phase 4.1 task list are exposed; any other
-- method call falls through the metatable and raises a clear error.
-- The underlying Session is held in a closure, not on the view, so a
-- chooser cannot dig it out via `view._session` either.
--
-- Algorithm-vs-LLM firewall: this module never `require`s `ui.*` or
-- `app.llm.*`. Enforced by tests/spec/lint/firewall_spec.lua.

local M = {}

local READ_ONLY_ACCESSORS = {
    "hands",
    "legal_cards",
    "current_turn",
    "current_phase",
    "current_bid",
    "current_trick",
    "trump",
    "talon_cards",
    "talon_substate",
    "talon_pass_targets",
    "redeal_offer",
    "bad_talon_offer_state",
    "rebuy_offer_state",
    "available_marriages",
    "config",
}

local view_metatable = {
    __index = function(_, key)
        error("SessionView: '" .. tostring(key) .. "' is not exposed", 2)
    end,
}

function M.new(session)
    if session == nil then
        error("SessionView.new: session is required", 2)
    end
    local view = {}
    for _, name in ipairs(READ_ONLY_ACCESSORS) do
        view[name] = function(_, ...)
            return session[name](session, ...)
        end
    end
    return setmetatable(view, view_metatable)
end

M.READ_ONLY_ACCESSORS = READ_ONLY_ACCESSORS

return M
