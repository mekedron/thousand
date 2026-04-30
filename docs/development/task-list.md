---
sidebar_position: 3
title: Task List
---

# Task List

This file is the **living checklist** for building the game. Tick boxes off
as you complete them. Tasks are grouped by phase from the
[Roadmap](./roadmap.md) and ordered by priority **within** each phase.

:::tip[How to use this page]
- **Top-to-bottom is priority order.** Don't skip ahead within a phase.
- A task is "done" when its acceptance line is true and the change is
  merged to `main`.
- If you find a missing task, add it under the correct phase rather than
  inventing a new section.
- A `[P0]` task **blocks the phase** until done. `[P1]` is normal-priority.
  `[P2]` is "nice to have, defer if needed".
:::

Legend: **P0** = blocker, **P1** = normal, **P2** = nice-to-have.

---

## Phase 0 — Project setup

Goal: `love .` opens a window. CI is green on macOS and Linux. The
plumbing every later phase relies on (i18n, settings, save dir) exists
from day one.

- [x] **P0** Initialise Love2D project skeleton (`main.lua`, `conf.lua`, window title, version).
- [x] **P0** Set up the directory layout from [Architecture](./architecture.md): `core/`, `app/`, `ui/`, `assets/`, `tests/`, `platform/`.
- [x] **P0** Add a Lua linter (luacheck) and formatter (stylua) with a single project config.
- [x] **P0** Add a unit-test runner that works on plain `lua` from the command line (e.g. busted) and a `make test` / shell script entry point.
- [x] **P0** GitHub Actions: run lint + tests on every push.
- [x] **P0** **i18n module**: a `t(key, …)` lookup against `assets/i18n/<locale>.lua`. Active locale lives in settings. Stub locale tables for `en`, `ru`, `pl`, `uk` (initially identical to `en`; populated in Phase 8).
- [x] **P0** **Locale fallback**: if a key is missing in the active locale, fall back to `en` and log once per missing key.
- [x] **P1** GitHub Actions: produce a `.love` artifact on every push to `main`.
- [ ] **P1** Project `README.md` at the repo root: how to run, how to test, how to package.
- [ ] **P2** Pre-commit hook running lint + tests locally.
- [ ] **P2** A simple CI check that flags hard-coded user-visible strings outside locale tables.

---

## Phase 1 — Core rules engine (pure Lua)

Goal: every rule from [Rules of Play](../rules/setup.md) implemented and tested. **No Love2D in this layer.**

:::warning[Read from `RuleConfig` from day one]
The engine is **parameterised by a `RuleConfig`** from this phase's
first commit. Phase 1 ships exactly one `RuleConfig` value — the
canonical Russian default — but never hard-codes a value any future
variant could change (talon size, bid increments, marriage values,
barrel rules, …).
:::

### 1.1 Cards & deck

- [ ] **P0** Card type with suit (♠♣♦♥) and rank (9,J,Q,K,10,A).
- [ ] **P0** Card point values: A=11, 10=10, K=4, Q=3, J=2, 9=0.
- [ ] **P0** Card rank order for trick comparison: A > 10 > K > Q > J > 9.
- [ ] **P0** 24-card deck builder.
- [ ] **P0** Deterministic shuffle (seedable, for reproducible tests).

### 1.2 Dealing

- [ ] **P0** Standard 3-player deal: 3+3+3, 2 to talon, 2+2, 1 to talon, 2+2 → 7 each, 3 in talon.
- [ ] **P0** Verify total cards == 24 after every deal.
- [ ] **P1** Misdeal detection (exposed card, wrong count) returns a typed error.

### 1.3 Auction / bidding

- [ ] **P0** Auction state machine starting at forehand, clockwise.
- [ ] **P0** Opening minimum 100; pre-talon maximum 120.
- [ ] **P0** Increments: 5 below 200, 10 from 200 onward.
- [ ] **P0** Pass is permanent; auction ends when two players have passed.
- [ ] **P0** Declarer is the last remaining bidder at their final bid.

### 1.4 Talon, pass and raise

- [ ] **P0** Reveal the 3 talon cards (publicly visible to all players).
- [ ] **P0** Declarer takes talon → 10 cards in hand, opponents at 7.
- [ ] **P0** Declarer passes 1 face-down card to each opponent → 8 / 8 / 8.
- [ ] **P0** Declarer may raise the bid post-talon (cannot lower).
- [ ] **P1** Reject illegal raises (below current bid, wrong increment).

### 1.5 Marriages and trump

- [ ] **P0** Marriage detection: K + Q of same suit in one hand.
- [ ] **P0** Marriage values: ♥=100, ♦=80, ♣=60, ♠=40.
- [ ] **P0** Marriage is declared by **leading** the K or Q while on lead — bonus posts immediately, trump becomes that suit from the next trick.
- [ ] **P0** No trump exists until the first marriage of the deal.
- [ ] **P0** Multiple marriages allowed in one deal — each replaces trump.
- [ ] **P1** Marriage formed via talon is legal.

