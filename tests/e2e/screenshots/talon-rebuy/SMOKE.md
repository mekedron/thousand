# Talon rebuy — manual smoke script

Phase 3.6 talon rebuy ships the `talon.rebuy` toggle. Automated unit +
session + e2e specs cover the engine, session, view-model, and
table-scene paths (see `tests/spec/core/talon_spec.lua`,
`tests/spec/app/session_talon_variants_spec.lua`,
`tests/spec/app/table_view_model_spec.lua`,
`tests/e2e/journeys/talon_variants_journey_spec.lua`). This document
is a manual smoke script for the rendered modal.

## Run

```bash
cd /Users/nikita/Projects/thousand
PATH="$PWD/.luarocks/bin:$PATH" love .
```

## Walk-throughs

### 1. Rebuy modal — head defender claims

1. Main menu → "New game".
2. From the template picker, clone `Russian Thousand` and edit it.
3. Set `talon.rebuy = on`. Leave `talon.rebuy_contract_value = 240`.
4. Save and apply the template.
5. Drive the auction to completion (any contract).
6. At talon reveal, expect a modal:
   - Title: "Buy talon at higher contract?"
   - Body: "Player N may take the talon at 240." (N = head defender,
     clockwise from declarer).
   - Buttons: "Buy at 240" / "Pass". Decline (Pass) is keyboard-default.
   - Tab cycles focus; Enter activates; Escape passes.
7. Click "Buy at 240". Expect the modal to close, the scoreboard to
   credit player N as the new declarer at the 240 contract, and the
   declarer's pre-take menu (Take talon) to render for the new
   declarer.
8. Capture as `01-rebuy-modal-claim.png` (modal visible) and
   `02-rebuy-after-claim.png` (post-claim scoreboard + take button).

### 2. Rebuy modal — both defenders pass

1. Same template as above.
2. Drive the auction to completion.
3. At the rebuy modal, click "Pass". Expect the modal to re-render for
   the next defender (clockwise) at the same contract.
4. Click "Pass" again. Expect the modal to close. The original
   declarer keeps the contract; the standard "Take talon" panel
   renders.
5. Capture as `03-rebuy-modal-second-defender.png` and
   `04-rebuy-after-all-pass.png`.

### 3. Rebuy + bad-talon sequencing

1. Edit the template; in addition to `talon.rebuy = on`, set
   `talon.bad_talon_redeal = any_contract`,
   `talon.bad_talon_threshold = 5`.
2. Drive a deal until the talon happens to be low (deterministic seeds
   land this reproducibly; see the test helper for guidance).
3. Expect the bad-talon modal first. Click "Play this hand" (decline).
4. Expect the rebuy modal to appear next. Verify it addresses the head
   defender at the rebuy contract.
5. Capture as `05-bad-talon-then-rebuy.png`.

### 4. Rebuy + concede / buyback gating

1. Edit the template; set `talon.rebuy = on`, `talon.pass_the_talon = on`,
   `talon.buyback = on`.
2. Drive the auction to completion.
3. While the rebuy modal is open: confirm there is no "Concede deal"
   or "Buy back hand" affordance behind the modal (the panel suppresses
   them under the rebuy view-model gate). Capture as
   `06-rebuy-suppresses-concede-buyback.png`.
4. Click "Pass" on each defender's prompt. After both decline, the
   declarer's pre-take menu re-opens with both buttons visible.
   Capture as `07-rebuy-declined-concede-buyback-restored.png`.

## What "passes"

A run passes if every screenshot above shows the labelled affordance,
modal, banner, or visibility state matching the description. If any
state is wrong, stop and file the discrepancy as a follow-up before
considering the task closed.
