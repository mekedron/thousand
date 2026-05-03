# Manual smoke test — Phase 4.2 single-player & seat assignment

Drop screenshots here if you want a visual record. The pure-Lua
journeys at `tests/e2e/journeys/{single_player,new_game,bot}_journey_spec.lua`
cover the underlying logic; this script is the visual sanity check
against `love .`.

## Setup

```bash
make run        # alias for `love .`
```

Window opens at 1280×720. Active scene: main menu.

## Steps

| # | Action | What you should see |
|---|---|---|
| 1 | Window opens | Title `Thousand`, six buttons stacked centred. **`Single Player` is at the top of the column, above `New Game`.** Continue and Abandon Game are muted (disabled). |
| 2 | Click `Single Player` | Skip any privacy curtain. **Table opens directly** — no picker between. The forehand under canonical Russian is seat 2; with seat 1 = human and seats 2/3 = bots, the auction begins on a bot turn so the curtain may not raise immediately. After both bot seats auto-pass (~1–2 s), the privacy curtain raises for **seat 1**. |
| 3 | Tap the curtain dismiss to enter the human seat | Bid panel renders. The seat indicator shows "you" on seat 1. Seats 2 and 3 should be visible at the top of the table. |
| 4 | Press Esc → menu | Continue and Abandon Game are now enabled. |
| 5 | Click `Abandon Game` → `Yes, abandon` | Both grey out again. |
| 6 | Click `New Game` | **The per-seat picker scene opens.** Title `Start a new game`, subtitle `Playing under Russian Thousand`, three rows. Each row has *two* segmented toggles side by side: `Seat 1 [Human\|Bot] [Easy\|Normal\|Hard]`. Defaults: row 1 = Human, rows 2–3 = Bot. **Difficulty defaults to `Normal`.** Row 1's difficulty toggle is disabled (greyed background, amber-ringed `Normal` for the read-only "current value" cue) because seat 1 is human; rows 2 and 3 are interactive. `Start` button below; `Back` button in the top-right. |
| 7 | Click `Hard` on row 2's difficulty toggle | Row 2's difficulty flips to `Hard` (active segment brightens). Row 1's difficulty stays disabled. |
| 8 | Click `Bot` on row 1 | Row 1's difficulty toggle becomes interactive (no more amber ring, full colour). Row 1 difficulty stays at `Normal` until you click it. |
| 9 | Click `Human` on row 1 | Row 1 difficulty greys out again with the amber ring on whichever value was current — verifies the disable round-trips cleanly. |
| 10 | Click the `Human` segment on row 2 | Row 2 flips to Human; row 2's difficulty toggle greys out (you may have to look — it was on Hard). |
| 11 | Click `Start` | Table opens with `{human, human, bot}` and `seat_difficulties = {normal, hard, normal}`. (The bot only runs on seat 3, so behaviour is indistinguishable from `normal` until Phase 4.3 lands real heuristics — but the binding is in place.) The privacy curtain raises on seat 2 (forehand under canonical Russian dealer 1, now human). |
| 12 | Esc → menu → `New Game` again | Picker reopens with **default composition** (row 1 = Human, rows 2/3 = Bot, all difficulties = Normal). |
| 13 | Toggle every row to `Bot` (3 clicks) | All-bots composition is allowed; `Start` is still active. Every row's difficulty toggle is now interactive. |
| 14 | Cycle row 2 difficulty to `Easy`, row 3 to `Hard` | Each click changes the active segment. |
| 15 | Click `Start` | Table opens with `{bot, bot, bot}` and `seat_difficulties = {normal, easy, hard}`. **The privacy curtain never raises** — no human seats to protect. The auction auto-advances; you can watch it play. |
| 16 | Esc → menu → `Continue` | Resumes mid-auction with the same all-bot composition and difficulty binding (verified in `auto_save_restore_spec.lua` round-trip). |
| 17 | Resize the window | Picker reflows: title/subtitle stay centred, rows stay aligned, difficulty toggles stay aligned to the right of the kind toggles. |
| 18 | Cmd+Q to quit | App exits cleanly. |

## Keyboard navigation (optional pass)

The Tab order pairs each row's kind toggle with its difficulty toggle, but
disabled toggles are skipped. Default 3-player layout: kind1, **(skip diff1
disabled)**, kind2, diff2, kind3, diff3, Start, Back.

| # | Action | Expected |
|---|---|---|
| K1 | On the menu, press Tab | Focus outline appears on `Single Player` (first enabled). |
| K2 | Tab again | Focus moves to `New Game`. |
| K3 | Enter on `New Game` | Picker opens. |
| K4 | Tab once | Focus on row 1 kind toggle. |
| K5 | Tab again | Focus skips row 1's disabled difficulty toggle and lands on row 2 kind. |
| K6 | Tab + Enter | Row 2 cycles to Human; row 2 difficulty disables itself. |
| K7 | Tab once | Focus moves to row 3 kind (skips row 2 difficulty since it just disabled). |
| K8 | Tab + Enter | Row 3 cycles to Human; row 3 difficulty disables itself. |
| K9 | Tab + Enter | Start activates (no more enabled difficulty toggles to traverse) → table opens with all three seats human, all difficulties stayed at `Normal`. |
| K10 | Esc → menu → `New Game` | Reopens picker, default composition. |
| K11 | Tab + Tab + Tab | Lands on row 2 difficulty (kind1 → kind2 → diff2). |
| K12 | Enter | Cycles diff2 from Normal → Hard. |
| K13 | Esc on the picker | Returns to menu without starting. |

## Screenshots to drop here (optional)

Suggested filenames:

- `01_menu.png` — fresh launch showing Single Player above New Game.
- `02_table_after_single_player.png` — after Single Player, curtain on seat 1 once bots have passed.
- `03_picker_default.png` — New Game picker, default composition with the three difficulty toggles visible (row 1 greyed with amber ring on Normal, rows 2 and 3 interactive).
- `04_picker_two_humans.png` — row 2 flipped to Human; both row 1 and row 2 difficulty toggles greyed.
- `05_picker_all_bots.png` — every row flipped to Bot, every difficulty toggle interactive, Start still active.
- `06_table_all_bots_no_curtain.png` — all-bot game, no privacy curtain.

### Phase 4.2 difficulty additions

Drop these into `difficulty/` next to the others if you want a focused
record of the new toggle:

- `difficulty/01_default.png` — row 1's difficulty toggle disabled (amber-ringed Normal), rows 2/3 enabled.
- `difficulty/02_row2_hard.png` — row 2 difficulty cycled to Hard.
- `difficulty/03_row1_bot_enables_diff.png` — row 1 flipped to Bot; row 1's difficulty toggle now interactive.
- `difficulty/04_focus_order.png` — Tab focus visible on row 2 difficulty (after Tab + Tab + Tab from picker entry).

These are not committed to git automatically; drop them in this dir
manually if you want them in the PR.
