# Manual smoke check — Connect hot-seat input to the rules engine

Per [memory: smoke testing — hand the script over](../../../../.claude/projects/-Users-nikita-Projects-thousand/memory/feedback_smoke_testing.md),
this script is for the developer to run by hand. **Do not** drive Love2D
through computer-use or MCP — those workflows have proven unreliable for
this codebase.

## Pre-flight

```sh
make run            # Launches `love .` from the repo root.
```

Window opens at the Thousand main menu.

## Steps

Take a screenshot at every numbered step and save to
`tests/e2e/screenshots/connect-hot-seat-input/<NN>-<short-slug>.png`.

1. **Menu render.** Title "Thousand" and four buttons: New Game,
   Continue (greyed), Abandon Game (greyed), Quit. Save as
   `01-menu.png`.

2. **Start a new game.** Click **New Game**. The table scene loads
   with:
   - Two opponent stacks across the top (`Player 1`, `Player 3`).
   - Centre band with `Bid —`, `Turn Your hand`, `Trump —`,
     `Phase Auction`.
   - Active hand at the bottom labeled `Your hand`, **sorted**: spades
     first, then clubs, diamonds, hearts; each suit ordered 9, J, Q, K,
     10, A.
   - Bid panel below the centre band: five buttons `Bid 100`,
     `Bid 105`, `Bid 110`, `Bid 115`, `Bid 120`, plus `Pass`.
   - Top-right `Menu` button.
   Save as `02-fresh-table.png`.

3. **Hover a card.** Move the cursor over any card in the bottom
   strip. The hovered card lifts ~12 pixels. Save as `03-hover.png`.

4. **Tab into the hand.** Press **Tab**. A yellow focus outline
   appears on the first card. Press **Right** a few times to walk
   through cards, then **Down** through panel buttons. The focus
   outline tracks. Save as `04-keyboard-focus.png`.

5. **Bid 100.** Click `Bid 100`. The bid panel re-renders for player 3
   (centre band updates `Bid 100  Player 2`, `Turn Player 3`). The
   active hand at the bottom becomes player 3's. Save as
   `05-after-bid.png`.

6. **Two passes.** Click `Pass`, then `Pass` again on the next turn.
   The auction terminates with player 2 as declarer. The talon flips
   face-up in the centre. The panel becomes a single `Take talon`
   button. Save as `06-talon-revealed.png`.

7. **Take talon.** Click `Take talon`. Player 2's hand grows to 10
   cards. A label `Pass card to Player 1` (or `Player 3`) appears
   above the hand. Save as `07-take-talon.png`.

8. **Pass two cards.** Click any two cards in succession to pass them
   to the named opponent. After the second click, the panel becomes
   `Raise to ...` buttons + `Keep bid at 100`. Save as
   `08-after-pass.png`.

9. **Skip raise.** Click `Keep bid at 100`. The phase indicator
   changes to `Tricks`. The hand has 8 cards. Save as
   `09-tricks-start.png`.

10. **Lead a non-marriage card.** Click any card in the active hand
    that is **not** part of a held K+Q pair. The card flies to the
    centre under `Led:` plus the suit symbol. Turn rotates clockwise.
    Save as `10-first-trick.png`.

11. **Marriage prompt.** Drive the deal until you can lead a K or Q
    of a suit you also hold the matching K/Q for. Click that card.
    Modal appears: `Declare marriage in: ♠` (suit primitive), with
    `Declare` / `Just play` buttons. Pick `Declare`. The bonus
    posts; the trick begins under no-trump; the next trick has the
    suit symbol next to `Trump`. Save as `11-marriage.png` and
    `12-trump-engaged.png`.

12. **Illegal play (optional).** Try clicking a card that breaks
    must-follow / must-trump. Engine rejects; a localised toast
    appears at the bottom of the centre band reading `Not your
    turn` or `Illegal play: ...`. Save as `13-toast.png`.

13. **Deal-done banner.** Continue clicking legal cards until the
    eighth trick resolves. The centre fills with a banner
    `Deal complete` plus per-player running totals, and a panel
    button `Next deal` appears. Click `Next deal`; a fresh deal opens
    with the dealer rotated to player 2. Save as `14-deal-done.png`
    and `15-next-deal.png`.

## Pass criteria

A run **passes** when every screenshot above is captured and shows the
described state. If any of the four task acceptance bullets is not
visible after this script:

- card hit-tests work,
- auction UI lets each player bid or pass in turn,
- talon reveal + pass-card interactions are playable,
- marriage declaration appears when leading K or Q of a held marriage,

stop and fix before committing.

## Troubleshooting

- If the bid buttons render with `%{amount}` instead of numbers, the
  Button widget's `label_params` plumbing is broken — check
  `ui/button.lua:Button:draw`.
- If a card click never registers, the rebuild-on-every-frame bug has
  regressed — check `ui/scenes/table.lua:_rebuild_panel_if_needed` and
  the pending-card reconciliation in `mousereleased`.
- If suit symbols render as boxes near `Led:` or in the marriage
  prompt, the LÖVE default-font workaround has regressed — both should
  use `cards.draw_suit` primitives, never Unicode glyphs.
