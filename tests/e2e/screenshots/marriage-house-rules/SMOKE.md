# Marriage house rules — manual smoke script

Phase 3.6 marriage-house-rules ships six new selectable toggles in the
`marriages` section plus two new sibling fields:
`half_marriage_capture_bonus`, `half_marriage_capture_bonus_value`,
`trump_activation_timing`, `marriage_announcement_timing`,
`drowned_marriage`, `ace_marriage`, `ace_marriage_value`,
`one_trump_per_deal`.

Automated unit + integration + e2e specs cover the engine, session,
view-model and table-scene paths (see
`tests/spec/core/marriages_spec.lua`,
`tests/spec/core/scoring_spec.lua`,
`tests/spec/core/tricks_spec.lua`,
`tests/spec/app/session_marriage_variants_spec.lua`,
`tests/e2e/journeys/marriage_variants_journey_spec.lua`).
This document is a manual smoke script for the rendered UI — hand it
to a tester so they can drive the table scene and capture screenshots
that confirm the visual changes.

## Run

```bash
cd /Users/nikita/Projects/thousand
PATH="$PWD/.luarocks/bin:$PATH" love .
```

## Walk-throughs

For every toggle: clone the canonical Russian template, flip the
toggle (and any required sibling), save, apply, and start a new game.
Capture each frame to
`tests/e2e/screenshots/marriage-house-rules/`.

### 1. trump_activation_timing — immediate trump flip

1. Set `marriages.trump_activation_timing = immediate`. Save and
   start a new deal until you reach the tricks phase.
2. Lead the K of a marriage suit; the trump indicator flips on the
   same trick (not the next one). The played K is now trump.
3. Capture as `01-trump-activation-immediate.png`.

### 2. marriage_announcement_timing — hand announcement

1. Set `marriages.marriage_announcement_timing = hand_announcement`.
2. Reach a trick where the leader holds a K-Q marriage. Expect an
   "Announce marriage" button in the tricks panel (the K/Q-tap modal
   is suppressed).
3. Press the button, choose a suit; the bonus posts and trump
   schedules per the active activation timing.
4. Capture as `02-hand-announcement-button.png`.

### 3. marriage_announcement_timing — pre first trick

1. Set `marriages.marriage_announcement_timing = pre_first_trick`.
2. Reach the start of the tricks phase. Expect a pre-first-trick
   modal listing the active seat's eligible suits with "Declare" and
   "Skip" buttons.
3. Walk through every queued seat (declare or skip); the modal
   advances and closes when the queue empties.
4. Capture as `03-pre-first-trick-modal.png`.

### 4. drowned_marriage — retroactive cancel

1. Set `marriages.drowned_marriage = retroactive_cancel`.
2. Declare a hearts marriage and lead the K. An opponent captures the
   K (e.g. with the Ace).
3. Expect a "Marriage drowned in hearts" banner; the bonus row is
   removed from the scoreboard.
4. Capture as `04-drowned-marriage-banner.png`.

### 5. ace_marriage — bonus only

1. Set `marriages.ace_marriage = on`. Set `ace_marriage_value` to
   200 (default).
2. Reach a trick where the leader holds all four Aces. Expect a
   "Declare four aces" button.
3. Press it; the +200 row appears in the deal scoreboard at scoring
   time.
4. Capture as `05-ace-marriage-bonus.png`.

### 6. ace_marriage — sets trump

1. Set `marriages.ace_marriage = sets_trump`.
2. Declare four aces, then lead any Ace; trump flips to that suit
   immediately.
3. Capture as `06-ace-marriage-sets-trump.png`.

### 7. one_trump_per_deal — only first marriage flips trump

1. Set `marriages.one_trump_per_deal = on`.
2. Declare two marriages. The first sets trump; the second posts the
   bonus but trump stays unchanged.
3. Capture as `07-one-trump-per-deal.png`.

### 8. half_marriage_capture_bonus — defender captures K+Q

1. Set `marriages.half_marriage_capture_bonus = on`,
   `half_marriage_capture_bonus_value = 25`.
2. Drive a deal where a non-declarer captures both the K and Q of
   the same suit across two tricks.
3. The deal scoreboard shows a "Captured K+Q" row crediting that
   seat with +25.
4. Capture as `08-half-marriage-capture-bonus.png`.

## Notes

- Every screenshot should reflect the localised English text under
  the active locale; `ru/pl/uk` mirror EN as placeholders pending
  Phase 9 translations.
- For complex setups (drowned, half-marriage) it's easiest to
  hand-craft a deck distribution via a temporary `Session.from_state`
  fixture and restart; the journey-spec at
  `tests/e2e/journeys/marriage_variants_journey_spec.lua` shows the
  shape.
