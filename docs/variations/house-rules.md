---
sidebar_position: 6
title: House Rules
---

# House Rules

Beyond the regional variants, almost every regular Thousand table has its
own pet rules. This page collects the **most common** ones — agree which
ones are in play **before** the first deal.

## Dealing & redeal house rules

### 4-nine mandatory redeal

A player dealt **all four nines** in their starting hand may **demand a
redeal** before the auction begins. Almost universally enforced because
holding all four nines means a useless hand (zero card-points and no
chance of any marriage). Some tables make it **mandatory for the
dealer** to redeal even if the player would prefer to play.

### 3-nine optional redeal

A player dealt **three nines** may **optionally request a redeal**. Less
universal than the 4-nine rule but very common, especially with novice
players. Some tables require the dealer to grant the request; others let
the dealer decline once.

### Weak-hand redeal

A "weak hand" entitles the player to request a redeal in some tables.
Definitions vary widely:

- **Strict**: no marriage and no Ace and no card above 10.
- **Loose**: no marriage and no Ace.
- **Counted**: total card-point value in hand below a threshold (e.g. < 14).

### Four-jack redeal

A player dealt **all four Jacks** may request a redeal — analogous to
the four-nine rule but rarer. Some tables also allow the **declarer**
to demand a redeal if the **talon contains three Jacks** (covered also
under [Bad talon redeal](#bad-talon-redeal)).

### Misdeal handling

- **Standard**: same dealer redeals without penalty.
- **Soft penalty** (canonical Russian default): deal moves one seat
  clockwise so the next player redeals (book: *"If a penalty is
  received during dealing, the redeal is done by the next player"*).
- **Flat penalty**: dealer pays a small fixed penalty (e.g. 20 points)
  and redeals.

### Bottom-card guard (Cut-deck safety)

The reference book forbids a 9 or J from landing at the very end of
the cut deck: physical play re-cuts up to three times before
penalising the dealer. Two strategies model the same offence;
combine them at most one at a time — the cross-field invariant
rejects turning both on.

- **On** (canonical Russian default): the shuffle's final step
  swaps the bottom card with the first card that is not a 9 or J
  whenever the offence applies, so the bottom slot is always a Q,
  K, 10, or A. The procedural cut-and-recut penalty cannot fire.
  Deterministic — the swap is a function of the post-Fisher-Yates
  ordering, so the same seed produces the same deck.
- **Off**: leaves the raw Fisher-Yates ordering untouched. A 9 or
  J at the bottom is permitted; tables that want unmodified
  shuffles or that simulate the procedural rule explicitly should
  pin this off and turn the
  [Cut-deck nine/jack penalty](#cut-deck-ninejack-penalty-procedural)
  on.

### Cut-deck nine/jack penalty (procedural)

The procedural alternative to the bottom-card guard: turn the cut
into a real interactive moment. After the shuffle the engine opens
a pre-auction *cut* phase; the seat counter-clockwise of the dealer
clicks `Cut the deck`. A 9 or J at the bottom is a bad cut, the
cutter rotates one seat counter-clockwise, and the deck is
re-shuffled. After three bad cuts the dealer takes a fixed −120
penalty applied immediately and the deal proceeds with the current
ordering — no further re-cuts.

- **Off** (default): the cut is silent and instantaneous; the
  shuffle's bottom card stays untouched. Use this with the
  [Bottom-card guard](#bottom-card-guard-cut-deck-safety) on if you
  want the canonical Russian "no offence ever" semantics.
- **On**: opens the procedural ritual. Requires the bottom-card
  guard to be off (the guard erases the offence the ritual relies
  on). The penalty amount is fixed at 120 points; a configurable
  amount is deferred until a table asks for it.

### All-pass handling (no forced-bid rule)

When no one bids and **neither the forced-opening rule nor the
"bolt"** is in effect, the deal is dead. Tables disagree on what
happens next:

- **Standard**: redeal by the same dealer, no scoring.
- **Pass-out**: deal moves clockwise without scoring.
- **"Распасы" (reverse-scoring)**: the deal is played without trump or
  bidding, and the player who **wins the fewest tricks** scores their
  card-points (or, in some traditions, the player with the **most**
  tricks loses theirs). A way to make every deal count.

## Bidding house rules

### Forced opening at 100

Forehand **must** open at 100; they cannot pass on their first turn.
Speeds up the auction; eliminates the "everyone passes" non-deal.

### Maximum first-round bid

Some tables cap the first-round (pre-talon) bid at **120**; others allow
up to **150** if the bidder has very strong cards. Confirm before play.

### Forced dealer bid (Бовт / Bolt)

If everyone passes, the dealer is forced into a 100 contract. Sometimes
called *бовт* or *болт*. **Pinned on by default in canonical Russian**
(book + video walkthroughs agree the dealer has 100 "hanging" before
forehand acts, so the auction never collapses on all-pass) and standard
in Ukrainian play; optional in Polish, 2-player, and 4-player Configuration A.
Configuration B (dealer sits out) cannot turn this on — the
`forced_dealer_bid_requires_active_dealer` invariant rejects the combination.

:::warning[Same word, two rules]
The Russian word *болт* (and its synonym *палка*) is **also** used for
the **zero-tricks penalty** under
[Penalty house rules](#zero-tricks-penalty-болт--палка) — a completely
different rule. Always agree which "bolt" your table means.
:::

### "Dark" / blind bid

A player may make their first bid **before looking at their hand**
(*в тёмную* / *ciemny* / *blind*). Successful blind bids score
**double**; failed blind bids cost double. High-risk, mostly social.

### Re-entry after pass

In standard rules, **passing is permanent**. Some house rules permit a
player who passed in the first round to re-enter once on a later round —
useful when forehand opens cautiously, the others pass, and forehand
ends up alone on a low contract.

### Contra (defender doubling)

A defender may **double** the declarer's bid before play begins,
asserting they will defeat the contract. The declarer may **redouble**
("rekontra") in response. The bid value at stake is multiplied
accordingly. Common in some Polish tables; rare in Russian play.

### No contract without marriage

Some tables forbid bidding **120 or higher** unless the bidder has a
marriage in their starting hand. A stricter variant caps the maximum
bid at **120 plus the value of marriages already held** — a hand with
no marriage may bid only 100, a hand with the spades marriage may bid
up to 160, and so on.

### Negative-score bidding restriction

A player with a **negative running score** may be barred from active
bidding. They may only receive the minimum forced 100 contract if the
other players pass. Used at tables that don't want a falling player to
escape the hole by gambling on big bids.

### Forced-bid concession

When a player has been **forced into the minimum 100 contract** — by
the forced-opening rule, by the "bolt", or by being the last bidder
left in a stalled auction — and looks at a hopeless hand, some tables
allow them to **concede before play** rather than play out a guaranteed
loss.

The bid amount is deducted from the conceder's score and **distributed
to the other players**. Distribution variants:

- **Equal split**: each non-conceder gets the bid divided equally
  (e.g. 100 split among two defenders → +50 each).
- **Each gets full**: every other player receives the **full bid
  amount** (a stiffer penalty for the conceder; rare).
- **Pre-agreed ratio**: house-defined split.

Sometimes called *сдаться без вскрытия* (concede without opening) when
done before turning the talon over. Distinct from
[pass-the-talon](#pass-the-talon) — that's available to *any* declarer
after seeing the talon; forced-bid concession is reserved for players
who didn't want the bid in the first place.

### Write-off / Сдача

The book's pre-tricks concession. The declarer is prompted **after
seeing the widow** — between talon take and the pass step (Russian /
2-player B), or between talon reveal and the two opponent passes
(Polish 2-card `pass_without_taking`) — to either *Play this hand* or
*Write off*. Choosing to write off subtracts the **full bid** from the
declarer's running total and credits **half of the bid** to each
opponent.

On in the canonical Russian template — the book describes write-off
as a standard pre-play action available to any declarer with full hand
information.

Distinct from [forced-bid concession](#forced-bid-concession), which
only fires on a forced minimum-100 contract pre-play (before the
talon is even revealed).

Split variants:

- **Half to each** (book default): each opponent gets bid ÷ 2.
- **Equal split**: the bid is divided equally among the opponents
  regardless of count (in 2-player play this collapses to the same
  thing as half-to-each; in 3- and 4-player play it splits
  asymmetrically when partnerships are involved).

Pairs naturally with the
[every-third-write-off penalty](#every-third-write-off-penalty),
also on in the canonical template — at most Russian tables the two
rules ride together.

## Talon house rules

### Pass-the-talon

A declarer disgusted with the talon may **concede the deal** before
playing, paying their bid as a penalty. Common at relaxed tables; rare
in serious play.

### Public talon

Some house rules require the talon to be **flipped face-up before the
auction begins**. This makes the auction much sharper and less dependent
on luck. (Reduces strategic depth — most tables don't use this.)

### Talon flip after first auction round

A halfway compromise: the talon stays closed during the first round of
bidding; if the auction continues to a second round, the talon is
flipped. Lets first-round bids stay sharp while preserving talon mystery
for serious bids.

### "Buyback"

The declarer may **discard their entire hand** in exchange for a fresh
deal at a 50-point penalty. Almost never seen in serious play; sometimes
used in family games.

### Hidden talon on 100

If the declarer wins the auction at the **minimum 100** simply because
everyone else passed, the talon is **not shown to the defenders** —
only the declarer sees it. Some tables extend this to any forced 100
contract (bolt or forced-opening). Compensates for being stuck with a
contract you didn't want.

### Bad talon redeal

After winning the auction and revealing the talon, the declarer may
demand a redeal if the talon is worthless by **card-point sum**. The
book's canonical threshold is *"sum in the widow is less than 4"*,
so the rule fires on talons with **fewer than 4 card-points**;
tables that play with the looser "fewer than 5" cutoff configure
the threshold accordingly.

Some tables allow this only on a minimum 100 contract; others let any
declarer request it before the pass-cards step. Listed in the book
among the agreed-in-advance redeal conditions, so off in the
canonical Russian template.

### Two nines in the talon redeal

A sibling rule to **Bad talon redeal** with a different predicate:
the declarer may demand a redeal when the **talon (widow / прикуп)
contains exactly two 9s**, regardless of card-point sum. Distinct
trigger from the card-point threshold — a talon with 2 nines and an
Ace passes the bad-talon-points threshold but still qualifies under
this rule. The book lists it among the agreed-upon redeal conditions.

- **Off**: never offered.
- **Any contract**: offered after talon reveal regardless of bid.
- **Minimum-100 only**: offered only when the contract sits at the
  opening floor (100), mirroring the bad-talon-redeal gate.

If both this rule and bad-talon-redeal fire on the same talon, the
table sees a single offer, not two — the declarer accepts or declines
once.

### Talon re-buy

After the talon is revealed, **another player may "buy it away"** from
the auction winner by naming a higher fixed contract — typically 120,
240, or any value above the current bid. This creates a **second
auction** with full talon information and changes who plays the
contract.

### Open discard

After taking the talon, the declarer's **discards** to each opponent
may be made **face-up** rather than face-down. The defenders gain
information about what the declarer chose to throw away, reducing
talon luck. Mostly a tournament or analysis rule.

## Marriage house rules

### "Spades equals clubs"

Some tables score **♠ marriage at 60** (matching ♣) on the grounds that
40 points isn't worth declaring. Mostly a Ukrainian table tradition.

### Half-marriage capture bonus

A defender who captures **both halves** of a marriage (the K and the Q
of the same suit, in tricks) scores a small bonus — typically **20
points**.

### Trump activation timing

Standard rule: when a marriage is declared, **trump becomes that suit
from the next trick onward**.

Variant: trump takes effect **immediately** on the same trick — the led
K or Q is already trump and outranks any non-trump card already played
to the trick. Changes the strategy of timing marriages.

### Marriage announcement timing

- **Standard**: declared by **leading the K or Q** while on lead. The
  bonus posts immediately.
- **Hand-announcement variant**: a player on lead may **announce a
  marriage from the hand without leading either K or Q**, then lead a
  different card. Trump still switches to the marriage suit. Rare;
  changes strategy substantially.
- **Pre-trick variant**: marriages must be announced **before the first
  trick of the deal** in some traditions. Rare.

### Drowned marriage

If a player holds half a marriage (K or Q of some suit) and an opponent
captures the other half in a trick **before** the marriage is declared,
the marriage is *drowned*:

- **Standard**: the marriage simply cannot be declared; no bonus, no
  trump change.
- **Cancellation variant**: if the marriage was declared earlier and
  later "drowned" by capture, the bonus is retroactively cancelled.
  Almost never used — confusing scoring.

### Ace marriage / Тузовый марьяж

A player holding **all four Aces** may declare an **ace marriage**,
typically worth **+200 points**. Variants:

- **Trick required**: the player must already have taken at least one
  trick before declaring.
- **First-lead allowed**: declaration is legal on the very first lead
  of the deal.
- **First-Ace-led sets trump**: the suit of the first Ace led after
  declaration becomes trump (ace marriage replaces the usual K-Q
  marriage as the trump trigger).
- **No trump effect**: the ace marriage scores points but does not
  change the trump suit.

### One trump per deal

Only the **first declared marriage** sets trump. Later marriages still
**score their bonus**, but they **do not change the trump suit**. Used
at tables that find mid-deal trump-flipping confusing.

### Marriage trick required

The book's standard rule: a player may declare a **K-Q (trump)
marriage** only after the seat has already **captured at least one
trick** in the current deal. The same gate applies uniformly to the
**four-aces (ace) marriage**.

- **On** (book default): every marriage declaration — K-Q or four-aces,
  on lead or via hand-announcement / pre-first-trick — requires a
  prior captured trick. The pre-first-trick announcement window is
  effectively unusable under this rule because no seat has any
  captured tricks yet.
- **Off** (trickless variant): declarations are legal at any phase,
  including the first lead and the pre-first-trick window. Tables that
  use the pre-first-trick announcement timing or want to give the
  declarer a strong opening line typically pin this off.

## Trick-play house rules

### Partial trumping

A defender who **cannot beat** an existing trump but holds a lower trump
is, at some tables, **allowed** to discard rather than play the lower
trump. Standard Thousand requires playing the trump.

### Lazy revoke

Misplays (failure to follow / overtake / trump) are punished only when
**caught and called** before the next trick is led. After the next lead
the misplay stands. Useful for casual play.

### Last-trick bonus

The winner of the **final (8th) trick** earns a small bonus — typically
**+10 points** — added to that side's deal score. Common at many Russian
and Polish tables; reduces the dominance of the marriage.

### Slam bonus

If the declarer wins **all 8 tricks** of the deal:

- **Off**: no bonus, just the card-points and any marriages.
- **Fixed bonus**: a flat +X points (commonly +60 or +120).
- **Doubled bid**: the contract value is doubled on success.

A defender side analogously may get a **slam-against** bonus if the
declarer takes **zero tricks** (typically only relevant for mizère
contracts).

### Lead-trump-after-marriage

After declaring a marriage, the declarer **must lead trump on the next
trick** (not just the K or Q of the marriage). Some tables enforce this
as a strategy lock; most do not.

## Scoring house rules

### Rounding granularity

- **Standard**: card-point totals rounded to nearest **5**; marriage
  bonuses are exact.
- **Coarse**: round to nearest **10** — popular in fast tables.
- **Exact**: no rounding at all — popular in tournament play.

### Score actual points on success

- **Standard**: declarer scores the **bid value** on success (any extra
  points captured do not count).
- **Actual-points variant**: declarer scores the **larger of bid or
  actual deal points** on success. Reduces over-bidding pressure.

### Defender contributions

- **Standard**: each defender independently scores the points they
  captured (cards + own marriages).
- **Pooled variant**: the two defenders' captured points are summed and
  split equally. Almost never used outside partnership variants.

### Declarer rounding before contract check

Some tables **round the declarer's captured points before** comparing
to the bid. A captured 118 against a 120 bid rounds up to 120 and
**makes the contract**. Forgiving to near-misses; reduces over-bidding
caution.

### Failed-contract distribution

When the declarer **fails their contract**, the bid amount is deducted
from their running total. Where the points "go" varies:

- **Standard**: the points are simply lost — the declarer's individual
  loss; defenders are unaffected.
- **Split among defenders**: the bid is divided equally among the
  defenders and added to their scores.
- **Each defender gets the full bid**: a much stiffer penalty.
- **Mirrors forced-bid concession**: if the failed contract was a
  forced bid, the same distribution rule applies. (Most consistent
  choice.)

Significantly changes the risk profile of bidding. The standard rule
keeps Thousand a "race to 1000"; the distribution variants make it more
of a zero-sum chase.

## Opening-game house rules

### Golden deal / Золотой кон

During the **first N deals** (usually equal to the number of players,
so 3 in a 3-player game) every player in turn must play a **mandatory
120 contract**. The deal scores, penalties and bolts are commonly
**doubled**.

Variants:

- **Marriages doubled**: marriage values count double during golden
  deals (most common).
- **Marriages not doubled**: only card-points and contract penalties
  double.
- **If nobody makes 120**: scores reset and the normal game begins,
  *or* the golden round is replayed, *or* the game proceeds with the
  failures recorded.
- **Bidding allowed**: some tables let players bid above 120 during
  golden deals; others lock the bid at exactly 120.
- **Blind play allowed**: some tables forbid blind bids during the
  golden round.

A high-stakes opening that quickly punishes weak hands and rewards
strong ones.

## Barrel house rules

### Barrel deals

- **Standard**: 3 deals on the barrel.
- **Strict**: 1 deal only — make 120 or fall off.
- **Lenient**: unlimited until you make it or another player wins.

### Barrel collisions

- **Last-mounted survives** (standard).
- **All collide → all fall off**.
- **First-mounted survives** (rarer).
- **Coexist** — every on-barrel unit stays mounted simultaneously,
  each running its own `deal_count` countdown independently. Listed in
  the book as an agreed-in-advance variant: when more than one unit
  reaches the threshold, no eviction takes place.

### Barrel penalty

- **Standard**: −120 to a final 760.
- **Mild**: barrel resets, no penalty (return to 880).
- **Harsh**: −240 (back to 640).

### Three-falls barrel reset

The book's "if a player sat on the barrel 3 times and then fell off
it, all results are reset to zero" rule. The third fall **overrides**
the standard [barrel penalty](#barrel-penalty) and zeroes the
running total instead of deducting 120.

- **Off**: every fall applies the standard barrel penalty; the seat
  keeps any other accrued points.
- **On** (canonical Russian default): the engine tracks per-seat
  barrel-fall counters across the game; on the third fall the
  running total drops to zero and the counter clears.

### Barrel-jump penalty

Bidding **far above** the 120 needed (e.g. 200) while on the barrel and
failing incurs an extra penalty in some tables — typically the bid
amount instead of the standard −120. Discourages "hero" bids.

### Multiple players on the barrel

Standard rules force a [collision](#barrel-collisions) when a second
player reaches the barrel. A relaxed variant allows **two or more
players to sit on the barrel at the same time**, each running their own
3-deal countdown independently. First to make 120 wins; the others can
still fall off normally.

### Alternative barrel threshold

Some tables move the barrel from **880 to 900**, or add an
**intermediate "pit" score** (e.g. an at-700 lock-in) that players must
clear before approaching the barrel. Effects vary heavily — define
explicitly before play.

### Reverse barrel

A symmetric variant for failing players: at **−880**, a player enters a
**reverse barrel**. They have 3 deals to reach −1000 (which would lose
the game outright); if they fail to do so, they **fall back** to a
pre-agreed score such as −760 or −500. Rare; mostly a cruel
add-on for long sessions.

## Endgame house rules

### Target score

The default goal is **1000 points**, but tables disagree:

- **Standard**: first to **1000** wins. Game length: roughly 6–10
  deals at a typical pace.
- **Short**: first to **500** for a quick game (kid-friendly).
- **Long**: first to **1500** for serious players.
- **Tournament**: first to **2500** — significantly longer; usually
  paired with stricter scoring rules.

### Going over the target

If a player exceeds the target in a single deal:

- **Standard**: the player wins immediately at whatever the actual
  score is.
- **Exact rule**: a player must reach **exactly the target** to win.
  Exceeding it caps at `target − 1` and the deal continues.

### Tiebreakers

If two players cross the target in the same deal:

- **Standard**: the declarer wins ties.
- **High score**: highest running total wins.
- **Continuation**: continue play with the threshold raised by **+500**.

### Dump truck / Самосвал

If a player's running score lands **exactly on the threshold** (most
commonly **+555**), their score is **reset to zero**. Pure
kitchen-table folklore but widely known and frequently played.

- **Positive only**: only the positive threshold triggers the reset
  (most common at non-Russian tables).
- **Both signs**: positive and negative thresholds both trigger.
  This is the canonical Russian default per the reference book —
  Russian Thousand ships with `dump_truck = "both_signs"`.

The exact threshold is configurable as a sibling toggle: tables that
play with **+550** instead of **+555** use the same rule with a
shifted landmark. Bounded in [100, 1000]; thresholds not divisible by
5 rarely fire because scoring rounds running totals to multiples of 5.

## Special contracts

In addition to a numeric bid, some traditions allow **named contract
bids** that change the scoring rules of a single deal.

### Mizère / Минимум

Declarer commits to taking **zero tricks** in a no-trump deal. Fixed
contract value (commonly 120). Defenders try to force tricks on
declarer. Already noted under [Russian variant](./russian.md);
widespread informally.

### Slam contract

Declarer commits to taking **all 8 tricks**. Common contract values:
**240**, **300**, or simply double the highest numeric bid. Failing
loses the slam value as a penalty.

### Open hand

Declarer plays the **entire deal face-up** — all opponents see the
declarer's hand. Scoring is **doubled** on both success and failure.
Almost exclusively a tournament curiosity.

## Penalty house rules

### Revoke penalty

- **Standard**: declarer's full bid awarded to the opposing side.
- **Flat**: 120 points awarded regardless of bid.
- **Configurable**: a fixed house-defined amount.

### Talon-look penalty

Looking at the talon before the auction ends:

- **Standard**: 120 points deducted from the offender; deal redealt.
- **Stricter**: deal forfeited; opposing side awarded the bid.

### Showing-hand penalty

Deliberately or accidentally showing one's hand to an opponent:

- **Standard**: small fixed penalty (typically 20 points).
- **Strict**: full bid penalty.

### Zero-tricks penalty (Болт / Палка)

A player who takes **no tricks at all** in a deal earns a "bolt"
(*болт*, also *палка* — "stick"). After accumulating a threshold of
bolts (commonly **3**), the player receives a fixed penalty (commonly
**−120**) and the bolt counter clears.

Variants:

- **Three consecutive bolts** (counter resets on any trick taken).
- **Any 3 bolts during the game** (cumulative; never resets) — this
  is the canonical Russian default and matches the book's "every
  three sticks scored in the game" wording.
- **Bolts doubled during golden deals** (when the
  [Golden deal](#golden-deal--золотой-кон) rule is active).
- **Dark-game stick doubling** — a stick earned on a deal where the
  seat opened with a [blind / dark bid](#dark--blind-bid) counts as
  two sticks. The book frames this as standard for dark games; off
  by default in the canonical template.
- **Declarer exempt** — only defenders can earn bolts (rare).

:::warning[Same word, different rule]
This is **not** the same as the [forced dealer
bid](#forced-dealer-bid-бовт--bolt) — that's also called *болт* in
some traditions but means a forced 100 contract, not a zero-tricks
penalty.
:::

### Every-third-write-off penalty

A counter sibling to the zero-tricks bolt: every time a seat reaches
the configured number of [write-offs](#write-off--сдача) (usually 3),
a fixed −120 penalty fires and the write-off counter clears. The
threshold is configurable in `[2, 5]`; the penalty amount is
configurable in `[0, 240]`.

On in the canonical Russian template (penalty system entry #5 in the
reference book); pin it off at non-Russian tables that don't take
write-off seriously.

### No-win-streak penalty

The book's "no win for 3 rounds in a row or in total" rule. A seat
that fails to win a deal (declarer making contract, or defender
capturing positive deal points) for the configured number of deals
earns a fixed −120 penalty and the streak counter clears.

Variants:

- **Off**.
- **Consecutive three**: the counter resets on any winning deal;
  three losses in a row trip the penalty.
- **Any three** (canonical Russian default): cumulative across the
  game; only the penalty trigger resets the counter. Matches the
  book's "or in total" wording, mirroring the every-third-stick
  accumulation pattern above.

Threshold is configurable in `[2, 5]`; penalty amount in `[0, 240]`.

### Cross / Крест

An alternative penalty path for a failed contract. Instead of the bid
being deducted immediately, the failing declarer receives a **cross**;
defenders may receive **bolts** instead of points. After accumulating
**2 crosses**, the declarer receives a fixed penalty (commonly **−120**)
and the cross counter clears. Local; rarely seen outside specific
regional traditions.

---

There is **no wrong choice** here — but mismatched expectations cause
more arguments than any other element of Thousand. If a rule isn't on
this page, **ask before you bid**.
