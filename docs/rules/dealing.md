---
sidebar_position: 2
title: Dealing
---

# Dealing

The dealer shuffles the **24-card deck**, offers it to the player on their
right to cut, then deals as follows.

## The deal pattern

For three players, the standard pattern is:

```
3 + 3 + 3   to each player                (9 cards dealt, 0 in hand)
2 cards     to the talon (face down)
2 + 2       to each player                (15 dealt, 2 in talon)
1           to the talon (face down)
2 + 2       to each player                (21 dealt, 3 in talon)
```

Result:

- Each player has **7 cards in hand**.
- Three cards form the **talon** (also called the **widow** or **prikup**),
  face down in the centre of the table.
- All 24 cards have been dealt: `3 × 7 + 3 = 24`.

:::tip[Alternative deal patterns]
Some tables simply deal **7 cards each** in any pattern, then put the
remaining **3 cards face down** as the talon. Mathematically identical, just
quicker. Agree before the first hand which pattern you use.
:::

## Dealer responsibilities

- The dealer must **not look at the talon** while dealing.
- A misdeal — a card revealed, the wrong number of cards dealt, or a card
  exposed in the talon — moves the deal **one seat clockwise** so the
  next player redeals (book: *"If a penalty is received during dealing,
  the redeal is done by the next player"*). House rules differ on
  whether the same dealer redeals without penalty or pays a small flat
  penalty instead — see
  [House Rules — Misdeal handling](../variations/house-rules.md#misdeal-handling).

## Cut-deck ritual (optional)

The reference book describes a cut-and-recut ritual: after the shuffle,
the participant **counter-clockwise of the dealer** cuts the deck. A
**9 or J at the bottom is a bad cut** — the cutter rotates one seat
counter-clockwise and the deck is cut again. After **three bad cuts**
the dealer pays a fixed penalty (book default 120) and the deal
proceeds with the current ordering.

Two strategies model the same offence; pick exactly one per template:

- **Bottom-card guard** (canonical Russian default,
  `dealing.cut_deck_safety = "on"`): the shuffle deterministically
  swaps a safe partner into the bottom slot whenever a 9 or J would
  land there. The procedural penalty cannot fire; the cut is invisible
  to the player.
- **Procedural ritual** (`dealing.cut_deck_nine_jack_penalty = "on"`):
  the engine opens a pre-auction *cut* phase. The active cutter calls
  `Cut the deck`; a bad bottom rotates the cutter and re-shuffles, a
  good bottom proceeds straight to the auction. The penalty fires on
  the third bad cut.

The two are **mutually exclusive** — combining them produces silent
dead code, so the engine rejects the combination at validation time.
See [House Rules — Bottom-card guard](../variations/house-rules.md#bottom-card-guard-cut-deck-safety)
for the toggle wording.

## Redeal triggers

Before the auction begins, a player who was dealt a hopeless hand may be
entitled to a redeal. Two are near-universal:

- **Four nines.** A player dealt **all four nines** may demand a redeal
  — at most tables this is a *mandatory* right, since holding all four
  nines means a useless hand (zero card-points, no possible marriage).
- **Three nines.** A player dealt **three nines** may **optionally**
  request a redeal. Less universal than the four-nine rule but very
  common.

Variations also exist for "weak hands" (no marriage, no Ace, no card
above 10), and for misdeal handling. See
[House Rules](../variations/house-rules.md#dealing--redeal-house-rules)
for the configurable details — different tables enforce different
combinations of these.

## After the deal

The auction begins immediately. **Forehand** (left of the dealer) is the
first to bid. See [Bidding](./bidding).

:::info[Don't peek at the talon]
Until the auction ends, the talon is sacred. Looking at it ends the deal
with a penalty equal to a typical contract (commonly 120 points) deducted
from the offender's score.
:::
