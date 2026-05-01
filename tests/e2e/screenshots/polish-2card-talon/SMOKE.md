# Polish 2-card talon (pass_without_taking) — manual smoke script

Phase 3.6 wires the Polish Tysiąc 2-card talon: `talon.size = 2`,
`talon.distribution = "pass_without_taking"`. Automated specs cover the
engine, dealer, session, view-model, and table-scene paths (see
`tests/spec/core/talon_spec.lua`,
`tests/spec/core/dealing_spec.lua`,
`tests/spec/core/builtins_spec.lua`,
`tests/spec/app/session_talon_variants_spec.lua`,
`tests/spec/app/table_view_model_spec.lua`,
`tests/e2e/journeys/polish_2card_talon_journey_spec.lua`). This
document is a manual smoke script for the rendered affordance.

## Run

```bash
cd /Users/nikita/Projects/thousand
PATH="$PWD/.luarocks/bin:$PATH" love .
```

## Walk-through

### 1. Polish flow — direct pass affordance

1. Main menu → "New game".
2. From the template picker, select `Polish Tysiąc`. (Do **not** clone
   it; the built-in already has `talon.size = 2` and
   `talon.distribution = "pass_without_taking"` wired in.)
3. Drive the auction to completion in 10-step increments (Polish has no
   5-step phase): forehand opens at 100; the next two seats pass.
4. At talon reveal, expect:
   - The talon area renders **2 cards face-up** (not 3).
   - The pre-take panel shows a **single "Pass talon"** button — the
     canonical "Take talon" button must NOT appear.
   - No "Raise to …" / "Keep bid at …" buttons appear at any point —
     Polish skips the post-talon raise entirely.
5. Click "Pass talon". Expect:
   - Both talon cards leave the table area.
   - Each opponent's hand grows by one card.
   - The declarer's hand also grows by one card (the dealer's reserved
     leftover lands at the same moment as the second pass).
   - All three hands now hold **8 cards**.
   - Trick play starts immediately; declarer leads the first trick.
6. Capture as:
   - `01-polish-talon-revealed.png` — pre-pass: 2 talon cards face-up,
     "Pass talon" button visible, no Take/Raise buttons.
   - `02-polish-after-pass.png` — post-pass: empty talon area, three
     8-card hands, trick-play UI active.

### 2. Auction discipline (10-step increments)

1. Same `Polish Tysiąc` template.
2. At the auction screen, attempt to bid `105`. The button is
   disabled / no such bid is offered (only 110, 120 should appear).
3. Bid `110`. Expect it to register.
4. Capture as `03-polish-auction-10-step.png`.

### 3. Compare with canonical Russian (regression check)

1. Quit and start a new game with `Russian Thousand`.
2. Drive the auction the same way.
3. At talon reveal, expect the canonical 3-card talon and the
   "Take talon" button (NOT "Pass talon"). The post-talon raise
   buttons appear after the pass step, exactly as before.
4. No screenshots required — this is just a sanity check that the
   Russian flow is unaffected by the Polish changes.

## What "passes"

A run passes if every screenshot above shows the labelled affordance,
hand sizes, and trick-start state matching the description. If any
state is wrong, stop and file the discrepancy as a follow-up before
considering the task closed.
