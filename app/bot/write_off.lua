-- Phase 3.9: bot decision stub for the pre-tricks write-off prompt.
--
-- Returns "play" unconditionally. Phase 4.5 (bot logic for bidding
-- house rules) replaces this stub with a real hand-strength heuristic.
-- The session does not yet auto-fire the bot; this module exists so
-- the API surface is in place for the Phase 4.5 wiring.
--
-- Algorithm-vs-LLM firewall: this module must never `require("app.llm.*")`.
-- The LLM client cannot influence move selection — it only writes
-- character chat. The CI import-graph lint enforces this.

local M = {}

-- Decide whether the bot declarer accepts or writes off the contract
-- when the pre-tricks write-off prompt opens for them.
--
-- Returns one of:
--   * "play"      — accept the deal and continue into the pass step.
--   * "write_off" — concede the contract per `bidding.write_off_split`.
--
-- The Phase 3.9 stub always returns "play" — the real heuristic lands
-- in Phase 4.5 alongside the rest of the bidding-house-rules bot logic.
function M.choose(_session)
    return "play" -- i18n-ok: action enum, never rendered
end

return M
