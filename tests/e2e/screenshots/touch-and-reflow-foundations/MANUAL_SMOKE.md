# Manual smoke test — Touch-ready input and reflowable layout foundations

Run these by hand against `love .`, then drop screenshots into this
directory if you want to capture the visual state. The pure-Lua e2e
journey (`tests/e2e/journeys/touch_input_spec.lua`,
`tests/spec/ui/finger_size_spec.lua`, and the extended resize block in
`tests/e2e/journeys/menu_navigation_spec.lua`) covers the same logic;
this script is the visual sanity check.

## Setup

```bash
make run    # alias for `love .`
```

Window opens at 1280×720. Active scene: main menu.

## Steps

| # | Action | What you should see |
|---|---|---|
| 1 | Window opens at 1280×720 | Main menu visible: title, subtitle, four stacked buttons. New Game has the focus outline. |
| 2 | Drag the window down to ~800×600 (the conf.lua minimum) | Buttons reflow toward the new centre; title and subtitle stay centred; nothing clips off the edges. |
| 3 | Click `New Game` | Table scene: green felt, `Table` header centred, escape hint text near the bottom, Menu button in the top-right corner with ~16 px breathing room from both edges. |
| 4 | Resize the window to ~1600×900 | Menu button **stays in the top-right corner** with the same 16 px margin — its x position grows with the window. Title stays centred. |
| 5 | Resize back to ~800×600 | Menu button still pinned to top-right with the 16 px margin. |
| 6 | Click the `Menu` button | Returns to the main menu. Continue and Abandon Game become active (vivid green); New Game is no longer the only enabled button. |
| 7 | Click `New Game` again, then click-and-hold the Menu button and drag the cursor outside it before releasing | The Menu button shows its pressed (darker) colour while held; releasing outside cancels the action — you stay on the table. |
| 8 | Press Cmd+Q (macOS) or click `Quit` from the main menu | App exits cleanly. |

Touch-hardware checks (real iOS / Android tap, drag, multi-touch) are
deferred to Phase 5 (iOS port) when love-ios lands. Until then the
pure-Lua harness covers the touch wiring through
`tests/e2e/journeys/touch_input_spec.lua`.

## Screenshots to drop here (optional)

Suggested filenames if you do capture:

- `01_menu_at_1280x720.png` — fresh launch
- `02_menu_at_800x600.png` — minimum-size reflow
- `03_table_at_1280x720.png` — table with Menu button top-right
- `04_table_at_1600x900.png` — Menu button stays top-right after resize
- `05_table_pressed_then_released_outside.png` — pressed colour, no transition

These are not committed to git automatically; drop them in this
directory manually if you want them in the PR.
