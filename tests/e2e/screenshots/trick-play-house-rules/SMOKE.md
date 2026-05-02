# Trick-play house rules — manual smoke script

Phase 3.6 trick-play-house-rules flips nine `tricks.*` toggles to
selectable and adds three sibling value fields:
`must_overtake_strictness`, `must_trump_strictness`,
`defender_must_overtrump_declarer`, `lazy_revoke`, `partial_trumping`,
`last_trick_bonus`, `last_trick_bonus_value`, `slam_bonus`,
`slam_bonus_value`, `slam_against_penalty`,
`slam_against_penalty_value`, `lead_trump_after_marriage`.

Automated unit + integration coverage lives in
`tests/spec/core/tricks_spec.lua`,
`tests/spec/core/scoring_spec.lua`,
`tests/spec/core/rule_config_spec.lua`,
`tests/spec/core/builtins_spec.lua`,
`tests/spec/app/session_trick_play_variants_spec.lua`, and
`tests/spec/app/table_view_model_spec.lua`. This document is a manual
smoke script for the rendered UI — hand it to a tester so they can
drive the table scene and capture screenshots that confirm the
visible changes.

## Run

```bash
cd /Users/nikita/Projects/thousand
PATH="$PWD/.luarocks/bin:$PATH" love .
```

## Walk-throughs

For every toggle below: clone the canonical Russian template from the
template picker, flip the toggle (and any sibling value field), save,
apply, and start a new game. Capture each key state to
`tests/e2e/screenshots/trick-play-house-rules/`.

### 1. polish_strict overtake / trump (Polish builtin)

1. Pick the **Polish Tysiąc** built-in template. The new fields are
   pre-set: `must_overtake_strictness = polish_strict`,
   `must_trump_strictness = polish_strict`,
   `defender_must_overtrump_declarer = on`.
2. Start a new game. Bid until you reach the tricks phase.
3. When following suit, the legal-card highlight should narrow to
   the *single highest beating card* in your hand of that suit.
   Capture `polish-strict-overtake.png`.
4. When forced to trump (void in led, holding trump), the highlight
   should narrow to the *single highest trump* in your hand. Capture
   `polish-strict-trump.png`.

### 2. defender_must_overtrump_declarer

1. Clone Russian → flip `defender_must_overtrump_declarer = on`.
2. Drive a deal where the declarer plays a trump and a defender (not
   the declarer) is void in the led suit and holds a trump higher
   than the declarer's. The defender's legal-card highlight should
   restrict to the over-the-declarer-trump cards only.
3. Capture `defender-must-overtrump.png`.

### 3. partial_trumping

1. Clone Russian → flip `partial_trumping = on`.
2. Drive a deal where a defender is void in led suit, holds only
   sub-threshold trumps, and the declarer has played a trump. The
   defender's legal-card set should include off-trump discards (in
   addition to their lower trumps) — the must-trump obligation
   relaxes.
3. Capture `partial-trumping-discard.png`.

### 4. lazy_revoke

1. Clone Russian → flip `lazy_revoke = on`.
2. Drive a deal and deliberately play an off-suit card while still
   holding the led suit. The play is *accepted* under
   `lazy_revoke = on` (the must-follow violation is recorded but does
   not block the play).
3. Capture `lazy-revoke-accepted.png`. Without `lazy_revoke = on` the
   same play is rejected with a toast.

### 5. last_trick_bonus

1. Clone Russian → flip `last_trick_bonus = on`,
   `last_trick_bonus_value = 10`.
2. Play a complete deal. The deal-done banner gains a "Last trick"
   row showing the +10 bonus credited to whoever won the eighth
   trick.
3. Capture `last-trick-row.png`.

### 6. slam_bonus = fixed

1. Clone Russian → flip `slam_bonus = fixed`,
   `slam_bonus_value = 60`.
2. Drive a deal where the declarer wins all eight tricks (e.g. seed
   the deal with a stacked declarer hand). The deal-done banner
   gains a "Slam bonus" row showing the +60 bonus credited to the
   declarer.
3. Capture `slam-bonus-fixed-row.png`.

### 7. slam_bonus = doubled_bid

1. Clone Russian → flip `slam_bonus = doubled_bid`.
2. Drive a deal where the declarer wins all eight tricks at a known
   bid. The declarer's running-total delta should be +2× the bid,
   not +bid. (No "Slam bonus" row appears under the doubled_bid
   variant; the doubling is realised via the bid multiplier.)
3. Capture `slam-bonus-doubled-bid.png`.

### 8. slam_against_penalty

1. Clone Russian → flip `slam_against_penalty = on`,
   `slam_against_penalty_value = 120`.
2. Drive a deal where the declarer takes zero tricks. The deal-done
   banner gains a "Slam against" row showing the −120 penalty
   subtracted from the declarer's score.
3. Capture `slam-against-row.png`.

### 9. lead_trump_after_marriage

1. Clone Russian → flip `lead_trump_after_marriage = on`.
2. Play a deal until a marriage is declared (lead K or Q of a held
   marriage). On the trick AFTER the marriage trick, the leader's
   legal-card highlight should narrow to trump cards only (assuming
   the leader holds at least one trump).
3. Capture `lead-trump-after-marriage.png`.

## Notes

- The animation polish (per-row slide-in, partial-trumping discard
  badge, lazy-revoke "call revoke" affordance) is intentionally
  deferred to Phase 5.1's broader animation pass and the still-
  pending Phase 3.6 penalty-house-rules task.
- If a screenshot doesn't match the description above, stop and
  flag the discrepancy — do not commit further work.
