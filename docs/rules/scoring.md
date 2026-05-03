---
sidebar_position: 7
title: Scoring
---

# Scoring

Scoring is where Thousand earns its name. Each deal contributes points to
**three running totals** (one per player); the first to **1000** wins.

## What you score

Each player's deal score is the sum of:

1. **Card points** captured in tricks ([see values](../equipment/card-ranking)).
2. **Marriage bonuses** declared during the deal (only counted for the
   declaring player).

The total points available in a deal are:

```
120 (cards) + 100 (♥) + 80 (♦) + 60 (♣) + 40 (♠) = 400 maximum
```

## Declarer's contract

The declarer's deal score is compared to their **bid** (the contract):

- **Made the contract** (deal score ≥ bid): the declarer **adds the bid**
  to their running total.
- **Failed the contract** (deal score &lt; bid): the declarer **subtracts
  the bid** from their running total.

The declarer's actual deal score above the bid is **not** counted — only
the bid value is added on success. (Some house rules score the actual
points; see [House Rules](../variations/house-rules).)

## Defenders' score

Each defender independently adds **the points they actually captured** in
the deal (cards + any marriages they declared) to their running total.

:::tip[Why declarer doesn't always want a high contract]
Even though a higher bid scores more on success, defenders score nothing
extra when the declarer wins — but they score everything they capture
*regardless* of the declarer's outcome. Bidding too high to keep them off
points is rarely worth the failure risk.
:::

## Rounding

All deal scores are **rounded to the nearest 5**. (e.g. captured 73 → 75;
captured 67 → 65.) **Marriage bonuses are exact** and not rounded.

## The barrel

When a player's running total reaches **880 points** they go **on the
barrel**:

- They have **3 deals** to score the final **120 points** to reach 1000
  and win.
- During those deals **the score on the barrel is frozen at 880** for that
  player — they cannot lose points or gain points there.
- They must score **at least 120** in *one of the three deals* to win.
- If they fail to win by the end of the third barrel deal, they **fall off
  the barrel** and **lose 120 points** (back to 760).

If two or three players are on the barrel simultaneously, the standard
rule is that only the **last to mount** stays on; the others are knocked
off back to 760. Variants differ — confirm at the table.

## Reaching exactly 1000

A player who reaches exactly **1000 points** wins immediately. If multiple
players cross 1000 in the same deal, the **declarer wins ties**;
otherwise, the player with the **higher total** wins.

## Dump truck (Самосвал) and write-off (Сдача)

The reference book documents two further canonical scoring events:

- **Dump truck (самосвал).** When a running total lands exactly on
  **+555** *or* **−555**, that seat's running total is reset to
  zero. The canonical Russian template ships with this rule **on**;
  see
  [House Rules — Dump truck](../variations/house-rules.md#dump-truck--самосвал).
- **Write-off (сдача).** A declarer who sees that the contract is
  unmakeable may write off the deal at any point before the eighth
  trick: the **full bid** is subtracted from the declarer, and
  **half the bid** is credited to each opponent. Off by default;
  see
  [House Rules — Write-off](../variations/house-rules.md#write-off--сдача).

## Sample running scoresheet

```
Deal | Forehand | Middlehand | Rearhand | Notes
-----+----------+------------+----------+------------------------------
 1   |   +120   |   +35      |  +25     | F bids 120 hearts, makes it
 2   |   -100   |   +60      |  +50     | F bids 100, fails (cards 95)
 3   |   +60    |   +85      |  +90     | M bids 100, fails; R caught marriage
 ... |   ...    |   ...      |  ...     |
```

Continue until one player crosses 1000 (going via the barrel).
