# Manual smoke — render the playable table state

The e2e harness uses a pure-Lua love-mock and asserts that text labels
and shape primitives reach the recording. This script covers what the
mock cannot: the visual result inside a real Love2D window.

## Prerequisites

- Love2D 11.x on PATH.
- Run from the repo root: `love .`

## Steps

1. **Launch.** `love .` — the main menu opens.
2. **Start a game.** Click **New Game**.

   Verify on the table screen:
   - **Top strip** shows two face-down stacks labelled **Player 2** and
     **Player 3**, each with `7 cards` to the right of the stack. One
     of them carries a small yellow `D` dealer badge.
   - **Centre band** shows a `Talon` label with a 3-card face-down
     stack underneath, and on the right, four labelled rows:
       - `Bid    —`
       - `Turn   Player 2` (the cyan colour means "this seat is the
         current actor" — distinct from the yellow keyboard focus).
       - `Trump  —`
       - `Phase  Auction`
   - **Bottom strip** shows **Your hand** with 7 face-up cards. Each
     card displays a rank letter ("9", "J", "Q", "K", "10", "A") in the
     top-left, and a coloured suit shape (red diamonds/hearts, dark
     clubs/spades) drawn just below — NOT a tofu box. The shapes are
     primitives because LÖVE's default font has no Unicode coverage for
     ♠♣♦♥; Phase 4 will replace these with proper card art.
   - **Right column** shows `Score`, then three rows
     `Your hand · 0`, `Player 2 · 0`, `Player 3 · 0`. The `Player 2`
     row is highlighted in cyan because it is their turn.
   - **Top-right** shows the `Menu` button. **No yellow focus ring**
     should be visible on it on entry.
3. **Press Tab.** The Menu button gains a yellow focus outline. Press
   Tab again — the outline disappears (toggle). Same as the menu /
   end-of-game scenes.
4. **Click Menu.** Returns to the menu. The focus ring should NOT be
   visible on any menu button on entry. Press Tab — focus appears on
   New Game; press Tab again — focus advances past the disabled
   Continue/Abandon buttons to Quit.
5. **Click Continue.** Returns to the same table — same hand layout
   should appear (the session is preserved). The yellow `D` dealer
   badge should be on the same seat.
6. **Click Menu, then Abandon.** Confirm-abandon modal opens with the
   Cancel button focused (yellow outline). Press Esc to close. Press
   Abandon again, then click `Yes, abandon`. The session clears;
   Continue and Abandon grey out again.
7. **Resize the window** through several sizes (drag the corner): the
   bottom hand strip reflows so all 7 cards fit, the scoreboard column
   stays anchored to the right, and the Menu button stays in the
   top-right.
8. **Visual check on cards specifically**:
   - Hearts: red curved shape (two lobes + triangle).
   - Diamonds: red rotated square.
   - Clubs: dark three-circle cluster + stem.
   - Spades: dark inverted heart + stem.

If anything renders as a tofu glyph (`□`), an unexpected colour, or
overlaps a neighbouring region, save a screenshot here and flag it.

## Optional — end-of-game render

Until input wiring lands, the end-of-game scene is reached only via
unit/e2e tests. To smoke it manually:

```bash
love . # then close the window
```

The unit test `tests/spec/ui/scenes/end_of_game_spec.lua` and the e2e
journey `tests/e2e/journeys/end_of_game_render_spec.lua` both exercise
the rendering with a finished session injected. If you want a real
window, add a temporary debug shortcut in `main.lua` to
`manager:set_session(Session.from_state{ ... winner = 1 })` followed by
`manager:switch_to("end_of_game")`, but DO NOT commit that.
