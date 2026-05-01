# Talon variants — manual smoke script

Phase 3.6 talon-variants ships six new selectable toggles. Automated
unit + integration + e2e specs cover the engine and view-model paths
(see `tests/spec/core/talon_spec.lua`, `tests/spec/app/session_talon_variants_spec.lua`,
`tests/e2e/journeys/talon_variants_journey_spec.lua`). This document
is a manual smoke script for the rendered UI.

## Run

```bash
cd /Users/nikita/Projects/thousand
PATH="$PWD/.luarocks/bin:$PATH" love .
```

## Walk-throughs

### 1. Concede + Buy back buttons

1. Main menu → "New game".
2. From the template picker, clone `Russian Thousand` and edit it.
3. Set `talon.pass_the_talon = on` and `talon.buyback = on`.
   Set `talon.buyback_penalty = 50` (default).
4. Save and apply the template.
5. Drive the auction to completion (any contract).
6. At talon reveal, expect three buttons in the talon panel:
   "Take talon", "Concede deal", "Buy back hand (-50)".
7. Capture as `01-concede-buyback-buttons.png`.

### 2. Bad-talon redeal modal

1. Edit the same template; set `talon.bad_talon_redeal = any_contract`,
   `talon.bad_talon_threshold = 5`.
2. Reload the game; play deals until the talon happens to be low
   (deterministic seeding via session.seed makes this reproducible
   in spec but not from the menu — the `tests/e2e/journeys/talon_variants_journey_spec.lua`
   pinning is what spec coverage relies on).
3. When the talon shows three 9s (or any < 5 points), expect:
   - A modal titled "Redeal — bad talon"
   - Body "Talon has only 0 card points. Redeal?"
   - Buttons: "Redeal" / "Play this hand"
   - Tab cycles focus, Enter activates, Escape declines.
4. Capture as `02-bad-talon-modal.png`.

### 3. Hidden talon to defenders (minimum-100 contract)

1. Edit the template; set `talon.hidden_on_minimum_100 = minimum_100_only`.
2. Drive a deal where forehand opens at 100 and the others pass
   (declarer = forehand at the floor).
3. After the privacy curtain dismisses to a defender's view, expect
   the talon to render face-down (closed stack, not the three cards).
4. After the privacy curtain dismisses to the declarer's view, expect
   the talon to render face-up.
5. Capture both as `03a-talon-hidden-to-defender.png` and
   `03b-talon-visible-to-declarer.png`.

### 4. Flip-after-first-round

1. Edit the template; set `talon.flip_after_first_round = on`.
2. Start a fresh deal.
3. During the first auction round (each seat acts at most once), expect
   the talon to render face-down (closed stack).
4. After every seat has acted once, on the next bid the talon flips
   face-up.
5. Capture as `04-flip-after-first-round.png`.

### 5. Open-discard

1. Edit the template; set `talon.open_discard = on`.
2. Drive a deal to talon reveal and through declarer take + the two
   passes. After each pass, the card laid in front of the opponent
   should render face-up rather than face-down.
3. Capture as `05-open-discard.png`.

### 6. Custom-template editor renders the new sibling fields

1. Open the template editor.
2. Scroll to the talon section.
3. Expect to see rows for the six new selectable toggles AND three
   sibling number fields:
   - "Buyback penalty" (default 50)
   - "Bad-talon threshold" (default 5)
   - "Re-buy contract value" (default 240)
4. Capture as `06-template-editor-talon-section.png`.

## What "passes"

A run passes if every screenshot above shows the labelled affordance,
modal, banner, or visibility state matching the description. If any
state is wrong, stop and file the discrepancy as a follow-up before
considering the task closed.
