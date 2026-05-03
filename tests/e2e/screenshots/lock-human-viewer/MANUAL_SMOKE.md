# Manual smoke test — Phase 4.2 viewer lock

Drop screenshots here if you want a visual record. The pure-Lua
journeys at `tests/e2e/journeys/{single_player,mixed_seats,bot}_journey_spec.lua`
cover the underlying logic; this script is the visual sanity check
against `love .`.

## Setup

```bash
make run        # alias for `love .`
```

Window opens at 1280×720. Active scene: main menu.

## Steps — single-player (lone human)

| # | Action | What you should see |
|---|---|---|
| 1 | Window opens | Main menu with `Single Player` at the top of the column. |
| 2 | Click `Single Player` | Table opens directly. Forehand under canonical Russian dealer 1 is seat 2 (a bot). **The bottom of the table shows seat 1's hand face-up — labelled "Your hand" — even though seat 2 is on turn.** Seat 2's hand is face-down at the top, labelled "Player 2". |
| 3 | Wait ~1 s | "Bot 2 thinking…" banner sits centred at the top of the centre region. **No bid buttons render** while the bot is on turn. |
| 4 | After bot 2 acts | The thinking banner switches to "Bot 3 thinking…". Layout is unchanged: human's hand still at bottom labelled "Your hand", bots face-down at the top. |
| 5 | After bot 3 acts | Privacy curtain raises with "Ready, Player 1?". |
| 6 | Tap to dismiss | Auction bid buttons appear. Human's hand still at the bottom labelled "Your hand". |
| 7 | Click `Pass` | Turn rotates to the next bot. Banner returns; no auction panel. Human's hand stays put. |
| 8 | Press Esc → menu | Continue is enabled. |

**Regression check:** at no point during single-player should a bot's hand appear face-up at the bottom slot. If it does, the viewer-lock has broken.

## Steps — mixed composition (2 humans + 1 bot)

| # | Action | What you should see |
|---|---|---|
| M1 | Click `New Game` | Per-seat picker. Defaults: Seat 1 = Human, Seat 2 = Bot, Seat 3 = Bot. |
| M2 | Click the `Human` segment on Seat 2 | Row 2 flips to Human. |
| M3 | Click `Start` | Forehand seat 2 is human now → privacy curtain raises with "Ready, Player 2?". |
| M4 | Tap to dismiss | Seat 2 sees their hand at the bottom labelled "Your hand"; auction panel renders. |
| M5 | Click `Pass` | Turn moves to seat 3 (bot). **Curtain does NOT raise.** "Bot 3 thinking…" banner appears. **Seat 2's hand stays at the bottom** (the viewer is still seat 2 — no snap-back to seat 1). No bid buttons. |
| M6 | After bot 3 acts | Curtain raises with "Ready, Player 1?". |
| M7 | Tap to dismiss | Seat 1's hand renders at the bottom labelled "Your hand"; bid panel reappears. Seat 2 is now an opponent at the top. |

**Regression check:** during step M5, the hand at the bottom must still be seat 2's (the last revealed human), not seat 1's and not seat 3's. If the bottom slot shows seat 3's bot hand, the viewer-lock has broken; if it shows seat 1's hand, the sticky last-human-viewer logic has broken.

## Steps — all-bot (regression of MANUAL_SMOKE in single-player-and-new-game)

| # | Action | What you should see |
|---|---|---|
| A1 | New Game → toggle every row to Bot → Start | All-bot game. **No privacy curtain.** Auction auto-advances. |
| A2 | Watch the auction | Layout follows current_turn (legacy hot-seat fallback for the all-bot case): each bot's hand briefly appears at the bottom as it acts. This is intentional — there is no human to anchor a viewer on. |

## Screenshots to drop here (optional)

Suggested filenames:

- `01_single_player_bot2_thinking.png` — bot 2 on turn, human (seat 1) hand face-up at bottom labelled "Your hand", "Bot 2 thinking…" banner.
- `02_single_player_bot3_thinking.png` — bot 3 on turn, same layout, banner reads "Bot 3 thinking…".
- `03_single_player_human_curtain.png` — curtain raised for seat 1.
- `04_single_player_human_panel.png` — curtain dismissed, auction panel visible, seat 1's hand at bottom.
- `05_mixed_seat2_curtain.png` — curtain raised for seat 2 in mixed composition.
- `06_mixed_bot3_thinking.png` — bot 3 on turn under mixed composition, seat 2's hand still at the bottom.

These are not committed to git automatically; drop them in this dir
manually if you want them in the PR.
