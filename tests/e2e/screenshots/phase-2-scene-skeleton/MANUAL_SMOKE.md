# Manual smoke test — Phase 2 scene skeleton

Run these by hand against `love .`, then drop screenshots into this
directory if you want to capture the visual state. The pure-Lua journey
(`tests/e2e/journeys/menu_navigation_spec.lua`) covers the same logic;
this script is the visual sanity check.

## Setup

```bash
make run    # alias for `love .`
```

Window opens at 1280×720. Active scene: main menu.

## Steps

| # | Action | What you should see |
|---|---|---|
| 1 | Window opens | Title `Thousand`, subtitle, four buttons stacked centred. New Game and Quit are vivid green; Continue and Abandon Game are muted (disabled). New Game has a yellow focus outline. |
| 2 | Move the mouse over `Quit` | Quit's background brightens (hover). |
| 3 | Press Tab | Focus outline jumps to the next enabled button (Quit, since Continue and Abandon are disabled). |
| 4 | Press Down (or Tab) | Focus wraps back to New Game. |
| 5 | Press Enter (with New Game focused) | Scene switches to the table. Green felt, `Table` header, escape hint at the bottom, and a `Menu` button in the top-right corner. |
| 6 | Click the `Menu` button | Returns to the main menu. Abandon Game is now active (vivid green). |
| 7 | Click Abandon Game | Modal overlay appears: `Abandon the current game?` with `Yes, abandon` and `Cancel`. Cancel has the focus outline (default). |
| 8 | Press Tab | Focus moves to `Yes, abandon`. |
| 9 | Press Escape | Modal dismissed. Menu visible. |
| 10 | Click Abandon Game again, then click `Yes, abandon` | Modal dismissed. Abandon Game is greyed again (no game in progress). |
| 11 | Click New Game, then press Esc | Returns to menu (Esc still works for keyboard users alongside the visible Menu button). |
| 12 | Click New Game, then drag-press the Menu button but release outside it | Menu button's pressed colour appears while held; releasing outside cancels the action — you stay on the table. |
| 13 | Resize the window | Buttons reflow. Title and subtitle stay centred. |
| 14 | Press Cmd+Q (macOS) or click Quit | App exits cleanly. |

## Screenshots to drop here (optional)

Suggested filenames if you do capture:

- `01_main_menu.png` — fresh launch
- `02_main_menu_hover.png` — cursor over Quit
- `03_table.png` — after New Game, table scene
- `04_main_menu_with_active_abandon.png` — back from table, Abandon enabled
- `05_confirm_abandon.png` — modal open
- `06_back_to_clean_menu.png` — after Yes, Abandon greyed again

These are not committed to git automatically; drop them in this dir
manually if you want them in the PR.
