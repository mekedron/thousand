# 2-player Variant A stock_draw — manual smoke script

Phase 3.6 wires the 2-player Variant A closed-talon stock-draw
distribution: `players.count = 2`,
`players.two_player_config = "closed_talon_draw_stock"`,
`talon.size = 0`, `talon.distribution = "stock_draw"`. Automated specs
cover the engine, dealer, session, view-model, and table-scene paths
(see
`tests/spec/core/rule_config_spec.lua`,
`tests/spec/core/dealing_spec.lua`,
`tests/spec/core/builtins_spec.lua`,
`tests/spec/app/table_view_model_spec.lua`,
`tests/e2e/journeys/two_player_stock_draw_journey_spec.lua`). This
document is a manual smoke script for the rendered table affordance.

## Run

```bash
cd /Users/nikita/Projects/thousand
PATH="$PWD/.luarocks/bin:$PATH" love .
```

## Walk-through

### 1. Variant A flow — stock + trump indicator on the table

1. Main menu → "New game".
2. From the template picker, select `Two-player Variant A`. (Do **not**
   clone it; the built-in already has `talon.size = 0`,
   `players.two_player_config = "closed_talon_draw_stock"`, and
   `talon.distribution = "stock_draw"` wired in.)
3. The table opens with two seated players (no third seat). Each hand
   holds **9 cards**. The talon area on the centre band shows a
   **6-card face-down stack** labelled "Stock", with a single
   **face-up card** beside it labelled "Trump indicator". The
   trump-indicator's suit is the deal's initial trump.
4. The auction opens immediately after the deal; there is no talon
   reveal phase. Forehand bids the minimum (100); the dealer passes.
   Trick play begins.
5. Capture as:
   - `01-stock-and-trump-indicator.png` — pre-trick: 9-card hands, the
     "Stock" label + 6-card stack, the face-up trump indicator with its
     "Trump indicator" caption. Confirm there is **no** "Talon",
     "Take talon", "Pass talon", or "Raise to …" button anywhere on
     the screen.

### 2. Per-trick draw (winner first, loser second)

1. Continue from step 1 above. Lead any legal card; the opponent
   responds.
2. After the trick resolves, the winner draws the top card from the
   stock and the loser draws the next. The "Stock" label remains; the
   count caption now reads **"4 cards left"**.
3. Capture as:
   - `02-after-first-trick.png` — post-first-trick: the stock pile is
     visibly shorter, the count caption shows 4 remaining, both hands
     are still **9 cards** (one played + one drawn).

### 3. Stock exhausted → strict play

1. Continue trick play until the stock is empty (three more tricks
   draw out the remaining 4 cards; the trump-indicator card is the
   final draw).
2. The stock area now reads **"Empty"** and no further drawing
   happens. Must-follow / must-beat / must-trump are now strict (the
   relaxed phase ends with the stock).
3. Capture as:
   - `03-stock-exhausted.png` — the "Stock" label remains, the
     "Empty" caption replaces the count, no card stack is drawn, and
     the trump indicator is gone (it was the bottom card and has been
     drawn).

### 4. Compare with 2-player Variant B (regression check)

1. Quit and start a new game with `Two-player Variant B`.
2. The table opens with **7-card hands** and a **3-card talon** (no
   stock, no trump indicator). The standard Take / Pass / discard /
   raise affordances appear. This confirms the Variant A changes did
   not regress Variant B's traditional-talon flow.
3. No screenshots required — sanity check only.

## What "passes"

A run passes if every screenshot above shows the labelled affordance,
hand sizes, stock count, and trick-start state matching the
description. If any state is wrong, stop and file the discrepancy as
a follow-up before considering the task closed.
