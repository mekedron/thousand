---
sidebar_position: 0
title: Overview
---

# Variations

Thousand has been played for over a century across Russia, Poland, Ukraine,
the Baltics and beyond. Every region — and arguably every kitchen table —
has its own twist. This section catalogues the variations that come up most
often.

## Why so many variants?

Three forces drive variation in Thousand:

1. **No central rulebook.** Unlike Bridge or Poker, Thousand has no
   federation, no tournament circuit, and no canonical text. Rules are
   passed down orally.
2. **Player count flexibility.** The core 24-card mechanic adapts cleanly to
   2, 3, 4 and even 6 players, each with its own conventions.
3. **The barrel.** The dramatic 880-point endgame invites house-rule
   tweaks: how many barrel deals, what the penalty is, what happens when
   two players reach the barrel together.

## What this section covers

| Variant | Players | Highlights |
|---|---|---|
| [Russian Thousand](./russian.md) | 3 | The default; this site's reference rules. |
| [Polish *Tysiąc*](./polish.md) | 3 | Different marriage values; explicit "must-trump" rule. |
| [Ukrainian Тисяча](./ukrainian.md) | 3 (or 4) | Often played with the *bolt* (declarer-must-bid) variant. |
| [Two-player](./two-player.md) | 2 | Shared face-up talon; closer to Schnapsen. |
| [Four-player](./four-player.md) | 4 | Fixed partnerships; dealer sits out or plays. |
| [House Rules](./house-rules.md) | any | Common kitchen-table tweaks worth agreeing in advance. |

## Comparison with the reference book

The implementation aligns with the "common standard" Russian rules
described in the canonical reference book (see Phase 3.7 of the
project task list). Two items the book describes remain
**deferred** in v1:

- **32-card deck variant.** The book mentions an optional 6–A deck
  with sevens worth 7 points and eights worth 0. v1 ships the
  standard 24-card deck only; the 32-card variant is out of scope
  for the current release.
- **Cut-deck nine/jack penalty.** The book's procedural rule —
  "if a nine or jack ends up at the end of the deck, the deck is
  cut again; on the third occurrence the dealer takes a penalty" —
  is procedural rather than algorithmic and is not a good fit for
  software simulation. The shuffle is reproducible from a seed in
  v1, so the situation cannot arise the way it does at a physical
  table.

Every other rule the book lists as part of the standard penalty
system (the 3-sticks penalty, the dump-truck reset, the
marriage-trick-required precondition) is implemented and pinned on
in the [Russian Thousand](./russian.md) canonical defaults. Rules
the book frames as agreed-in-advance — write-off, every-third-write-
off, no-win-streak, three-falls reset, dark-game stick doubling,
two-nines-in-talon redeal, coexist barrel collision — ship as
selectable [House Rules](./house-rules.md) toggles.

## How to read these pages

Each variation page lists **only the differences** from the standard rules
documented in [Rules of Play](../rules/setup.md). Where a rule is not
mentioned, assume the standard rule applies.

:::tip[Always agree before the first deal]
The most common source of arguments in Thousand is mismatched expectations.
Spend 30 seconds before the first hand confirming:
1. Marriage values.
2. Barrel rules (and barrel collisions).
3. Whether passing the talon is allowed.
4. What happens on a misdeal or revoke.
:::
