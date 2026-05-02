# Bidding house rules — manual smoke script

Phase 3.6 bidding-house-rules ships nine new selectable toggles in the
`bidding` section plus three special-contract toggles in `specials`.
Automated unit + integration + e2e specs cover the engine, session,
view-model and table-scene paths (see
`tests/spec/core/auction_spec.lua`,
`tests/spec/app/session_bidding_variants_spec.lua`,
`tests/spec/ui/scenes/table_spec.lua`,
`tests/e2e/journeys/bidding_variants_journey_spec.lua`).
This document is a manual smoke script for the rendered UI.

## Run

```bash
cd /Users/nikita/Projects/thousand
PATH="$PWD/.luarocks/bin:$PATH" love .
```

## Walk-throughs

For every toggle: clone the canonical Russian template, flip the
toggle (and any required sibling), save, apply, and start a new game
with the locked seed `1` (Settings → Developer if present, otherwise
edit `app/session.new` opts in code temporarily). Capture each frame
to `tests/e2e/screenshots/bidding-house-rules/`.

### 1. forced_opening — pass disabled for forehand

1. Set `bidding.forced_opening = on`. Save and start a new deal.
2. Dismiss the privacy curtain to the forehand seat.
3. Expect the auction panel to show bid buttons (100, 105, …, 120) but
   **no Pass button**.
4. Capture as `01-forced-opening-pass-disabled.png`.

### 2. forced_dealer_bid — banner after all-pass

1. Set `bidding.forced_dealer_bid = on`. Save and start a new deal.
2. Pass on every active seat (forehand and middlehand suffice — the
   auction terminates after `pass_count >= player_count - 1`).
3. Expect a banner above the centre band:
   `Player 1 forced to 100`. The session moves into the talon phase.
4. Capture as `02-forced-dealer-bid-banner.png`.

### 3. blind_bid — "Bid blind ×2" button

1. Set `bidding.blind_bid = first_bid_double`. Save and start a new deal.
2. Before dismissing the privacy curtain for forehand, expect the
   auction panel to include `Bid blind ×2`.
3. Capture as `03-blind-bid-button.png`.

### 4. blind_bid — multiplier badge after declaring blind

1. Continue from #3 — tap `Bid blind ×2`.
2. The badge `×2` should appear on the right edge of the centre band.
3. Capture as `04-blind-bid-multiplier-badge.png`.

### 5. re_entry_after_pass — Re-enter button

1. Set `bidding.re_entry_after_pass = on`. Save and start a new deal.
2. Forehand passes; middlehand bids 100; you stay on forehand's
   curtain.
3. Expect a `Re-enter auction` button in the auction panel for the
   passed forehand seat.
4. Capture as `05-re-entry-button.png`.

### 6. contra — Contra button at talon-revealed

1. Set `bidding.contra = contra_only`. Save and start a new deal.
2. Forehand bids 100; middlehand and dealer pass; talon reveals.
3. Switch the curtain to a defender (middlehand or dealer).
4. Expect a `Contra` button in the talon-take panel.
5. Capture as `06-contra-button.png`.

### 7. contra_and_redouble — Redouble button

1. Set `bidding.contra = contra_and_redouble`. Save and start a deal.
2. Drive to talon-revealed as in #6, then tap `Contra` from a
   defender's view.
3. Switch the curtain to the declarer.
4. Expect a `Redouble` button in the talon-take panel; the multiplier
   badge should now read `×2` and switch to `×4` once redouble fires.
5. Capture as `07-redouble-button.png`.

### 8. forced_bid_concession — Concede (split) button

1. Set `bidding.forced_dealer_bid = on` AND
   `bidding.forced_bid_concession = equal_split`. Save and start.
2. Pass on forehand and middlehand to trigger forced-dealer-bid.
3. Expect a `Concede (split equally)` button before the talon reveals.
4. Capture as `08-concede-forced-bid-button.png`.

### 9. no_contract_without_marriage — disabled bids ≥ 120

1. Set `bidding.no_contract_without_marriage = no_120_without_marriage`.
   Pin a deal where the seat on turn holds no marriage (the spec uses
   `tests/spec/app/session_bidding_variants_spec.lua`'s
   `hands_without_marriage()` fixture for a deterministic example).
2. Expect the bid panel to render `Bid 120` greyed out, plus the
   subscript `(no marriage in hand)` above the panel.
3. Capture as `09-no-marriage-disabled-bids.png`.

### 10. negative_score_restriction — locked to 100

1. Edit the template; set `bidding.negative_score_restriction = on`.
   Hand-edit the auto-save (`templates.json`) so a player has a
   negative running total at deal start, then resume the game.
2. Expect the locked seat's bid panel to show only the `Bid 100`
   button, with the banner `Take 100 (negative score)` above the
   panel.
3. Capture as `10-negative-score-locked.png`.

### 11. named_contracts — special-contract buttons

1. Set `bidding.named_contracts = on`, plus `specials.mizere = on`,
   `specials.slam_contract = on`, `specials.open_hand = on`. Save and
   start.
2. Expect the auction panel to render `Mizère (120)`, `Slam (240)`,
   `Open hand (200)` alongside the numeric bid buttons.
3. Tap `Mizère (120)`. The session enters
   `deal_done` with reason `not_yet_supported_named_contract` (a
   stub-error pending the follow-up "Implement named-contract
   scoring & play" task — the bid is accepted, just not playable).
4. Capture as `11-named-contracts-buttons.png` (capture before
   tapping; the post-tap screen is informational only).

## Notes

- All player-facing strings ship as English placeholders in the
  Russian / Polish / Ukrainian locales until a translation pass.
- Per the project's `feedback_smoke_testing` memory, this script is
  meant to be run by hand. The `tests/e2e/journeys/...` spec covers
  the same surface programmatically and is what CI relies on.
- Touch-target floor (64 px) and keyboard navigation (Tab cycles
  focus, Enter activates, Escape dismisses modals) apply to every
  new affordance the same way as the existing panel buttons.
