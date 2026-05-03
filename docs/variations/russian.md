---
sidebar_position: 1
title: Russian Thousand
---

# Russian Thousand (*Тысяча*)

The variant treated as **canonical** throughout this documentation. Russian
Thousand is widespread across the former Soviet Union and is the version
implemented in most online card platforms (Mail.ru, Yandex Games, etc.).

## Defining features

- **3 players**, 24-card deck, 7-card hands, 3-card talon.
- Bid increments of **5 below 200**, then **10**.
- Marriages **100 / 80 / 60 / 40** (♥ / ♦ / ♣ / ♠).
- **Must-beat** and **must-trump** rules strictly enforced.
- Barrel at **880**, three deals to make 120, fall-back is **−120**.
- Score rounded to nearest **5**.

## Canonical defaults (book "common standard")

The reference book lists these rules as part of the standard
1000 ruleset rather than as agreed-in-advance house rules, so the
canonical Russian template ships them **on**. They appear in the
deal scoreboard from the first scored deal:

- **Marriage requires a captured trick.** A K-Q (or four-aces)
  marriage may only be declared once the seat has captured at least
  one trick in the current deal. See
  [House Rules — Marriage trick required](./house-rules.md#marriage-trick-required).
- **Misdeal moves the deal clockwise.** A penalty during dealing
  rotates the dealer one seat clockwise so the next player redeals
  (book: *"If a penalty is received during dealing, the redeal is
  done by the next player"*). See
  [House Rules — Misdeal handling](./house-rules.md#misdeal-handling).
- **Bottom-card guard.** The shuffle deterministically swaps a safe
  partner into the bottom slot when Fisher-Yates would have placed
  a 9 or J there, so the book's procedural cut-and-recut rule never
  fires. See
  [House Rules — Bottom-card guard](./house-rules.md#bottom-card-guard-cut-deck-safety).
- **Every-three-sticks (Болт / Палка) penalty.** A seat that takes
  zero tricks in a deal earns a *stick*; on every third stick a
  fixed −120 penalty fires and the counter clears. See
  [House Rules — Zero-tricks penalty](./house-rules.md#zero-tricks-penalty-болт--палка).
- **No-win-streak penalty.** A seat that fails to win for three
  deals (in a row or in total) takes a fixed −120 penalty and the
  streak counter clears. See
  [House Rules — No-win-streak penalty](./house-rules.md#no-win-streak-penalty).
- **Write-off / Сдача mid-deal concession.** A declarer who sees the
  contract is unmakeable may write the deal off between tricks: the
  full bid is subtracted from the declarer and half the bid credited
  to each opponent. See
  [House Rules — Write-off](./house-rules.md#write-off--сдача).
- **Every-third-write-off penalty.** Cross-deal sibling of the
  zero-tricks penalty: every third write-off across the game fires
  a fixed −120 penalty and the counter clears. See
  [House Rules — Every-third-write-off penalty](./house-rules.md#every-third-write-off-penalty).
- **Three-falls barrel reset.** A seat that has fallen off the
  barrel three times has its running total reset to zero on the
  third fall ("Reset to zero. Occurs … if a player sat on the
  barrel 3 times and then fell off it"). See
  [House Rules — Three-falls barrel reset](./house-rules.md#three-falls-barrel-reset).
- **Dump truck (Самосвал) ±555 reset.** When a running total lands
  exactly on **+555** *or* **−555**, that seat's running total is
  reset to zero. See
  [House Rules — Dump truck](./house-rules.md#dump-truck--самосвал).
- **Forced dealer 100 (Бовт / Bolt).** The dealer is implicitly
  committed to a 100 contract before the auction starts; if both
  opponents pass without overcalling, the dealer takes the deal at
  100 automatically. The auction can never collapse on all-pass —
  every deal has play. See
  [House Rules — Forced dealer bid](./house-rules.md#forced-dealer-bid-бовт--bolt).

## Defaults off (agreed-in-advance under Russian play)

The reference book treats these explicitly as **agreed by the
parties before the start** rather than part of the common standard.
The canonical template leaves them off; pin them on per-table by
cloning the Russian template and editing.

- [Four-nine redeal](./house-rules.md#4-nine-mandatory-redeal),
  [three-nine redeal](./house-rules.md#3-nine-optional-redeal),
  and the [weak-hand redeal](./house-rules.md#weak-hand-redeal)
  ("total points of any participant are less than the agreed
  amount, usually 13–15").
- [Bad talon redeal](./house-rules.md#bad-talon-redeal) ("sum in
  the widow is less than 4") and the
  [two-nines-in-the-talon redeal](./house-rules.md#two-nines-in-the-talon-redeal).
- [Ace marriage / Тузовый марьяж](./house-rules.md#ace-marriage--тузовый-марьяж).
- [Golden deal / Золотой кон](./house-rules.md#golden-deal--золотой-кон).
- [Dark-game stick doubling](./house-rules.md#zero-tricks-penalty-болт--палка)
  (book: stick "may be doubled" in a dark game — a variant rather
  than part of the common standard).
- [Coexist barrel collision](./house-rules.md#barrel-collisions)
  (multiple seats on the barrel simultaneously).

## Notable Russian conventions

### Forehand opens or passes

Forehand is **forced to open the auction** at 100, OR to pass. Other players
may then continue to bid as normal.

### "Дать в темную" (blind bidding)

A bidder may bid an extra 10 points **without looking at the talon** even
after winning the auction. This sight-unseen raise multiplies the bid (some
tables: ×2 on success, ×2 on failure).

### Penalty for revoking

A player who fails to follow suit, fails to overtake, or fails to trump
when required typically pays the **declarer's full bid** to the opposing
side. (Some tables: a flat 120 penalty regardless of bid.)

### Mizère / 'no tricks' contracts

Some Russian tables include a special **"mizère" / "минимум"** call:
declarer commits to taking **zero tricks** in a no-trump deal for a fixed
score (typically 120). Defenders try to force tricks on declarer.

## Differences vs. Polish *Tysiąc*

The Russian and Polish games are recognisably the same game; the chief
differences are:

| Feature | Russian | Polish |
|---|---|---|
| Marriage ♥ | 100 | 100 |
| Marriage ♦ | 80 | 80 |
| Marriage ♣ | 60 | 60 |
| Marriage ♠ | 40 | 40 |
| "Must-trump" rule | Yes | Yes (sometimes called *przebijanie*) |
| Talon size | 3 cards | 2 cards (one each to two opponents) |
| Bidding minimum | 100 | 100 |
| Mizère contract | Yes (informal) | Rarer |

See [Polish Tysiąc](./polish) for full details.
