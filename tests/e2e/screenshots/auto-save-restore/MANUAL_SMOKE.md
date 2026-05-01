# Manual smoke check — auto-save and restore

Per [memory: smoke testing — hand the script over](../../../../.claude/projects/-Users-nikita-Projects-thousand/memory/feedback_smoke_testing.md),
this script is for the developer to run by hand.

The automated journey at
`tests/e2e/journeys/auto_save_restore_spec.lua` exercises the same flow
under the love-mock; this script is the on-device sanity check that the
file actually round-trips through `love.filesystem.getSaveDirectory()`.

## Pre-flight

Find your save directory:

```sh
love . 2>&1 | head -5   # printed at startup, or:
ls "$HOME/Library/Application Support/LOVE/thousand"   # macOS
```

Delete any leftover save so each run starts clean:

```sh
rm -f "$HOME/Library/Application Support/LOVE/thousand/auto_save.json"
make run
```

## Steps

Take a screenshot at every numbered step and save to
`tests/e2e/screenshots/auto-save-restore/<NN>-<short-slug>.png`.

1. **Fresh menu — Continue greyed.** No `auto_save.json` on disk. Menu
   shows New Game (enabled), Continue (greyed), Abandon Game (greyed),
   Settings (enabled), Quit (enabled). Save as
   `01-menu-no-save.png`.

2. **New Game → mid-deal.** Click **New Game**. Drive the auction one
   click in (e.g. Bid 100, Pass, Pass) so the talon phase opens, then
   take the talon and pass two cards. Save as `02-mid-deal.png`.

3. **Quit (graceful).** Use Cmd+Q (or your OS's window close button).
   Verify `auto_save.json` exists in the save directory and is non-zero
   bytes. Save the directory listing as `03-after-quit.png`.

4. **Relaunch — Continue enabled.** `make run` again. Menu shows
   Continue **enabled** and Abandon Game **enabled**. Save as
   `04-relaunch-continue-enabled.png`.

5. **Continue restores state.** Click **Continue**. The table reopens
   on the same deal, with the same hands, same bid history, same player
   on turn. Save as `05-continue-restored.png`.

6. **Suspend (background) round-trip.** Drive a couple more actions.
   Cmd+H (macOS) or alt-tab away to background the app. Wait a few
   seconds, return — verify the running game is still up. Quit and
   relaunch — `auto_save.json` reflects the post-suspend state. Save as
   `06-after-suspend.png`.

7. **Save fires after a scored deal.** Play one full deal to its
   8th-trick scoring. The deal-done banner appears. Without quitting,
   inspect `auto_save.json` and confirm the running totals match what
   the scoreboard shows. Save the diff/listing as
   `07-post-deal-save.png`.

8. **Game-over does not restore.** Use the smallest possible game (or
   keep playing) until a player crosses 1000. The end-of-game scene
   appears. Quit. Relaunch. Continue is **greyed out** because the
   loader rejects a save with `winner != nil` and the in-update hook
   cleared the file when the phase reached `done`. Save as
   `08-no-restore-after-win.png`.

9. **Abandon clears the file.** Start a new game so a fresh save
   exists. Esc back to the menu. Click **Abandon Game** → **Yes,
   abandon**. Verify `auto_save.json` is gone from the save directory.
   Continue and Abandon Game return to greyed-out. Save as
   `09-after-abandon.png`.

## Pass criteria

- A fresh launch with no save file lands on the menu with Continue and
  Abandon Game greyed out.
- Auto-save triggers on graceful quit, on app suspend (focus lost or
  visibility lost), and after each scored deal.
- The save file lives at `auto_save.json` under
  `love.filesystem.getSaveDirectory()` and is valid JSON containing a
  `schemaVersion` and a `templateName`.
- Relaunch reads the file and restores the session: hands, talon, bid,
  current trump, declared marriages, played tricks, running totals.
- A finished game (winner != nil) is not restored — Continue stays
  greyed.
- Starting a new game from the menu replaces the save; abandoning the
  current game from the menu deletes it.

If any of these fails, stop and fix before committing.

## Troubleshooting

- If `Continue` stays greyed after a relaunch, check that the file was
  actually written (look in the save directory) and that
  `app/auto_save.lua` `load()` returns non-nil — common causes are a
  schema mismatch or a corrupt JSON write.
- If auto-save never fires after a scored deal, look at `main.lua`'s
  `love.update` poll: it triggers on `phase == "deal_done"`. A
  regression that holds the deal in `tricks` past the eighth play
  would suppress the trigger.
- If `love.quit` doesn't save, confirm `main.lua`'s `love.quit` is
  defined — LÖVE only calls a `love.quit` callback if the global
  exists, otherwise the app exits without firing it.
- If a finished game is silently restored to the menu's Continue, the
  loader's `state.winner ~= nil` guard in `app/auto_save.lua` `load()`
  has been bypassed.
