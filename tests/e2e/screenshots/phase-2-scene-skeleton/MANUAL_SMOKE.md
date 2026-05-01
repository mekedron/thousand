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
| 3 | Press Tab (or Down) | Focus outline jumps to the next enabled button (Quit, since Continue and Abandon are disabled). |
| 4 | Press Shift+Tab (or Up) | Focus moves backward, wrapping to New Game. |
| 5 | Press Enter | Scene switches to the table. Green felt, `Table` header, escape hint at the bottom, and a `Menu` button in the top-right corner. |
| 6 | Click the `Menu` button | Returns to the main menu. Continue and Abandon Game are both active (vivid green). |
| 7 | Click Continue | Returns to the table — same session resumes (no New Game, no confirm prompt). |
| 8 | Click Menu, then click Abandon Game | Modal overlay appears: `Abandon the current game?` with `Yes, abandon` and `Cancel` side-by-side. Cancel has the focus outline (default). |
| 9 | Press Left | Focus moves to `Yes, abandon`. (Right or Tab also work.) |
| 10 | Press Escape | Modal dismissed. Menu visible. |
| 11 | Click Abandon Game again, then click `Yes, abandon` | Modal dismissed. Both Continue and Abandon Game are greyed again (no session). |
| 12 | Click New Game, then drag-press the Menu button but release outside it | Menu button's pressed colour appears while held; releasing outside cancels the action — you stay on the table. |
| 13 | Resize the window | Buttons reflow. Title and subtitle stay centred. |
| 14 | Click Quit (or press Cmd+Q on macOS) | App exits cleanly. |

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
