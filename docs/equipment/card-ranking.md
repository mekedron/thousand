---
sidebar_position: 2
title: Card Ranking & Values
---

# Card Ranking & Values

In Thousand each card has **two distinct values**: a **rank** that determines
which card wins a trick, and a **point value** that the winning side scores
when the trick is captured.

## Rank order (high to low)

Within any single suit, cards rank as follows during a trick:

```
A  >  10  >  K  >  Q  >  J  >  9
```

:::caution The 10 outranks the King
This is the most common point of confusion for beginners coming from Whist or
Bridge. In Thousand, **the 10 is the second-highest card in every suit**,
beaten only by the Ace.
:::

## Point values

The point value of a card is added to the captured side's score for the
deal:

| Card | Points |
|------|-------:|
| Ace (A)  | **11** |
| Ten (10) | **10** |
| King (K) | **4**  |
| Queen (Q)| **3**  |
| Jack (J) | **2**  |
| Nine (9) | **0**  |

A full deck therefore contains **120 points in cards** per deal
(`(11 + 10 + 4 + 3 + 2 + 0) × 4 = 120`).

## Marriage values

When the same player holds the **King and Queen of one suit** and declares
them, the team scores a **marriage bonus** in addition to any points won in
tricks. Marriage values vary by suit:

| Marriage | Suit symbol | Bonus points |
|---|---|---:|
| Hearts marriage | ♥ K + Q | **100** |
| Diamonds marriage | ♦ K + Q | **80**  |
| Clubs marriage | ♣ K + Q | **60**  |
| Spades marriage | ♠ K + Q | **40**  |

The mnemonic **100 / 80 / 60 / 40** descends through the suits in order
**♥ ♦ ♣ ♠**.

:::info Total possible per deal
With every marriage active and all tricks captured, a single player can score
**120 + 100 + 80 + 60 + 40 = 400 points** in one deal — though this
practically never happens.
:::

See [Trump & Marriages](../rules/trump-and-marriages) for how and when
marriages may be declared.
