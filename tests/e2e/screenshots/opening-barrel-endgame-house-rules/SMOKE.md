# Opening-game / barrel / endgame house rules — manual smoke check

Phase 3.6 task: "Implement opening-game, barrel, and endgame house
rules" — wires eight `opening_game` / `barrel` / `endgame` toggles
end-to-end. Engine math is pinned by
`tests/spec/core/scoring_spec.lua` and `tests/spec/core/auction_spec.lua`;
session / view-model wiring by
`tests/spec/app/session_endgame_variants_spec.lua`. This script exists
so the human can confirm the new banners and scoreboard markers render
under Love2D — busted's `love`-mock harness cannot exercise the actual
draw path.

## Pre-flight

```sh
cd /Users/nikita/Projects/thousand
PATH="$PWD/.luarocks/bin:$PATH" busted   # full suite green
PATH="$PWD/.luarocks/bin:$PATH" make lint  # 0 warnings
```

## Smoke run

```sh
love .
```

For each toggle below, save a screenshot (`Cmd-Shift-4` → click the
Love2D window on macOS) into this directory.

### 1. `opening_game.golden_deal = "on"` → `golden_deal_banner.png`

1. Main menu → Templates → clone "Russian Thousand".
2. Editor: set **Golden deal** = on. Save as `Smoke — golden`.
3. Use → start a new game.
4. Expected: the auction panel is replaced by a gold banner reading
   `Golden deal — Player 1 forced to 120` with the subtitle
   `Deal 1 of 3`. Talon reveal / pass / play proceeds without ever
   showing the bid panel.
5. Screenshot the table on the first deal.

### 2. `barrel.pit_lock_in = "on"` → `pit_locked_marker.png`

1. Clone Russian → set **Pit lock-in** = on (pit_score stays at 700).
   Save / use.
2. Play through deals until any seat's running total crosses 700 from
   below (drive a deal that lands ≥ 700).
3. On the next render, screenshot. Expected: that seat's scoreboard
   row shows the teal `Pit-locked` line below the running total.
   Total is capped at exactly 700.

### 3. `barrel.collision_rule = "first_mounter"` → `collision_first_mounter.png`

1. Clone Russian → set **Barrel collision rule** = first_mounter.
   Save / use.
2. Drive deals so two seats reach 880 in close succession (tip: stage
   one seat at 870 and have the next deal push them to 880; then
   another seat to 880 the deal after that).
3. On the deal where the second seat would mount, screenshot the
   scoreboard. Expected: only the first-mounted seat shows the gold
   `Barrel: N left` line; the later mounter falls off (760).

### 4. `barrel.overshoot_penalty = "on"` → `overshoot_penalty_row.png`

1. Clone Russian → set **Overshoot penalty** = on. Save / use.
2. Drive a deal where the declarer is on barrel with
   `deals_remaining = 1` AND fails a bid above 120 (you'll need to
   stage a saved-game state for this; in practice this needs the talon
   raise toggle or a high opening-min variant. The session-integration
   test exercises this path directly via advance_game).
3. Expected on deal-done banner: a row reading
   `Overshoot penalty — bid lost`. Running total drops to
   `threshold − bid`.

### 5. `barrel.reverse_barrel = "on"` → `reverse_barrel_marker.png`

1. Clone Russian → set **Reverse barrel** = on. Save / use.
2. Drive deals until any seat's running total drops to or below −880
   (failed contracts at high bids accumulate quickly).
3. Screenshot. Expected: the seat shows the red
   `Reverse barrel: 3 left` line. The total caps at −880.

### 6. `endgame.going_over_target = "exact_only"` → `exact_only_indicator.png`

1. Clone Russian → set **Going over target** = exact_only. Save / use.
2. Open a game. Even before any deal is played, screenshot the
   scoreboard.
3. Expected: above the target row, a gold
   `Win exactly at 1000` indicator. The target row reads
   `Target: 1000`.

### 7. `endgame.tiebreaker = "continuation"` → `continuation_banner.png`

1. Clone Russian → set **Tiebreaker** = continuation. Save / use.
2. Drive deals until two seats both cross 1000 in the same deal
   (rare — quickest to reach this via a saved game with both seats
   pre-seeded near 950 and a deal that bumps both ≥1000).
3. Expected: deal-done banner shows the
   `Tied at target — target raised to 1500` row. Subsequent deals'
   scoreboard shows `Target: 1500`.

### 8. `endgame.dump_truck = "positive_only"` → `dump_truck_reset.png`

1. Clone Russian → set **Dump truck (самосвал)** = positive_only.
   Save / use.
2. Drive deals so a seat lands exactly on 555 (e.g. pre-seed at 455
   and complete a deal worth +100).
3. Expected: deal-done banner shows the
   `Dump truck — reset to 0` row. Scoreboard total resets to 0.

## Notes

* All eight toggles are exercised end-to-end by automated tests; the
  smoke check focuses on the visual chrome (banner colours, marker
  placement, scoreboard target row) that the busted suite cannot
  capture.
* When a smoke run produces an unexpected screenshot, capture both
  expected (from the test fixtures' state) and observed before
  reporting.