### 1.6 Trick-taking

- [ ] **P0** Must follow suit if you can.
- [ ] **P0** Must beat the led card (highest of led suit) if you can — overtake rule.
- [ ] **P0** Must trump if void in led suit and trump exists; must overtrump if you can.
- [ ] **P0** Discard freely only when neither led suit nor trump is held.
- [ ] **P0** Trick winner = highest trump, else highest card of led suit; winner leads next.
- [ ] **P0** A deal is exactly 8 tricks.
- [ ] **P1** Revoke detection — log every illegal play with the rule it broke.

### 1.7 Scoring & barrel

- [ ] **P0** Captured card points sum (max 120 across both sides).
- [ ] **P0** Marriage bonuses credited to the player who declared them.
- [ ] **P0** Round each side's deal score to nearest 5; **marriage bonuses are exact**.
- [ ] **P0** Declarer made contract (deal score ≥ bid): + bid to running total.
- [ ] **P0** Declarer failed contract: − bid from running total.
- [ ] **P0** Defenders independently add their captured deal score to running totals.
- [ ] **P0** Barrel: at 880, freeze score, 3 deals to make 120 and win.
- [ ] **P0** Fall off the barrel: − 120 → 760.
- [ ] **P0** Win on reaching 1000.
- [ ] **P1** Barrel collision rule: last-mounter survives; others fall off.
- [ ] **P1** Tiebreaker: declarer wins ties when multiple players cross 1000 in the same deal.

### 1.8 Test suite for the engine

- [ ] **P0** Unit tests for every public function in `core/`.
- [ ] **P0** End-to-end test: simulate a full scripted deal and assert final scores.
- [ ] **P0** Property-test or scripted test: no rule violation reachable via the public API.
- [ ] **P1** Coverage report; aim for 80%+ on `core/`.

---

## Phase 2 — Hot-seat MVP

Goal: three humans pass a desktop around and play a real game to 1000.

- [ ] **P0** Scene structure: main menu → table → end-of-game.
- [ ] **P0** Render a 24-card deck, a hand, and the talon on screen — placeholder art is fine.
- [ ] **P0** Click-to-play interaction with hit-test on cards.
- [ ] **P0** Visible turn indicator and current bid display.
- [ ] **P0** Auction UI: each player in turn picks a bid amount or "pass".
- [ ] **P0** Talon reveal screen and "pass card to opponent" interaction.
- [ ] **P0** Marriage button / shortcut when leading a K or Q from a held marriage.
- [ ] **P0** Persistent running scoreboard visible during play.
- [ ] **P0** End-of-game screen showing winner and final scores.
- [ ] **P0** **Every player-visible string in this phase goes through `t()`** — no hard-coded literals, even in placeholder UI.
- [ ] **P0** **Auto-save the current game** to a single slot on app suspend / quit and after every scored deal; restore on next launch. Save format is JSON via `love.filesystem`, includes a `schemaVersion`, and snapshots the running scores plus the in-progress deal (hands, talon, bids, played tricks, declared marriages, current trump). The full save & load UI lands in Phase 4 — this phase only guarantees a long game survives a quit.
- [ ] **P1** Hot-seat privacy screen ("pass to next player" overlay) so each player only sees their own hand.
- [ ] **P1** "New game" / "abandon game" controls in the main menu.
- [ ] **P2** Visual indicator for which cards are *legal* to play (must-follow / must-beat / must-trump aware).

---

## Phase 3 — Rule template system

Goal: every variant from [Variations](../variations/index.md) is a
particular set of toggles in a single `RuleConfig`. Built-in templates
ship for the documented variants; players can clone, edit and save their
own.

### 3.1 `RuleConfig` data model & engine wiring

- [ ] **P0** Define a single `RuleConfig` table with every toggle the engine reads.
- [ ] **P0** Refactor the Core engine so **every variable rule reads from `RuleConfig`** — no hard-coded constants for things any variant could change.
- [ ] **P0** Each `RuleConfig` field has a typed schema (type, allowed values, default).
- [ ] **P0** Validation: incompatible combinations (e.g. partnerships=true with players=3) rejected with a clear, localisable error.
- [ ] **P0** Engine unit tests pass under each built-in `RuleConfig` from §3.3.
- [ ] **P1** `RuleConfig` is JSON-serialisable round-trip (used by §3.4 persistence and by saved games).
- [ ] **P1** A `schemaVersion` field on `RuleConfig` so future engine versions can migrate or reject old templates.

### 3.2 Toggle catalogue (the actual switches)

