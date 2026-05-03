# Write-off / сдача — manual smoke check

Phase 3.7 task 1: "Implement write-off / сдача and the every-third-
write-off penalty" — wires the new mid-deal concession action and its
counter end-to-end. Engine math is pinned by
`tests/spec/app/session_write_off_spec.lua`; auto-save round-trip by
`tests/spec/core/auto_save_spec.lua`; view-model and panel rendering
by `tests/spec/app/table_view_model_spec.lua` and
`tests/e2e/journeys/write_off_journey_spec.lua`. This script exists
so the human can confirm the panel button, the scoreboard counter,
and the deal-done banner all behave correctly under Love2D — busted's
`love`-mock harness cannot exercise the real draw or input path.

## Pre-flight

```sh
cd /Users/nikita/Projects/thousand
PATH="$PWD/.luarocks/bin:$PATH" busted    # full suite green
PATH="$PWD/.luarocks/bin:$PATH" make lint # 0 warnings
```

## Smoke run

```sh
love .
```

For each step below, save a screenshot (`Cmd-Shift-4` → click the
Love2D window on macOS) into this directory.

### 1. Default canonical_russian: no Write-off button → `default_no_button.png`

1. Main menu → New game → Russian Thousand (canonical) → start.
2. Forehand bids 100, two seats pass; the talon takes and discards.
3. The tricks phase opens. Expected: **no** "Write off" button next
   to the play-card affordances. The default canonical_russian still
   ships `bidding.write_off = "off"`.
4. Screenshot the tricks panel showing only the standard play UI.

### 2. Toggle on, button visible → `toggle_on_button.png`

1. Main menu → Templates → clone "Russian Thousand".
2. Editor: set **Write-off / сдача** = `On` (under the Bidding
   section). Leave **Write-off split** at its default
   (`Half to each opponent`). Save as `Smoke — write-off`.
3. Use → start a new game.
4. Drive into the tricks phase as the declarer (forehand opens 100,
   others pass, take and discard talon).
5. Expected: a new `Write off` button is present in the tricks panel
   alongside the play affordances. It should be enabled, hover-
   responsive (mouse), and reachable via Tab keyboard navigation.
6. Screenshot the tricks panel with the button focused via Tab.

### 3. Press Write off → deal-done banner → `write_off_banner.png`

1. From step 2, press **Write off** (mouse click or focus + Enter).
2. Expected: the deal closes immediately. The deal-done banner reads
   `Write-off — declarer conceded mid-deal`. The scoreboard shows
   the declarer at `−100` and each opponent at `+50`.
3. Screenshot the deal-done state.
4. Press **Next deal**.

### 4. Streak counter on the scoreboard → `streak_counter.png`

1. Editor → clone the smoke template → also set
   **Every-third-write-off penalty** = `Any three write-offs`. Leave
   the threshold at 3 and the penalty amount at 120. Save as
   `Smoke — write-off + streak`.
2. Use → start a new game.
3. As declarer, write off in the first deal. Expected: the
   scoreboard now shows `Write-offs: 1 / 3` under the declarer's row
   (distinct blue-grey tint, below the Bolts / Crosses lines if any).
4. Screenshot the scoreboard.

### 5. Threshold-hit penalty fires → `streak_penalty.png`

1. Continue the same game from step 4. Have the same seat declare
   and write off three deals in a row. (You can pass-out the deals
   where the seat is not the declarer.)
2. On the third write-off the declarer should pay the bid (`−100`)
   **plus** the configured penalty (`−120`), and the
   `Write-offs:` counter resets to `0 / 3`.
3. Screenshot the scoreboard immediately after the third write-off.

### 6. equal_split variant → `equal_split.png`

1. Editor → clone the smoke template → set **Write-off split** =
   `Equal split across opponents`. Save as `Smoke — write-off equal`.
2. Use → start a new game with the new template.
3. As declarer at a 100 contract, press Write off.
4. Expected: in 3-player canonical Russian, the math matches
   `half_to_each` (each opponent gets `floor(100 / 2) = 50`). The
   visible difference would only appear in 4-player non-partnership
   layouts, where `half_to_each` gives each of three opponents 50
   (= 150 total credit) while `equal_split` gives `floor(100/3) = 33`
   each (= 99 total credit). For the canonical 3-player case both
   modes look identical — confirm no errors and capture the panel.

## What to escalate

- The `Write off` button is not present after toggling
  `bidding.write_off` to `on` → check `build_tricks_panel` in
  `ui/scenes/table.lua` and `build_tricks_phase_block` in
  `app/table_view_model.lua`.
- The button is present but pressing it does nothing → check
  `Session:write_off()` guards in `app/session.lua`; the action
  rejects under `wrong_phase`, `write_off_disabled`,
  `too_late_to_write_off`, etc., with a structured error.
- The scoreboard never shows `Write-offs: X / Y` despite the streak
  toggle being on → confirm `app/table_view_model.lua` exposes
  `entry.write_offs` and the table scene reads
  `entry.write_offs.count` / `.threshold`.
- The third write-off does not fire the penalty → confirm
  `penalties.write_off_streak` is actually `any_three` (cloning the
  template twice can lose toggles). Check `_write_off_counts` via
  the auto-save inspector if needed.
- Banner wording is in English when locale = ru/pl/uk → the
  i18n keys (`scene.table.tricks.write_off_button`,
  `scene.table.scoreboard.write_off_counter`,
  `scene.table.deal_done.write_off`) currently fall back to en;
  Phase 9 covers full translation.
