# Cross-deal counter penalties — manual smoke check

Phase 3.7 task 2: "Implement the cross-deal counter penalties:
no-win-for-3-rounds, three-falls reset, and dark-game stick doubling"
— wires three new toggles end-to-end. Engine math is pinned by:

- `tests/spec/core/scoring_spec.lua` (advance_game fall-tracking +
  third-fall reset)
- `tests/spec/app/session_no_win_streak_spec.lua` (no-win counter
  semantics + threshold-fire + auto-save round-trip)
- `tests/spec/app/session_barrel_falls_spec.lua` (per-seat fall
  counter + reset event + multi-seat independence)
- `tests/spec/app/session_zero_tricks_dark_game_spec.lua` (dark-game
  stick doubling under blind_at_win)
- `tests/spec/core/auto_save_spec.lua` (counter persistence)
- `tests/e2e/journeys/cross_deal_counters_journey_spec.lua`
  (rendered scoreboard lines)

This script exists so the human can confirm the scoreboard counters
render correctly under Love2D — busted's `love`-mock harness cannot
exercise the real draw or input path.

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

### 1. Default canonical_russian: no new counter lines → `default_no_counters.png`

1. Main menu → New game → Russian Thousand (canonical) → start.
2. Drive into the tricks phase.
3. Expected: the scoreboard shows the standard rows (totals, barrel
   state, optional bolt / cross / write-off lines). **No** "No-win
   streak: …" or "Barrel falls: …" lines are visible.
4. Screenshot the scoreboard.

### 2. No-win streak counter visible → `no_win_counter.png`

1. Main menu → Templates → clone "Russian Thousand".
2. Editor: under Penalties, set **No-win streak penalty** =
   `Any three deals`. Leave threshold = 3 and amount = 120. Save as
   `Smoke — no-win streak`.
3. Use → start a new game.
4. Drive at least one deal where some seat does not win. Expected:
   under each seat, a teal-tinted line reads `No-win streak: N / 3`
   (where N is 0 after the first win, 1 after a non-win).
5. Screenshot the scoreboard.

### 3. No-win threshold-hit penalty fires → `no_win_penalty.png`

1. Continue the same game. Force three consecutive non-wins on a
   single seat (easiest: have that seat sit out as defender while a
   different declarer wins, three deals in a row).
2. On the third non-win, expected: the seat takes a `−120` penalty
   in the deal-done banner row (or visible in the running totals),
   and the counter line resets to `0 / 3`.
3. Screenshot immediately after the third non-win.

### 4. Three-falls reset to zero → `three_falls_reset.png`

1. Editor → clone the smoke template → also set **Three falls reset
   to zero** = `On` (under Barrel). Save as `Smoke — three falls`.
2. Use → start a new game with custom starting totals close to the
   barrel (use auto-save inspector or scripted fixtures if available;
   alternatively play long enough to reach 880).
3. Mount the barrel; fail across three deal_count attempts; mount
   again; fail again; mount a third time; fail.
4. Expected: on the third fall, the seat's running total is set to
   **0** instead of the standard `760` (= 880 − 120 fall_off
   penalty). The counter line `Barrel falls:` resets to `0 / 3`.
5. Screenshot showing the running total at 0 and the reset row in
   the deal-done overlay.

### 5. Dark-game stick doubling → `dark_game_doubled.png`

1. Editor → clone the smoke template → also set **Doubled in dark
   game** = `On` (under Penalties). Make sure
   **Zero-tricks penalty** = `Any three deals`. Save as
   `Smoke — dark stick`.
2. Use → start a new game. Drive into a deal where a seat declares
   blind (forehand opens 100 with the blind toggle, others pass).
3. Play out the deal so a defender takes zero tricks.
4. Expected: in the deal-done scoreboard, the zero-trick seat's bolt
   counter advances by **2** instead of 1. The running counter line
   reads `Bolts: 2 / 3` (or whatever its current threshold says).
5. Screenshot the scoreboard right after the deal closes.

### 6. All toggles off → counters never render → `all_off.png`

1. Switch back to the default `Russian Thousand` template.
2. Drive a fresh deal and confirm none of the new counter lines
   appear under any seat.
3. Screenshot the scoreboard.

## What to escalate

- A new counter line never renders despite its toggle being `on` →
  check `app/table_view_model.lua` (the section that builds
  `scoreboard[i].no_win` / `barrel_falls`) and confirm the
  configuration's penalties / barrel block actually carries the
  expected value (cloning the template twice can lose toggles).
- The third fall does NOT zero the running total → check
  `core/scoring.lua` `advance_game`: the `fall_count_reset_active`
  branch should fire when `barrel.fall_count_resets_to_zero == "on"`
  and the per-unit count just hit 3.
- The dark-game stick doubling does not fire → confirm
  `auction.blind_at_win` is true at the moment the deal closes.
  This is set in `core/auction.lua` when a winning bid was blind.
  If the declarer was outbid by a non-blind seat, `blind_at_win`
  becomes false — the rule does not fire (which is correct per
  the book wording).
- The no-win counter advances even on a "win" → confirm the
  declarer's `made_contract` is true on the deal-done payload, or
  the defender's `deal_scores[seat]` is positive. Both qualify as
  "winning the deal" per the book; either should reset under
  `consecutive_three`.
- Banner wording is in English when locale = ru/pl/uk → the new
  i18n keys (`templates.field.penalties.no_win_streak.label`, …)
  carry .label translations only; .help and option labels fall
  back to en. Phase 9 covers full translation work.
