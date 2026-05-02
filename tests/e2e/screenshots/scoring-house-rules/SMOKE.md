# Scoring house rules — manual smoke check

Phase 3.6 task: "Implement scoring house rules" — wires four
`scoring.*` `RuleConfig` toggles end-to-end. Engine math is pinned by
`tests/spec/core/scoring_spec.lua` and session/view-model wiring by
`tests/spec/app/session_scoring_variants_spec.lua`. This script exists
so the human can confirm the deal-done scoreboard renders the new rows
and inline strict-rounding suffix in the running game (Love2D draw
path can't be exercised under busted's `love`-mock harness).

## Pre-flight

```sh
cd /Users/nikita/Projects/thousand
PATH="$PWD/.luarocks/bin:$PATH" busted   # 1765 tests, 0 failures
PATH="$PWD/.luarocks/bin:$PATH" make lint  # 0 warnings
```

## Smoke run

```sh
love .
```

For each of the four toggles below, save a screenshot (window-grab is
fine — `Cmd-Shift-4` then click the Love2D window on macOS) into this
directory.

### 1. `actual_points_on_success = "on"` → `actual_points_override.png`

1. Main menu → Templates → clone "Russian Thousand".
2. In the editor, set **Score actual points on success** = on. Save as
   `Smoke — actual points`.
3. Use this template → start a new game. Drive a deal where the
   declarer captures more than the bid (e.g. bid 100, capture 75 +
   declare hearts marriage on lead → deal_score 175). Finish all 8
   tricks.
4. At the deal-done banner, screenshot. Expected: a row labelled
   **Actual points override** with a positive total equal to
   `success_payout - bid`.

### 2. `defender_contributions = "pooled"` → `defender_pool.png`

1. Templates → clone Russian → set **Defender contributions** =
   pooled. Save / use.
2. Drive a deal where the declarer fails (e.g. bid 120, defenders
   capture asymmetrically — one takes 90 points, the other 30).
3. Screenshot the deal-done banner. Expected: a single
   **Defender pool** row showing the pooled total (e.g. `120`).
   Each defender's running total advances by the equal pooled share
   (`+60` here).

### 3. `failed_contract_distribution = "split_among_defenders"` → `failed_contract_distribution.png`

1. Templates → clone Russian → set **Failed-contract distribution** =
   split among defenders. Save / use.
2. Drive a deal where the declarer fails the bid.
3. Screenshot. Expected: a **Failed-contract share** row showing the
   distributed bid total. Defender running totals reflect their own
   captured + the split share (e.g. bid 100 split → +50 each on top
   of captured points).

### 4. `declarer_rounding_before_contract_check = "off"` → `rounding_strict.png`

1. Templates → clone Russian → set **Round declarer before contract
   check** = off. Save / use.
2. Drive a deal where the declarer captures a non-multiple-of-5
   total just shy of the bid (e.g. bid 120, capture 118). Under
   the strict mode the contract check uses raw 118 < 120 → fails.
   (Under the canonical `on` default the same hand would round to
   120 and succeed.)
3. Screenshot the deal-done banner. Expected: a `(raw 118, rounded
   120)` suffix beside the declarer's deal-score line. The
   `made_contract` indicator should reflect the strict failure.

## Pass criteria

- Each screenshot shows the expected new row / suffix.
- The deal-done running totals reflect the toggle's effect (no
  off-by-one, no missing rows).
- Switching the active template back to canonical Russian and
  finishing a deal shows none of the new rows / suffix (canonical
  defaults).

## Fail mode

If any screenshot is missing or wrong, do **not** commit: open an
issue noting which toggle broke and the observed deal-done payload.
