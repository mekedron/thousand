# Manual smoke check — Settings scene + hot-seat privacy toggle

Per [memory: smoke testing — hand the script over](../../../../.claude/projects/-Users-nikita-Projects-thousand/memory/feedback_smoke_testing.md),
this script is for the developer to run by hand.

## Pre-flight

```sh
make run
```

Window opens at the Thousand main menu.

## Steps

Take a screenshot at every numbered step and save to
`tests/e2e/screenshots/settings-curtain-toggle/<NN>-<short-slug>.png`.

1. **Menu has a Settings button.** Five buttons visible: New Game,
   Continue (greyed), Abandon Game (greyed), **Settings**, Quit. Save
   as `01-menu-with-settings.png`.

2. **Open Settings.** Click **Settings**. The Settings scene opens
   with the title "Settings", a row reading "Hot-seat privacy / Show a
   pass-to-next-player overlay between turns.", a button labelled
   **On**, and a top-right **Back** button. Save as `02-settings.png`.

3. **Toggle off.** Click the **On** button. Its label changes to
   **Off**. Save as `03-toggle-off.png`.

4. **Setting persists.** Click **Back** to return to the menu. Click
   **Settings** again. The button still reads **Off**. Quit the app
   (`make run` exits via the Quit button), relaunch with `make run`,
   open Settings — the button **stays Off** because the setting
   persisted to `settings.json` under `love.filesystem.getSaveDirectory()`.
   Save as `04-persisted.png`.

5. **No curtain in the new game.** Back → New Game. The table opens
   directly with Player 2's hand face-up and the bid panel visible —
   **no privacy curtain** appears at any point. Bid 100, then Pass,
   then Pass again — the deal proceeds without ever showing a
   between-turns overlay. Save as `05-no-curtain.png`.

6. **Toggle back on.** Esc → Settings → click **Off** → label flips
   to **On**. Back → Continue. The very next frame should raise the
   curtain for whichever seat is currently on turn (the seat your last
   action moved control to). Save as `06-curtain-restored.png`.

## Pass criteria

- The Settings button appears on the main menu, always enabled.
- The Settings scene renders the toggle, label, description, and Back.
- Clicking the toggle flips its label visually.
- The setting persists across an app relaunch.
- With the toggle **off**, no privacy curtain appears at any point in
  hot-seat play.
- With the toggle **on**, the curtain returns immediately on the next
  turn change.

If any of these fails, stop and fix before committing.

## Troubleshooting

- If the toggle label doesn't change after a click, `_sync_toggle_label`
  isn't being called — confirm the toggle button's `on_press` calls
  `settings.set("hot_seat_privacy", ...)`.
- If the setting doesn't persist across relaunch, the JSON file isn't
  being written — check `love.filesystem.getSaveDirectory()` and look
  for `settings.json` there. A read-only filesystem (rare) would also
  cause this.
- If the curtain still rises with the toggle off, the gate in
  `ui/scenes/table.lua:_apply_curtain_trigger` isn't reading the
  current value — make sure `settings.get("hot_seat_privacy")` is the
  first check, not after some short-circuit.