Group toggles in `RuleConfig` so the UI in §3.5 can render them in clear
sections. Each toggle's wording maps to a section in
[House Rules](../variations/house-rules.md) — the docs are the source of
truth for what each option does.

- [ ] **P0** **Players & seating**
  - Player count (2 / 3 / 4).
  - Partnership mode (none / fixed across-the-table) — only valid for 4 players.
  - 4-player configuration (A: dealer plays no talon / B: dealer sits out).
  - 2-player configuration (A: closed-talon draw stock / B: fixed deal no draw).
- [ ] **P0** **Dealing & redeal triggers**
  - 4-nine redeal (off / optional / mandatory).
  - 3-nine redeal (off / optional).
  - 4-jack redeal (off / on).
  - Weak-hand redeal (off / strict: no marriage + no Ace + no card above 10 / loose: no marriage + no Ace / counted: hand-points below threshold).
  - Misdeal handling (redeal by same dealer / pass deal clockwise / flat penalty + redeal).
  - All-pass handling when no forced-bid rule fires (redeal by same / pass-out clockwise / распасы reverse-scoring).
- [ ] **P0** **Talon**
  - Talon size (0 / 2 / 3).
  - Talon distribution (declarer takes all then passes / split face-down to opponents / face-up before auction).
  - Talon-flip-after-first-round (on / off).
  - Pass-the-talon (concede after seeing) on / off.
  - Buyback (discard hand for fresh deal at fixed penalty) on / off.
  - Hidden talon on minimum-100 contract (off / on — talon hidden from defenders when declarer is on a forced 100).
  - Bad-talon redeal (off / on — and trigger: fewer-than-5 card-points / 2 nines / 3 jacks / configurable; restricted to minimum 100 only on / off).
  - Talon re-buy (off / on — second auction with declared values 120 / 240 / open).
  - Open discard (off / on — declarer's pass-cards face-up rather than face-down).
- [ ] **P0** **Bidding**
  - Minimum opening bid (default 100).
  - Maximum first-round (pre-talon) bid (120 / 150).
  - Increment below 200 (5 / 10).
  - Increment from 200 onward (default 10).
  - Forced opening at 100 (forehand cannot pass) on / off.
  - Forced dealer bid — *бовт* (off / on — dealer takes 100 if all pass; **distinct** from the zero-tricks "Бoлт/Палка" penalty under Penalties).
  - Blind bid (sight-unseen, double-or-nothing) on / off.
  - Re-entry after pass (on / off — first-round passers may re-enter once).
  - Contra / doubling by defenders (off / contra-only / contra + redouble).
  - Forced-bid concession (off / on — and distribution: equal-split / each-defender-gets-full / pre-agreed-ratio).
  - No contract without marriage (off / strict: 120+ requires a marriage in hand / capped: max bid = 120 + value of marriages held).
  - Negative-score bidding restriction (off / on — players with a negative running total may only receive a forced 100).
  - Named contract bids available — see **Special contracts** below.
- [ ] **P0** **Marriages**
  - Hearts / Diamonds / Clubs / Spades values (defaults 100 / 80 / 60 / 40).
  - Half-marriage capture bonus on / off (and amount, default 20).
  - Trump activation timing (next-trick / immediately).
  - Marriage announcement timing (must-lead-K-or-Q / hand-announce-on-lead / pre-trick).
  - Drowned-marriage rule (cannot-be-declared / declared-then-cancelled).
  - Ace marriage / тузовый марьяж (off / on with value, default 200; sub-toggles: trick-required, first-Ace-led-sets-trump, no-trump-effect).
  - One trump per deal (off / on — only the first declared marriage sets trump; later marriages still score but do not change trump).
- [ ] **P0** **Trick play**
  - Must follow suit (always on — guarded constant).
  - Must overtake when following: strict / lenient.
  - Must trump when void: strict / lenient.
  - Defender must overtrump declarer: on / off.
  - Lazy revoke (only punished if caught before next lead) on / off.
  - Partial trumping (allow discard when can't beat existing trump) on / off.
  - Last-trick bonus (0 / 10 / 20 — points to winner of the 8th trick).
  - Slam bonus when declarer wins all 8 tricks (off / fixed-amount: e.g. 60 or 120 / doubled-bid).
  - Slam-against penalty when declarer takes 0 tricks (off / fixed-amount).
  - Lead-trump-after-marriage required (off / on).
- [ ] **P0** **Scoring**
  - Rounding granularity (nearest-5 / nearest-10 / no-rounding). Marriage bonuses always exact.
  - Score declarer's actual deal points instead of bid on success: on / off.
  - Defender contributions (independent / pooled-and-split — partnership mode only).
  - Failed-contract distribution (lost / split-among-defenders / each-defender-gets-bid). Affects what happens to the bid amount when a contract fails.
  - Declarer rounding before contract check (off / on — rounds the declarer's captured points up before comparing to the bid; turns 118 vs. a 120 bid into a make).
- [ ] **P1** **Opening-game (Golden deal)**
  - Golden deal (off / on with N deals, default = number of players).
  - Marriages doubled during golden deals (on / off).
  - Bidding above 120 allowed during golden deals (off / on).
  - Blind play allowed during golden deals (on / off).
  - Failure handling — when nobody makes 120 in a golden deal (continue / replay round / reset and start normal).
- [ ] **P0** **Barrel**
  - Threshold (default 880; alternative 900).
  - Intermediate "pit" lock-in (off / on at user-defined score).
  - Deal count on the barrel (1 / 3 / unlimited).
  - Fall-off penalty (−120 / 0 / −240).
  - Collision rule (last-mounter survives / all fall off / first-mounter survives / multiple-allowed).
  - Barrel-jump penalty when failing an overshooting bid on the barrel (off / bid-amount).
  - Reverse barrel at −880 (off / on — symmetric 3-deal countdown to lose; fall-back score user-defined).
- [ ] **P0** **Endgame**
  - Target score (500 / 1000 / 1500 / 2500). Default 1000.
  - Going-over-target rule (any-over-wins / exact-target-only / continuation-at-target+500).
  - Tiebreaker (declarer wins / highest score / continuation).
  - Dump truck / самосвал at exact ±555 (off / +555 only / both signs / configurable score).
- [ ] **P1** **Special contracts** (named bids alternative to numeric bids)
  - Mizère / no-tricks (off / on with fixed value, default 120).
  - Slam contract (off / on with fixed value: 240 / 300 / doubled-highest-bid).
  - Open-hand contract (off / on with doubled scoring).
- [ ] **P1** **Penalties**
  - Revoke penalty (full bid to opponents / flat 120 / configurable amount).
  - Talon-look penalty (default 120 / forfeit deal).
  - Showing-hand penalty (off / fixed amount, default 20 / full bid).
  - Zero-tricks "Бoлт / Палка" penalty (off / on — bolt counter threshold default 3, penalty default −120; sub-toggles: consecutive-only or cumulative, declarer-exempt, doubled-during-golden-deals). **Distinct** from the forced dealer bid above.
  - Cross / крест (off / on — alternative to immediate bid loss; cross threshold default 2, penalty default −120; defenders may receive bolts instead of points).

### 3.3 Built-in default templates

Each built-in is a constant `RuleConfig` value. **No new code per
variant** — only data.

- [ ] **P0** `Russian Thousand` (canonical, default at first launch).
- [ ] **P0** `Polish Tysiąc` (2-card talon, 10-step increments only, strict *przebijanie*).
- [ ] **P0** `Ukrainian Тисяча` (bolt rule, optional 2-deal barrel).
- [ ] **P0** `Two-player A` (closed talon, 9-card hands, draw stock).
- [ ] **P0** `Two-player B` (fixed deal, 7-card hands, no draw).
- [ ] **P0** `Four-player A` (dealer plays, no talon, 6 cards each).
- [ ] **P0** `Four-player B` (dealer sits out, otherwise standard 3-player rules).
- [ ] **P0** Engine test passes for every built-in template (full scripted deal).

### 3.4 Custom (user-saved) templates

- [ ] **P0** Clone a built-in template into a new editable copy.
- [ ] **P0** Edit any toggle in a custom template; live validation feedback.
- [ ] **P0** Save / rename / delete custom templates; persisted via `love.filesystem` as JSON.
- [ ] **P0** Reject invalid templates on load with a clear error and fall back to the canonical default.
- [ ] **P0** "Reset to default" for built-in templates the user has overridden.
- [ ] **P1** Import / export a template as a shareable JSON file (paste / share-sheet).
- [ ] **P1** Duplicate / star / sort templates in the picker.

### 3.5 Template UI

- [ ] **P0** Template picker on game start: built-in templates first, then user templates.
- [ ] **P0** Edit screen with toggles grouped by the §3.2 sections.
- [ ] **P0** Per-toggle inline help text — short and linkable to the relevant rules page.
- [ ] **P0** Inline validation (greys out / explains incompatible combinations).
- [ ] **P0** "Use this template" applies it to a fresh game.
- [ ] **P1** Confirmation prompt if the user changes templates **mid-game** (which abandons the current deal).
- [ ] **P1** Diff view: when looking at a custom template, highlight which toggles differ from its parent built-in.

---

## Phase 4 — UX & polish

Goal: it looks and feels like a card game, not a prototype.

### 4.1 Look & feel basics

- [ ] **P0** Animations: deal, play, capture, trump-flip on marriage, talon reveal.
- [ ] **P0** Sound effects: card flip, card play, trick capture, marriage chime, win/lose.
- [ ] **P0** Readable scoreboard with running totals, current deal contributions, and barrel state.
- [ ] **P0** Settings screen: active rule template, active card skin, language, sound on/off, animation speed.
- [ ] **P1** Interactive tutorial: walks a newcomer through bidding, talon, marriage and the barrel in one guided deal.
- [ ] **P1** End-of-game stats (deals played, marriages declared, contracts made/failed).
- [ ] **P1** Light + dark theme, respects system preference.
- [ ] **P2** Music with a single-track on/off toggle.

### 4.2 Card skins

- [ ] **P0** **Skin asset-pack format**: a directory with face cards (24), card back, and table felt — all referenced through a manifest so adding a skin is data-only.
- [ ] **P0** **One default skin** that ships in v1 (clean, readable, neutral — works for the tutorial).
- [ ] **P0** **At least 3 alternative built-in skins**, each visually distinct (e.g. classic Eastern-European, modern minimal, high-contrast / accessibility-friendly).
- [ ] **P0** **Skin selector** in settings with live preview before apply.
- [ ] **P0** Skin choice is persisted across launches and survives app updates.
- [ ] **P0** All skins must keep card rank/suit instantly readable — accessibility test: a player can identify any card in &lt; 1 second.
- [ ] **P1** Per-skin sound override (optional — some skins ship their own card-flip sound).
- [ ] **P2** User-imported custom skins (drop a folder under the save dir).

### 4.3 Save & load games

A complete game to 1000 can run an hour or more across many deals. Players need to set a game aside and come back to it — possibly with multiple games on the go.

- [ ] **P0** **Auto-save** at every checkpoint: after each scored deal, on app suspend, on graceful quit. Single auto-save slot (latest). Builds on the Phase 2 baseline.
- [ ] **P0** **Save format** is JSON via `love.filesystem` and includes:
  - `schemaVersion`,
  - the active rule template's identity **and a full snapshot of its toggles** (so a loaded game replays under the exact rules it started with, even if the template was edited later),
  - assigned characters per seat (placeholder data until Phase 7 lands),
  - running scores and the full history of played deals (for score-sheet review),
  - the in-progress deal: hands, talon, bidding state, played tricks, declared marriages, current trump,
  - wall-clock timestamps for created / last-saved.
- [ ] **P0** **Continue** button on the main menu loads the auto-save and resumes mid-deal. Disabled if no auto-save exists.
- [ ] **P0** **Manual save slots**: at any non-blocking moment (between deals; never mid-trick), save the current game with a user-chosen name. Up to N named slots (default 10).
- [ ] **P0** **Saved-games list** scene: one row per save showing player names, current running scores, deal number, and last-played timestamp.
- [ ] **P0** **Load** any saved game from the list; confirmation prompt if there is an in-progress game that would be abandoned.
- [ ] **P0** **Delete** a saved game with a confirmation prompt.
- [ ] **P0** Reject corrupted or schema-incompatible saves with a clear, localised message — never crash on a bad save file.
- [ ] **P1** Rename a saved game.
- [ ] **P1** Sort saved games (recent / name).
- [ ] **P1** Save thumbnail / preview shows the table state at save time.
- [ ] **P2** Export / import a saved game as a JSON file (for sharing or backup).

---

## Phase 5 — iOS port (cross-platform prototype)

Goal: the same Lua source builds and runs on **macOS, Linux and iOS**.
The base hot-seat game (Phases 0–4) plays correctly on every v1 target.

- [ ] **P0** Wire up the love-ios Xcode project that embeds our `.love`.
- [ ] **P0** Replace mouse hover affordances with touch-equivalent feedback.
- [ ] **P0** Hit-targets sized to **44 pt minimum** on iOS.
- [ ] **P0** Reflowable table layout: portrait and landscape on iPhone and iPad.
- [ ] **P0** Use `love.filesystem` exclusively (no absolute paths) so iOS sandboxing works.
- [ ] **P0** App icon set and launch screen for iOS.
- [ ] **P0** Smoke test the **template picker** and **skin selector** under touch input.
- [ ] **P0** Confirm a complete hot-seat game can be played end-to-end on iPhone, iPad, macOS and Linux without regressions.
- [ ] **P1** iPad-specific layout (more screen real estate for the scoreboard and history).
- [ ] **P1** Haptic feedback on card play, trick capture and marriage.
- [ ] **P2** Dynamic Type support for accessibility.

---

## Phase 6 — AI opponents (algorithmic)

Goal: a single human plays against two AI seats at one difficulty. **No
LLM yet — silent AI.**

- [ ] **P0** AI player abstraction: `chooseBid`, `chooseTalonPass`, `chooseRaise`, `chooseCard`, `chooseMarriage`. Lives in `app/ai/`.
- [ ] **P0** Rule-based AI v1: legal bidding heuristic from the [Strategy](../strategy.md) page.
- [ ] **P0** Rule-based AI v1: legal trick play that obeys must-follow / must-beat / must-trump.
- [ ] **P0** AI never produces an illegal move (verified by the same rules engine that guards the human).
- [ ] **P0** AI move latency capped at 2 seconds with a "thinking…" indicator.
- [ ] **P0** AI works under **every built-in `RuleConfig`** from §3.3 (Russian / Polish / Ukrainian / 2-player / 4-player), not just Russian.
- [ ] **P0** AI re-tested on macOS, Linux and iOS — no regressions on the prototype platforms.
- [ ] **P1** Difficulty levels: easy / normal / hard (differ in marriage planning, trump leading, defender cooperation).
- [ ] **P1** Single-player mode selectable from the main menu.
- [ ] **P2** AI plays the *mizère / no-tricks* contract correctly when enabled.

---

## Phase 7 — AI characters & psychology

Goal: AI seats become **named characters** with personalities. With an
OpenAI-compatible LLM endpoint configured, characters banter, react and
attempt to bluff during play. The algorithm still picks every move — the
LLM only writes text.

:::warning[Inviolable invariant]
**The algorithm picks every move. The LLM only writes dialogue.**
This phase must not weaken that boundary. If you find yourself wanting
the LLM to choose a card "just this once", you are doing it wrong — stop
and talk to the architect.
:::

### 7.1 Algorithm-vs-LLM firewall

- [ ] **P0** `app/ai/` (move logic) and `app/llm/` (chat) live in separate modules and never import each other.
- [ ] **P0** CI lint fails the build if the import graph is violated.
- [ ] **P0** The LLM client's only public output type is **text**. It has no method shape that could return a card, bid, or move.
- [ ] **P0** Test: with the LLM client stubbed to return chaos / errors / nothing, every test from Phases 1, 2, 3 and 6 still passes unchanged.

### 7.2 `CharacterPreset` data model

- [ ] **P0** Define a `CharacterPreset` table: name, avatar reference, short description, full LLM system prompt, voice/tone hints, default algorithmic difficulty, `bluffStyle` (often / rarely / never), spoken-language hint, `schemaVersion`.
- [ ] **P0** Each AI seat in a game is bound to a `CharacterPreset` (or `nil` for silent AI).
- [ ] **P0** The character has **no causal effect on moves** — it is metadata for the LLM and the UI only.
- [ ] **P1** `CharacterPreset` is JSON-serialisable round-trip and shares a schema-versioning approach with `RuleConfig`.

### 7.3 Built-in characters (default cast)

The slots matter more than the exact names; the product owner refines
copy later.

- [ ] **P0** **"Silent"** — no chat. Always available; default fallback when no LLM endpoint is configured.
- [ ] **P0** **At least 4 built-in named characters** with distinct voices and bluff styles. Suggested archetypes: the calculating aunt (polite, ruthless, rarely bluffs), the old hustler (terse, sarcastic, bluffs often), the friendly amateur (chatty, makes mistakes, never bluffs), the smug newcomer (talks smack, calls out your mistakes).
- [ ] **P0** Each built-in character has an avatar asset and a complete LLM system prompt.
- [ ] **P0** Built-in characters' on-screen text localises (English ships in this phase; Russian / Polish / Ukrainian land in Phase 8).

### 7.4 Custom (user-saved) characters

- [ ] **P0** Clone a built-in character into a new editable copy.
- [ ] **P0** Edit name, description, system prompt, voice/tone, default difficulty, bluff style.
- [ ] **P0** Save / rename / delete custom characters; persisted via `love.filesystem` as JSON.
- [ ] **P0** Validation: empty name rejected, system-prompt length capped, default difficulty valid.
- [ ] **P0** "Reset to default" for built-in characters the user has overridden.
- [ ] **P1** Import / export a character as a shareable JSON file.

### 7.5 OpenAI-compatible LLM client

- [ ] **P0** Minimal HTTP client in `app/llm/` that calls the **OpenAI Chat Completions** shape (or any endpoint that mimics it).
- [ ] **P0** Configurable: base URL, API key, model name, optional extra headers.
- [ ] **P0** Verified to work with at least: **OpenAI** (api.openai.com), **OpenRouter**, **local Ollama** (its `/v1` OpenAI-compatible mode), and **LM Studio**.
- [ ] **P0** **Non-blocking**: an LLM call never stalls the game loop. Use coroutines or a worker.
- [ ] **P0** Per-call timeout (default 8 s) — a slow endpoint never delays a move.
- [ ] **P0** Returns **text only**. No code path decodes a move-shaped response.
- [ ] **P1** Streaming responses (so chat appears progressively).

### 7.6 Endpoint settings & API key storage

- [ ] **P0** Settings screen section for LLM: base URL, API key, model name, "test connection" button.
- [ ] **P0** Defaults are blank — the feature is **opt-in**. Without it, the AI seats stay silent and the game is fully playable.
- [ ] **P0** API key stored in the platform secure store where available (macOS Keychain, iOS Keychain). Linux fallback: a local file with a clear in-app notice that secure storage is not available.
- [ ] **P0** Never log the API key. Never include it in crash reports or save files.
- [ ] **P1** "Forget API key" button.
- [ ] **P1** A small "where does my data go?" explainer shown on first enable.

### 7.7 Character chat HUD

- [ ] **P0** Per-AI-seat chat affordance: avatar + name at the seat; speech bubble or banner for incoming chat.
- [ ] **P0** Chat is **non-modal** — it never blocks the human's turn or pauses the algorithm.
- [ ] **P0** Mute / unmute a character with one tap on its avatar.
- [ ] **P0** Player-side text input so the human can talk back (per-session toggle: enabled by default, disable to play silent).
- [ ] **P0** Chat history accessible from a sidebar / drawer.
- [ ] **P1** Auto-translate character text to the player's locale (uses the same LLM endpoint).

### 7.8 Cost, rate & failure controls

- [ ] **P0** Hard cap on LLM calls per deal (default conservative; user-adjustable in settings).
- [ ] **P0** Debounce: at most one in-flight LLM call per character at a time.
- [ ] **P0** Throttling at the event source (e.g. one bid-reaction per character per auction round, not one per bid).
- [ ] **P0** Any LLM failure (missing key, 4xx, 5xx, timeout, parse fail, rate limit) is **silent** — the character simply does not speak. No on-table error popups.
- [ ] **P0** A diagnostic line in settings shows the *last* error for debugging.
- [ ] **P1** Per-character daily call counter visible in settings.
- [ ] **P2** Pre-baked offline lines for the built-in cast so they say *something* when the LLM is unavailable.

### 7.9 Character editor UI

- [ ] **P0** Character picker at game start: choose a character (or "Silent") for each AI seat.
- [ ] **P0** Editor screen: avatar slot, name, description, system-prompt textarea, voice/tone selector, default difficulty selector, bluff style.
- [ ] **P0** "Test in chat" button — sends a sample prompt and shows the response (no game state required).
- [ ] **P1** Diff view: highlight which fields differ from the parent built-in.
- [ ] **P2** Avatar import (drag-drop an image into the save dir).

---

## Phase 8 — Release readiness

Goal: signed, localised, distributable builds for macOS, Linux and iOS.

### 8.1 Localisation

The i18n plumbing has existed since Phase 0; this section is purely
translation work — populating the `ru`, `pl` and `uk` locale tables
against the keys already used in the code.

- [ ] **P0** English locale table reviewed and finalised (treated as the source of truth).
- [ ] **P0** Russian translation populated against the same keys.
- [ ] **P0** Polish translation populated against the same keys.
- [ ] **P0** Ukrainian translation populated against the same keys.
- [ ] **P0** Localise the built-in character cast's UI copy (name, description) into all four languages. (System prompts may stay English; the LLM handles output language.)
- [ ] **P0** Audit: zero missing-key warnings in any locale during a full play session.
- [ ] **P1** Locale auto-detection from system on first launch, manual override in settings.

### 8.2 Persistence

The save format (with `schemaVersion`) and the save/load UI already land
in Phase 2 and Phase 4. This sub-section hardens persistence for
release.

- [ ] **P0** Audit auto-save coverage across **all platform-specific suspension points**: iOS app backgrounding, macOS app quit, Linux SIGTERM, terminal Ctrl-C.
- [ ] **P0** `schemaVersion` migration logic: saves from earlier versions either auto-migrate forward or are rejected with a clear, localised message.
- [ ] **P0** User-saved rule templates, characters, **and saved games** all survive app updates.
- [ ] **P1** Score history (last N games) viewable in the menu.

### 8.3 Packaging & distribution

- [ ] **P0** macOS `.app` bundle, code-signed and notarised.
- [ ] **P0** Linux `.AppImage` (and a `.tar.gz` fallback).
- [ ] **P0** iOS `.ipa` via App Store Connect.
- [ ] **P0** Privacy policy and store metadata (description, screenshots) — explicitly mentioning that **LLM chat is opt-in and the user's API key never leaves the device**.
- [ ] **P1** Crash reporting (opt-in, anonymised) — must scrub the API key.
- [ ] **P1** Versioning scheme: semver in `conf.lua`, surfaced in the settings "About" screen.
- [ ] **P2** Auto-update channel for desktop (or a clear "check for updates" link).

### 8.4 Education mode

Thousand is complicated by modern card-game standards — bidding, the
talon, marriages, must-trump and the barrel are all unfamiliar concepts
to many players. Education mode is the dedicated learning path for
people who want to **study** the game rather than just play it.

Distinct from the single-deal tutorial in §4.1, which gets a first-time
user into a real game. Education mode is a **multi-lesson course**,
accessible from the main menu, that teaches the game from scratch.

- [ ] **P1** Main-menu entry "Learn to play" → Education mode hub.
- [ ] **P1** Lesson list: a sequence of self-contained lessons (~3–5 minutes each), building from cards → bidding → talon → marriages → tricks → scoring → barrel. Roughly 7 lessons.
- [ ] **P1** Each lesson is **interactive** — scripted hands the learner plays through with hint balloons explaining each step. No purely-text lessons.
- [ ] **P1** Lesson 1: deck & card rank. The 24 cards, rank order (A > 10 > K > Q > J > 9), point values.
- [ ] **P1** Lesson 2: bidding. Walks through an auction with explainers on each bid decision.
- [ ] **P1** Lesson 3: the talon, the pass, and the raise.
- [ ] **P1** Lesson 4: marriages and trump flips.
- [ ] **P1** Lesson 5: trick-taking under must-follow / must-beat / must-trump.
- [ ] **P1** Lesson 6: scoring a deal and the barrel.
- [ ] **P1** Lesson 7: variations primer — what templates are, how rules differ between Russian / Polish / Ukrainian / 2-player / 4-player.
- [ ] **P1** Glossary scene — searchable list of terms (бовт, прикуп, marriage, talon, barrel, mizère, …) with short definitions; accessible from anywhere via a `?` icon.
- [ ] **P1** Progress tracking — per-lesson completion state; resume mid-lesson.
- [ ] **P1** All lesson copy keyed via `t()` and translated alongside the rest of the app in §8.1.
- [ ] **P2** Practice mode — a one-deal sandbox where the AI offers gentle suggestions to a learner.
- [ ] **P2** Quick-reference popover accessible during a real game (rules cheat-sheet, not just during lessons).
- [ ] **P2** Per-lesson completion badges in a progress view (no gamification beyond a checkmark).

---

## Cross-phase / ongoing

- [ ] **P0** Keep the [Rules of Play](../rules/setup.md) in sync with code. If they disagree, fix the docs first.
- [ ] **P0** Every PR runs lint + tests; no merges on red.
- [ ] **P0** **Every player-visible string goes through `t()`.** No hard-coded UI literals, ever — not in placeholders, not in error messages, not in tutorials. Phase 8 only adds translations against keys that already exist.
- [ ] **P0** No platform-conditional code in `core/` or `app/`. Anything platform-specific lives in `ui/` or `platform/` so the post-v1 Windows and Android targets stay cheap.
- [ ] **P0** No absolute filesystem paths anywhere — `love.filesystem` only.
- [ ] **P0** Touch + mouse input parity: every interaction works under both, so the same code covers iOS, desktop, and (later) Android.
- [ ] **P1** Update this task list as you go: tick boxes off, add tasks you discover, do **not** delete obsolete ones — strike them through with a note.
- [ ] **P1** A short post-phase retrospective in the PR description when each phase closes.

---

## Phase 9 — Windows desktop *(post-v1)*

Goal: signed Windows build with the same Lua source.

- [ ] **P0** Acquire / arrange a Windows test machine.
- [ ] **P0** Verify the existing `.love` runs on Windows under the stock `love.exe`.
- [ ] **P0** Package as a Windows `.exe` / installer, code-signed.
- [ ] **P0** Confirm save files land in the expected per-user location and round-trip.
- [ ] **P1** Windows-specific app icon and store metadata (Microsoft Store optional).
- [ ] **P1** CI matrix gains a Windows runner.

---

## Phase 10 — Android *(post-v1)*

Goal: Play Store build with the same Lua source.

- [ ] **P0** Acquire / arrange Android phone and tablet test devices.
- [ ] **P0** Wire up the love-android Gradle project that embeds our `.love`.
- [ ] **P0** Re-validate touch hit-targets on Android (typically 48 dp minimum).
- [ ] **P0** Re-validate reflowable layout across phone and tablet form factors.
- [ ] **P0** Confirm `love.filesystem` save round-trip on Android sandbox.
- [ ] **P0** App icon, adaptive icon, and Play Store metadata.
- [ ] **P0** Signed `.aab` ready for Play Console upload.
- [ ] **P1** Android haptic feedback parity with iOS.
- [ ] **P1** CI matrix gains an Android build runner.
