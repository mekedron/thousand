## Manual smoke check — Legal-action affordances

Per [memory: smoke testing — hand the script over](../../../../.claude/projects/-Users-nikita-Projects-thousand/memory/feedback_smoke_testing.md),
this script is for the developer to run by hand. **Do not** drive Love2D
through computer-use or MCP — those workflows have proven unreliable for
this codebase.

## What this checks

The Phase 2 task `Add legal-action affordances` claims two behaviours:

1. **Cards that are legal under must-follow, must-beat, and must-trump
   rules can be visually distinguished.** Illegal cards in the active
   hand are dimmed; the dim is suppressed under hover so the cursor
   does not pretend the card is pickable.
2. **Illegal player actions are blocked with localised feedback.** A
   tap on an illegal card shows a localised toast that names the
   broken rule (must-follow / must-beat / must-trump / must-overtrump),
   not a bare engine error.

## Pre-flight

```sh
make run            # Launches `love .` from the repo root.
```

Window opens at the Thousand main menu.

## Steps

Take a screenshot at every numbered step and save to
`tests/e2e/screenshots/legal-action-affordances/<NN>-<short-slug>.png`.

1. **Reach the tricks phase as Player 2.** Click **New Game**, tap
   **Ready** to dismiss the forehand curtain, click `Bid 100`,
   tap Ready, click `Pass`, tap Ready, click `Pass` (auction
   terminates with Player 2 as declarer). Tap Ready, click
   `Take talon`, tap two cards in your hand to pass them to Players
   1 and 3 (the prompt above the hand says which player), click
   `Keep bid at 100`. The phase indicator now reads `Tricks`. Save
   as `01-tricks-phase-ready.png`.

2. **Lead the first card.** Click any card to lead. The card animates
   to the centre and the curtain rises for Player 3. Tap **Ready**.
   Save as `02-after-lead.png` once the curtain dismisses and
   Player 3's hand is on screen.

3. **Player 3 sees dimmed illegal cards.** Player 3 must follow the
   suit Player 2 led. Cards in Player 3's hand of the led suit
   render at full brightness; cards of other suits (and trumps when
   Player 3 is also void in the led suit) render with a translucent
   black overlay. Save as `03-dimmed-illegals.png`. Confirm visually
   that you can see at least one bright (legal) card and at least
   one dimmed (illegal) card.

4. **Hover does not lift an illegal card.** Hover the mouse over any
   bright (legal) card — it should rise about 12 pixels above its
   neighbours. Now hover an dimmed (illegal) card — the lift should
   NOT happen. The dim card stays in place even while the cursor sits
   over it. Save as `04-hover-legal.png` (lifted) and
   `05-hover-illegal-no-lift.png` (no lift).

5. **Tap an illegal card → localised toast.** Click an illegal (dimmed)
   card. The card stays in your hand and a red toast appears at the
   bottom of the centre band reading something like
   `You must follow ♥` (or whichever suit was led — `♠ ♣ ♦ ♥`). Save
   as `06-must-follow-toast.png` while the toast is still on screen
   (it auto-dismisses after about 2 seconds).

6. **Tap a legal card → no toast, card plays.** Click any bright
   (legal) card. The card flies to the centre, the curtain rises for
   the next seat, and there is **no toast**. Save as
   `07-legal-tap-no-toast.png` after the curtain raises.

7. **Trump scenario (must-trump).** Continue the deal until you reach
   a point where one seat is void in the led suit and a trump suit is
   active (i.e., somebody has declared a marriage in an earlier
   trick). When that seat must trump, all non-trump non-led cards
   render dimmed. Tapping one shows a toast like
   `You must play trump (♠)`. If you don't naturally reach this state
   in this deal, restart with `Esc → Continue` and play a few more
   tricks; it usually appears once a marriage is declared. Save as
   `08-must-trump-toast.png`.

8. **Keyboard focus on illegal card still works.** Press **Tab** to
   move focus into the hand. The yellow focus ring lands on the first
   card. Press **Right** until focus lands on a dimmed (illegal)
   card — the focus ring still appears around it (it lifts so the
   ring is fully visible) and the dim is still applied. Press
   **Enter**: the localised toast appears, just like clicking the
   card. Save as `09-keyboard-focus-illegal.png`.

## Pass criteria

A run **passes** when every screenshot above is captured and shows the
described state. If any of these claims fails:

- legal cards are visually distinct from illegal cards in the active
  hand (translucent overlay on illegal),
- hovering an illegal card does not lift it,
- tapping an illegal card shows a localised toast that names the
  broken rule (no bare English engine message), and
- tapping a legal card plays it without surfacing a toast,

stop and fix before committing.

## Troubleshooting

- If the dimmed cards are completely black and unreadable, `ILLEGAL_DIM`
  in `ui/scenes/table.lua` is too opaque — it should be
  `{ 0, 0, 0, 0.55 }` (~55% black) so the suit and rank are still
  recognisable through the dim.
- If hovering an illegal card lifts it, the `lift_hovered_index`
  logic in `draw_hand` is misfiring — it must guard against
  `card_legality[hovered_card_index] == false`.
- If tapping an illegal card shows `Illegal play: must_follow_violation`
  (or similar engine code text), the `err_to_toast_key` dispatch in
  `ui/scenes/table.lua` did not pick up the new code → key mapping;
  check that the code matches the engine's error envelope exactly.
- If the suit glyph in the toast is missing (just blank or the engine
  enum like `hearts`), the `suit_glyph` helper failed to look up the
  `card.suit.<name>` i18n key — verify the active locale table has
  the four suit glyph entries.
