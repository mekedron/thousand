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
| 6 | Click `New Game` | **The per-seat picker scene opens.** Title `Start a new game`, subtitle `Playing under Russian Thousand`, three rows: `Seat 1 [Human|Bot]`, `Seat 2 [Human|Bot]`, `Seat 3 [Human|Bot]`. Defaults: row 1 = Human, rows 2–3 = Bot. `Start` button below; `Back` button in the top-right. |
| 7 | Click the `Human` segment on row 2 | Row 2 flips to Human. The segment background brightens for the active value. |
| 8 | Click `Start` | Table opens with seat composition `{human, human, bot}`. The forehand under canonical Russian is seat 2 (now also human), so the privacy curtain raises on seat 2 immediately. Seat 3's bot will pick up its turn after the auction reaches it. |
| 9 | Esc → menu → `New Game` again | Picker reopens with the **default composition again** (row 1 = Human, rows 2/3 = Bot) — the picker rebuilds on each entry. |
| 10 | Toggle every row to `Bot` (3 clicks) | All-bots composition is allowed; `Start` is still active. |
| 11 | Click `Start` | Table opens with `{bot, bot, bot}`. **The privacy curtain never raises** — there are no human seats to protect. The auction auto-advances; you can watch it play. |
| 12 | Esc → menu → `Continue` | Resumes mid-auction with the same all-bot composition. |
| 13 | Resize the window | Picker reflows: title/subtitle stay centred, rows stay aligned. |
| 14 | Cmd+Q to quit | App exits cleanly. |

## Keyboard navigation (optional pass)

| # | Action | Expected |
|---|---|---|
| K1 | On the menu, press Tab | Focus outline appears on `Single Player` (first enabled). |
| K2 | Tab again | Focus moves to `New Game`. |
| K3 | Enter on `New Game` | Picker opens. |
| K4 | Tab once | Focus on row 1 toggle. |
| K5 | Tab + Enter | Row 2 cycles to Human. |
| K6 | Tab + Enter | Row 3 cycles to Human. |
| K7 | Tab + Enter | Start activates → table opens with all three seats human. |
| K8 | Esc on the picker | Returns to menu without starting. |

## Screenshots to drop here (optional)

Suggested filenames:

- `01_menu.png` — fresh launch showing Single Player above New Game.
- `02_table_after_single_player.png` — after Single Player, curtain on seat 1 once bots have passed.
- `03_picker_default.png` — New Game picker, default composition.
- `04_picker_two_humans.png` — row 2 flipped to Human.
- `05_picker_all_bots.png` — every row flipped to Bot, Start still active.
- `06_table_all_bots_no_curtain.png` — all-bot game, no privacy curtain.

These are not committed to git automatically; drop them in this dir
manually if you want them in the PR.
