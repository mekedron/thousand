# Special contracts (mizère / slam / open hand) — manual smoke check

Phase 3.6 task: "Implement special contracts" — wires the three named
contracts end-to-end. Engine math is pinned by
`tests/spec/core/scoring_spec.lua`; session wiring by
`tests/spec/app/session_special_contracts_spec.lua`; view-model and
banner rendering by
`tests/spec/app/table_view_model_spec.lua` and
`tests/e2e/journeys/special_contracts_journey_spec.lua`. This script
exists so the human can confirm the auction buttons, the active-
contract banner, and the open-hand face-up rendering all behave
correctly under Love2D — busted's `love`-mock harness cannot exercise
the actual draw path.

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

For each step below, save a screenshot
(`Cmd-Shift-4` → click the Love2D window on macOS) into this
directory.

### 1. Auction buttons appear under `named_contracts = "on"` → `auction_buttons.png`

1. Main menu → Templates → clone "Russian Thousand".
2. Editor: set **Named contracts** = on, **Mizère** = on,
   **Slam contract** = on, **Open hand** = on. Save as `Smoke —
   specials`.
3. Use → start a new game.
4. Expected on the first auction panel: three new bid buttons
   alongside the numeric ones — `Mizère (120)`, `Slam (240)`,
   `Open hand (200)`. Each button should be enabled.
5. Screenshot the auction panel.

### 2. Mizère contract → `mizere_banner.png`

1. With the same template, click `Mizère (120)` as forehand.
2. Other seats pass.
3. Talon reveal proceeds normally. After taking and passing, expected:
   a purple banner above the table reading `Mizère — declarer must
   take 0 tricks (120)`.
4. Screenshot the table during the tricks phase.
5. Try clicking a K or Q while on lead with a marriage in hand:
   expected — the marriage modal **does not** appear, or if it does,
   the declaration is rejected with a localised error
   (`marriages_disabled_in_mizere`).
6. Play out 8 tricks. If declarer takes any trick, expected
   deal-done banner shows `−120` on the declarer's scoreboard row;
   if declarer takes 0 tricks, `+120`.

### 3. Slam contract → `slam_banner.png`

1. Restart, click `Slam (240)` as forehand. Others pass.
2. Expected: a purple banner above the table reading `Slam —
   declarer must take all 8 tricks (240)`.
3. Screenshot the tricks phase.
4. Play through. On a clean sweep, deal-done shows `+240`. Otherwise
   `−240`.

### 4. Open-hand contract → `open_hand_face_up.png`

1. Restart, click `Open hand (200)` as forehand. Others pass.
2. Expected: a purple banner above the table reading `Open hand —
   declarer plays face-up (200)`.
3. **Most importantly:** the declarer's hand renders **face-up** in
   the opponent seat boxes (instead of the usual face-down stack).
   Every defender can read the declarer's cards.
4. Screenshot the table from a defender's perspective showing the
   declarer's cards face-up.
5. Play through. Success (declarer captures ≥ 100) → `+200`;
   failure → `−200`.

### 5. Custom `slam_contract_value` → `slam_custom_value.png`

1. Editor → clone the smoke template → set **Slam contract value** =
   300. Save as `Smoke — slam 300`.
2. Use → new game → click `Slam (300)` button. Expected button
   label shows `Slam (300)`; the active-contract banner reads
   `Slam — declarer must take all 8 tricks (300)`.
3. Screenshot the auction panel and the tricks-phase banner.

## What to escalate

- Clicking a named-contract button does **not** advance the auction
  → check `Session:bid_named_contract`.
- Talon never reveals after a named bid wins → on_auction_end stub
  may have crept back in.
- Declarer's hand renders face-down under open-hand → check the
  view-model `declarer_hand_open` flag and `draw_opponents` branch.
- Marriage modal still appears under mizère → the
  `marriages_disabled_in_mizere` guard in `Session:declare_marriage`
  isn't firing.
- Banner wording is in English when locale = ru/pl/uk → the
  i18n keys (`scene.table.special_contract.*_banner`) need
  translation. Phase 9 covers this; for the smoke check, English is
  fine.
