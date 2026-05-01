# Manual smoke check — Hot-seat privacy and hand-off flow

Per [memory: smoke testing — hand the script over](../../../../.claude/projects/-Users-nikita-Projects-thousand/memory/feedback_smoke_testing.md),
this script is for the developer to run by hand. **Do not** drive Love2D
through computer-use or MCP — those workflows have proven unreliable for
this codebase.

## Pre-flight

```sh
make run            # Launches `love .` from the repo root.
```

Window opens at the Thousand main menu.

## Steps

Take a screenshot at every numbered step and save to
`tests/e2e/screenshots/hot-seat-privacy/<NN>-<short-slug>.png`.

1. **Forehand curtain on a fresh game.** Click **New Game**. The
   screen goes black with a centred panel reading
   `Pass the device to Player 2.` / `Tap when ready.` plus a `Ready`
   button. The whole table behind is fully obscured — you should not
   see any cards or labels through the backdrop. Save as
   `01-curtain-forehand.png`.

2. **Ready dismiss.** Click **Ready**. The curtain disappears and
   Player 2's hand is revealed at the bottom strip with the bid panel
   visible (`Bid 100` … `Bid 120` plus `Pass`). Save as
   `02-after-ready.png`.

3. **Tap-anywhere dismiss.** Press **Esc** to return to the menu,
   click **Continue**. The curtain re-appears for Player 2. This time
   click anywhere on the dark backdrop **outside** the centre panel
   (e.g. top-left corner). The curtain dismisses just like Ready.
   Save as `03-tap-anywhere.png` of the curtain immediately before the
   click, and `04-after-tap-dismiss.png` of the table after.

4. **Bid raises a curtain for the next seat.** Click `Bid 100`. The
   curtain rises again with `Pass the device to Player 3.` Save as
   `05-curtain-seat-3.png`.

5. **Pass during auction.** Tap Ready. Click `Pass`. The curtain
   appears with `Pass the device to Player 1.` Save as
   `06-curtain-seat-1.png`.

6. **Auction → talon hand-off.** Tap Ready, click `Pass` (Player 1
   passes). Auction terminates with Player 2 as declarer. The curtain
   appears one more time with `Pass the device to Player 2.` Save as
   `07-curtain-back-to-declarer.png`.

7. **No curtain through the talon flow.** Tap Ready. Click
   `Take talon`. **No curtain** — the same Player 2 keeps acting.
   Confirm by clicking two cards to pass them and then `Keep bid at
   100`; through all of these the curtain never re-appears. Save as
   `08-talon-flow-no-curtain.png` after the skip-raise click.

8. **First card of the first trick.** The phase becomes `Tricks` and
   Player 2 leads. **No curtain yet** — Player 2 is still acting.
   Click any legal card. The card flies to the centre, and the curtain
   appears with `Pass the device to Player 3.` Save as
   `09-trick-first-card.png` (curtain rendered).

9. **Esc during the curtain returns to menu.** With the curtain up
   (any seat), press **Esc**. The main menu returns; **Continue**
   resumes the same in-progress deal. Confirm Continue brings the
   curtain back for the same seat. Save as `10-esc-returns-to-menu.png`
   of the menu after Esc.

10. **Deal-done has no curtain.** Continue playing through the deal
    by tapping Ready then a legal card on each turn until the eighth
    trick resolves. The deal-done banner appears centred (`Deal
    complete` + per-player running totals + `Next deal` button).
    **No curtain** — the device is on the table while everyone reads
    scores. Save as `11-deal-done-no-curtain.png`.

11. **Next deal raises a curtain for the new forehand.** Click
    `Next deal`. A new deal is dealt and the curtain appears for the
    new forehand (Player 3 after one rotation). Save as
    `12-next-deal-curtain.png`.

## Pass criteria

A run **passes** when every screenshot above is captured and shows the
described state. If any of the four task-line claims fails:

- the curtain hides inactive hands (full-opacity backdrop, no leak),
- each player only sees their own hand during private decisions,
- the curtain rises on every turn change between humans (auction
  bid/pass, every trick-card play, deal kickoff), and
- no curtain interrupts a sequence in which the same seat keeps acting
  (talon take + passes + raise/skip, marriage declaration mid-lead),

stop and fix before committing.

## Troubleshooting

- If you can see card outlines through the curtain, the backdrop
  alpha is too low — `CURTAIN_BG` in `ui/scenes/table.lua` must stay
  at `{0, 0, 0, 1}`.
- If the curtain re-raises during the talon flow (between take, pass
  cards, raise/skip), the trigger compares `view.turn_player` against
  the wrong seat — check `Session:current_turn()` returns
  `talon.declarer` consistently across `take_talon`, `pass_talon` and
  `skip_raise`.
- If `Esc` during the curtain reveals the hand instead of going to
  menu, the keypressed branch in the curtain block is wired wrong —
  Esc must call `_return_to_menu`, not `_close_curtain`.
- If the curtain flicker-appears on `Take talon` / pass-talon clicks,
  `_apply_curtain_trigger` is firing during the talon phase — confirm
  `Session:current_turn()` returns the declarer (not nil) throughout
  the talon flow.
