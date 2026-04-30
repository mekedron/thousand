---
sidebar_position: 3
title: Task List
---

# Task List

This file is the **living implementation checklist** for building the
game. Tasks are grouped by phase from the [Roadmap](./roadmap.md).
Within each phase, the order is the execution order.

:::tip[How to use this page]
- Work top-to-bottom within the active phase.
- A checkbox should be large enough for one focused implementation
  session. Small adjacent changes belong in the same task.
- Use plain bullets under a task for acceptance notes and scope details.
  Do not add checkboxes to non-tasks.
- A task is done when its scope notes are true and the change is merged
  to `main`.
:::

---

## Phase 0 — Project setup

Goal: `love .` opens a window. CI is green on macOS and Linux. The
plumbing every later phase relies on (i18n, settings, save dir) exists
from day one.

- [x] Initialise the Love2D project skeleton and repository layout.
  - `main.lua`, `conf.lua`, window title, and Love2D version are set.
  - Top-level directories match [Architecture](./architecture.md):
    `core/`, `app/`, `ui/`, `assets/`, `tests/`, `platform/`.
- [x] Add Lua formatting, linting, tests, and local command entry points.
  - `stylua` and `luacheck` share project-level config.
  - Plain-`lua` tests run from the command line through a single script or
    `make test`.
- [x] Add GitHub Actions for linting and tests on every push.
- [x] Add i18n plumbing from day one.
  - `t(key, ...)` reads from `assets/i18n/<locale>.lua`.
  - Active locale lives in settings.
  - Stub locale tables exist for `en`, `ru`, `pl`, and `uk`.
  - Missing active-locale keys fall back to `en` and log once per key.
- [x] Document how to run, test, and package the project in the root
  `README.md`.
- [x] Produce a `.love` artifact on every push to `main`.
- [x] Add local pre-commit checks for linting and tests.
- [x] Add a CI guard for hard-coded player-visible strings outside locale
  tables.

---

## Phase 1 — Core rules engine (pure Lua)

Goal: every rule from [Rules of Play](../rules/setup.md) implemented and
tested. **No Love2D in this layer.**

:::warning[Read from `RuleConfig` from day one]
The engine is **parameterised by a `RuleConfig`** from this phase's first
commit. Phase 1 ships exactly one `RuleConfig` value — the canonical
Russian default — but never hard-codes a value any future variant could
change (talon size, bid increments, marriage values, barrel rules, ...).
:::

### 1.1 Cards & deck

- [ ] Define the canonical `RuleConfig` baseline and the card model.
  - Card has suit (♠♣♦♥) and rank (9,J,Q,K,10,A).
  - Card point values are A=11, 10=10, K=4, Q=3, J=2, 9=0.
  - Trick rank order is A > 10 > K > Q > J > 9.
  - These values are read from the canonical Phase 1 `RuleConfig`, not
    duplicated as unrelated constants.
- [ ] Build the deterministic 24-card deck module.
  - Deck builder returns exactly one card for every suit/rank pair.
  - Total deck card points equal 120.
  - Shuffle is seedable and reproducible in tests.

### 1.2 Dealing

- [ ] Implement standard 3-player deal and deal validation.
  - Deal sequence is 3+3+3, 2 to talon, 2+2, 1 to talon, 2+2.
  - Each player ends with 7 cards and the talon has 3 cards.
  - Every completed deal still contains exactly 24 unique cards.
  - Misdeals such as wrong count or exposed card return typed errors.

### 1.3 Auction / bidding

- [ ] Implement the auction state machine.
  - Auction starts at forehand and advances clockwise.
  - Opening minimum is 100; pre-talon maximum is 120.
  - Bid increments are 5 below 200 and 10 from 200 onward.
  - Pass is permanent.
  - Auction ends when two players have passed.
  - Declarer is the last remaining bidder at their final bid.
  - Illegal bid attempts return typed errors.

### 1.4 Talon, pass and raise

- [ ] Implement talon reveal, pickup, pass, and post-talon raise.
  - The 3 talon cards are publicly revealed.
  - Declarer takes the talon and reaches 10 cards; opponents stay at 7.
  - Declarer passes 1 face-down card to each opponent, producing 8 / 8 / 8.
  - Declarer may raise after seeing the talon but cannot lower the bid.
  - Illegal raises, including wrong increment and below-current-bid values,
    return typed errors.

### 1.5 Marriages and trump

- [ ] Implement marriage detection, declaration, bonuses, and trump state.
  - A marriage is K + Q of the same suit in one hand.
  - Marriage values are ♥=100, ♦=80, ♣=60, ♠=40.
  - A marriage is declared by leading the K or Q while on lead.
  - The bonus posts immediately.
  - No trump exists until the first declared marriage.
  - Declared marriage suit becomes trump from the next trick.
  - Multiple marriages are allowed in one deal and each replaces trump.
  - A marriage formed through the talon is legal.

### 1.6 Trick-taking

- [ ] Implement legal-play validation and trick resolution.
  - Player must follow suit if possible.
  - Player must beat the led card if possible when following suit.
  - Player must trump when void in led suit and trump exists.
  - Player must overtrump if possible.
  - Player may discard freely only when holding neither led suit nor trump.
  - Trick winner is highest trump, otherwise highest card of led suit.
  - Trick winner leads next.
  - A deal is exactly 8 tricks.
  - Every illegal play is logged with the rule it broke.

### 1.7 Scoring & barrel

- [ ] Implement deal scoring and contract resolution.
  - Captured card points sum to at most 120 across all sides.
  - Marriage bonuses are credited to the player who declared them.
  - Captured card points round to nearest 5; marriage bonuses stay exact.
  - Declarer made contract when deal score is at least the bid.
  - Successful declarer adds the bid to running total.
  - Failed declarer subtracts the bid from running total.
  - Defenders independently add their captured deal scores.
- [ ] Implement barrel and game-end scoring.
  - At 880, score freezes and the player has 3 deals to make 120 and win.
  - Falling off the barrel applies −120 and returns the player to 760.
  - Reaching 1000 wins.
  - Barrel collision rule is last-mounter survives; others fall off.
  - If multiple players cross 1000 in the same deal, declarer wins ties.

### 1.8 Engine tests

- [ ] Build the core rules test suite.
  - Every public function in `core/` has unit coverage.
  - A scripted full deal asserts final scores.
  - Public APIs cannot reach a rule-violating state in scripted or
    property-style tests.
  - Coverage report exists with a target of at least 80% for `core/`.

---

## Phase 2 — Hot-seat MVP

Goal: three humans pass a desktop around and play a real game to 1000.
The first table UI is already touch-ready and reflowable so iOS is a
porting pass later, not a UI rewrite.

- [ ] Build the scene skeleton and game navigation.
  - Main menu, table, and end-of-game scenes exist.
  - New-game and abandon-game controls are available from the menu.
- [ ] Build touch-ready input and reflowable table foundations.
  - Mouse and touch use the same action paths.
  - No required interaction depends on hover.
  - Primary card/table controls are sized for finger input from the first UI
    pass.
  - Table layout responds to window size instead of using fixed desktop-only
    coordinates.
- [ ] Render the playable table state with placeholder assets.
  - 24-card deck, player hand, talon, current turn, current bid, running
    scoreboard, and end-of-game winner/final scores are visible.
- [ ] Connect hot-seat input to the rules engine.
  - Player can click or tap cards through hit-tests.
  - Auction UI lets each player bid or pass in turn.
  - Talon reveal and pass-card interactions are playable.
  - Marriage declaration is available when leading a K or Q from a held
    marriage.
- [ ] Add hot-seat privacy and hand-off flow.
  - A pass-to-next-player overlay hides inactive hands.
  - Each player only sees their own hand during private decisions.
- [ ] Add legal-action affordances.
  - Cards that are legal under must-follow, must-beat, and must-trump rules
    can be visually distinguished.
  - Illegal player actions are blocked with localised feedback.
- [ ] Route every player-visible string in the hot-seat MVP through `t()`.
  - This includes placeholder UI, error messages, button labels, and
    end-of-game text.
- [ ] Add baseline auto-save and restore.
  - One auto-save slot writes on app suspend, graceful quit, and after every
    scored deal.
  - Save format is JSON via `love.filesystem`.
  - Save includes `schemaVersion`, running scores, hands, talon, bids,
    played tricks, declared marriages, and current trump.
  - Next launch restores the auto-save if present.

---

## Phase 3 — Rule template system

Goal: every variant from [Variations](../variations/index.md) is
represented as data in a single `RuleConfig` system. Phase 3 must not
balloon into implementing every obscure house rule immediately: each
documented toggle is either implemented and selectable, or explicitly
marked deferred so built-in templates and saved custom templates cannot
accidentally depend on it.

### 3.1 `RuleConfig` model & engine wiring

- [ ] Expand `RuleConfig` into the single schema for every engine toggle.
  - Every field has a type, allowed values, default value, and
    `schemaVersion` handling.
  - Every field records whether it is implemented, selectable, or deferred.
  - `RuleConfig` round-trips through JSON for persistence and saved games.
  - Incompatible combinations are rejected with clear, localisable errors.
- [ ] Refactor the core engine so every variable rule reads from
  `RuleConfig`.
  - No hard-coded constants remain for rules that variants can change.
  - Engine tests pass under every built-in template added in this phase.

### 3.2 Toggle catalogue

Group toggles in `RuleConfig` so the UI can render clear sections. Each
toggle's wording maps to [House Rules](../variations/house-rules.md),
which remains the source of truth for behavior. Catalogue tasks mean
schema, validation, and UI representation; gameplay behavior is required
only for toggles marked selectable.

- [ ] Add players and seating toggles.
  - Player count (2 / 3 / 4).
  - Partnership mode (none / fixed across-the-table), valid only for 4
    players.
  - 4-player configuration (dealer plays no talon / dealer sits out).
  - 2-player configuration (closed-talon draw stock / fixed deal no draw).
- [ ] Add dealing and redeal-trigger toggles.
  - 4-nine redeal (off / optional / mandatory).
  - 3-nine redeal (off / optional).
  - 4-jack redeal (off / on).
  - Weak-hand redeal options.
  - Misdeal handling options.
  - All-pass handling options, including распасы reverse-scoring.
- [ ] Add talon toggles.
  - Talon size (0 / 2 / 3).
  - Talon distribution options.
  - Talon-flip-after-first-round.
  - Pass-the-talon.
  - Buyback.
  - Hidden talon on minimum-100 contract.
  - Bad-talon redeal.
  - Talon re-buy.
  - Open discard.
- [ ] Add bidding toggles.
  - Minimum opening bid.
  - Maximum first-round bid.
  - Increment below 200.
  - Increment from 200 onward.
  - Forced opening at 100.
  - Forced dealer bid (бовт), distinct from the zero-tricks penalty.
  - Blind bid.
  - Re-entry after pass.
  - Contra and redouble.
  - Forced-bid concession.
  - No contract without marriage.
  - Negative-score bidding restriction.
  - Named contract bids.
- [ ] Add marriage toggles.
  - Hearts / Diamonds / Clubs / Spades values.
  - Half-marriage capture bonus.
  - Trump activation timing.
  - Marriage announcement timing.
  - Drowned-marriage rule.
  - Ace marriage / тузовый марьяж.
  - One trump per deal.
- [ ] Add trick-play toggles.
  - Must follow suit as a guarded constant.
  - Must overtake strictness.
  - Must trump strictness.
  - Defender must overtrump declarer.
  - Lazy revoke.
  - Partial trumping.
  - Last-trick bonus.
  - Slam bonus.
  - Slam-against penalty.
  - Lead-trump-after-marriage requirement.
- [ ] Add scoring toggles.
  - Rounding granularity.
  - Score declarer's actual deal points instead of bid on success.
  - Defender contributions.
  - Failed-contract distribution.
  - Declarer rounding before contract check.
- [ ] Add opening-game, barrel, and endgame toggles.
  - Golden deal settings.
  - Barrel threshold, pit lock-in, deal count, fall-off penalty, collision
    rule, overshoot penalty, and reverse barrel.
  - Target score, going-over-target rule, tiebreaker, and dump truck /
    самосвал settings.
- [ ] Add special-contract and penalty toggles.
  - Mizère / no-tricks.
  - Slam contract.
  - Open-hand contract.
  - Revoke penalty.
  - Talon-look penalty.
  - Showing-hand penalty.
  - Zero-tricks "Бoлт / Палка" penalty.
  - Cross / крест.

### 3.3 Built-in default templates

Each built-in is a constant `RuleConfig` value. **No new code per
variant** — only data.

- [ ] Add built-in 3-player regional templates.
  - `Russian Thousand` is canonical and default at first launch.
  - `Polish Tysiąc` uses 2-card talon, 10-step increments only, and strict
    *przebijanie*.
  - `Ukrainian Тисяча` includes the bolt rule and optional 2-deal barrel.
- [ ] Add built-in 2-player and 4-player templates.
  - `Two-player A` uses closed talon, 9-card hands, and draw stock.
  - `Two-player B` uses fixed deal, 7-card hands, and no draw.
  - `Four-player A` has dealer play, no talon, and 6 cards each.
  - `Four-player B` has dealer sit out and otherwise standard 3-player
    rules.
- [ ] Add scripted engine tests for every built-in template.
  - Built-in templates use only implemented selectable toggles.
  - Each template can complete a full scripted deal.
  - Template-specific edge rules are asserted.

### 3.4 Custom templates

- [ ] Implement custom template lifecycle and persistence.
  - Clone a built-in template into an editable copy.
  - Edit any toggle with live validation feedback.
  - Save, rename, delete, duplicate, star, and sort custom templates.
  - Persist templates via `love.filesystem` as JSON.
  - Reject invalid templates on load with a clear error and fall back to the
    canonical default.
  - Reject templates that enable deferred toggles.
  - Reset an overridden built-in template to default.
  - Import or export a template as shareable JSON.

### 3.5 Template UI

- [ ] Build the template picker and editor.
  - Game start shows built-in templates first, then user templates.
  - Editor groups toggles by the sections in this phase.
  - Each toggle has short inline help linked to the relevant rules page.
  - Inline validation greys out and explains incompatible combinations.
  - Deferred toggles are disabled or hidden with a clear note, not silently
    selectable.
  - "Use this template" applies it to a fresh game.
  - Changing templates mid-game requires a confirmation prompt because it
    abandons the current deal.
  - Custom templates show a diff against their parent built-in template.

---

## Phase 4 — UX & polish

Goal: it looks and feels like a card game, not a prototype.

### 4.1 Look & feel basics

- [ ] Add polished table presentation.
  - Animations cover deal, play, capture, trump-flip on marriage, and talon
    reveal.
  - Sound effects cover card flip, card play, trick capture, marriage chime,
    win, and loss.
  - Scoreboard clearly shows running totals, current deal contributions, and
    barrel state.
- [ ] Build the settings screen.
  - Settings include active rule template, active card skin, language, sound
    on/off, animation speed, and light/dark theme preference.
  - Theme respects system preference.
- [ ] Add the first-time-player tutorial and end-of-game stats.
  - Tutorial walks through bidding, talon, marriage, and barrel in one guided
    deal.
  - End-of-game stats include deals played, marriages declared, and contracts
    made/failed.
- [ ] Add optional background music.
  - One-track music can be toggled on or off.

### 4.2 Card skins

- [ ] Define the card-skin asset-pack format.
  - A skin directory contains 24 face cards, a card back, and table felt.
  - A manifest references every asset so adding a skin is data-only.
- [ ] Ship built-in skins with readability checks.
  - One clean, readable default skin ships in v1.
  - At least 3 alternative built-in skins are visually distinct.
  - Every skin lets a player identify any card in under 1 second.
- [ ] Build the skin selector.
  - Settings show live preview before apply.
  - Selected skin persists across launches and survives app updates.
- [ ] Add skin extension hooks.
  - Per-skin sound overrides are supported.
  - User-imported custom skins can be loaded from the save directory.

### 4.3 Save & load games

A complete game to 1000 can run an hour or more across many deals.
Players need to set a game aside and come back to it — possibly with
multiple games on the go.

- [ ] Harden auto-save checkpoints and save schema.
  - Auto-save writes after each scored deal, on app suspend, and on graceful
    quit.
  - Save format is JSON via `love.filesystem`.
  - Save includes `schemaVersion`.
  - Save includes active rule template identity and a full snapshot of its
    toggles.
  - Save includes assigned characters per seat, even before Phase 7 fills
    character data.
  - Save includes running scores, full played-deal history, in-progress deal,
    and created / last-saved timestamps.
- [ ] Add continue/resume from auto-save.
  - Main menu shows "Continue" when an auto-save exists.
  - Continue resumes mid-deal.
  - Continue is disabled when no auto-save exists.
- [ ] Implement manual save slots and the saved-games list.
  - Save current game between deals with a user-chosen name.
  - Named slots default to 10.
  - Saved-games list shows player names, running scores, deal number, and
    last-played timestamp.
- [ ] Implement saved-game actions.
  - Load any saved game with confirmation if an in-progress game would be
    abandoned.
  - Delete a saved game with confirmation.
  - Rename a saved game.
  - Sort saved games by recent or name.
  - Show a table-state thumbnail or preview when available.
- [ ] Add save-file hardening and portability.
  - Corrupted or schema-incompatible saves produce a clear, localised message
    and never crash.
  - Saved games can be exported and imported as JSON.

---

## Phase 5 — iOS port (cross-platform prototype)

Goal: the same Lua source builds and runs on **macOS, Linux and iOS**.
The base hot-seat game from Phases 0–4 plays correctly on every v1
target.

- [ ] Wire the love-ios Xcode project and iOS app assets.
  - Xcode project embeds the current `.love`.
  - App icon set and launch screen are present.
- [ ] Audit shared code for iOS-safe assumptions.
  - `love.filesystem` is used exclusively.
  - No absolute paths are used.
  - Phase 2 touch/input assumptions still hold on real iOS hardware.
- [ ] Adapt the table UI for touch and responsive layouts.
  - Hit targets are at least 44 pt on iOS.
  - Table layout reflows in portrait and landscape.
  - iPhone and iPad are both supported.
  - iPad can use extra space for scoreboard and history.
- [ ] Smoke test key UI on touch devices.
  - Template picker works under touch input.
  - Skin selector works under touch input.
  - Save and resume work in the iOS sandbox.
- [ ] Validate the cross-platform prototype end-to-end.
  - A complete hot-seat game can be played on iPhone, iPad, macOS, and Linux
    without regressions.
- [ ] Add iOS platform polish.
  - Haptic feedback fires on card play, trick capture, and marriage.
  - Dynamic Type support is available for accessibility.

---

## Phase 6 — AI opponents (algorithmic)

Goal: a single human plays against two AI seats. **No LLM yet — silent
AI.** The hard requirement is legal play under every built-in
`RuleConfig`; strong strategy can improve incrementally after the first
working AI.

- [ ] Define the AI player interface in `app/ai/`.
  - Interface covers `chooseBid`, `chooseTalonPass`, `chooseRaise`,
    `chooseCard`, and `chooseMarriage`.
  - Interface can observe game state without importing UI or LLM code.
- [ ] Implement rule-based bidding, talon, raise, and marriage decisions.
  - Bidding heuristic follows the [Strategy](../strategy.md) page.
  - Decisions are legal under the active `RuleConfig`.
  - Strategy tuning is strongest for the canonical Russian template first.
- [ ] Implement rule-based trick play.
  - AI obeys must-follow, must-beat, must-trump, and overtrump rules.
  - AI move legality works under every built-in `RuleConfig`, not just
    Russian.
- [ ] Enforce AI legality and latency.
  - Every AI move is validated by the same rules engine that guards human
    moves.
  - AI never produces an illegal move in tests.
  - Move latency is capped at 2 seconds with a "thinking..." indicator.
- [ ] Add single-player mode and difficulty levels.
  - Single-player mode is selectable from the main menu.
  - Easy, normal, and hard differ in marriage planning, trump leading, and
    defender cooperation.
- [ ] Re-test AI on all prototype platforms.
  - macOS, Linux, and iOS runs have no regressions.
- [ ] Add AI behavior for special contracts.
  - Mizère / no-tricks contract is played correctly when enabled.

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

- [ ] Create the AI/LLM module boundary and import-graph guard.
  - `app/ai/` and `app/llm/` live in separate modules and never import each
    other.
  - CI fails if the import graph is violated.
  - The LLM client's only public output type is text.
  - The LLM client has no method shape that could return a card, bid, or
    move.
- [ ] Prove LLM failures cannot affect gameplay.
  - With the LLM client stubbed to return chaos, errors, or nothing, every
    test from Phases 1, 2, 3, and 6 still passes unchanged.

### 7.2 `CharacterPreset` data model

- [ ] Implement `CharacterPreset` schema, game binding, and persistence.
  - Fields include name, avatar reference, short description, full LLM system
    prompt, voice/tone hints, default algorithmic difficulty, `bluffStyle`,
    spoken-language hint, and `schemaVersion`.
  - Each AI seat is bound to a `CharacterPreset` or `nil` for silent AI.
  - Character data has no causal effect on moves.
  - Presets round-trip through JSON and share schema-versioning conventions
    with `RuleConfig`.

### 7.3 Built-in characters

The slots matter more than the exact names; the product owner refines
copy later.

- [ ] Add the built-in character cast.
  - "Silent" is always available and is the default fallback when no LLM
    endpoint is configured.
  - At least 4 named characters have distinct voices and bluff styles.
  - Suggested archetypes: calculating aunt, old hustler, friendly amateur,
    smug newcomer.
  - Each named character has an avatar asset and complete LLM system prompt.
  - Built-in character UI copy is localisable.

### 7.4 Custom characters

- [ ] Implement custom character lifecycle and validation.
  - Clone a built-in character into an editable copy.
  - Edit name, description, system prompt, voice/tone, default difficulty, and
    bluff style.
  - Save, rename, delete, and reset custom characters.
  - Persist custom characters via `love.filesystem` as JSON.
  - Reject empty names, too-long system prompts, and invalid default
    difficulties.
  - Import or export a character as shareable JSON.

### 7.5 OpenAI-compatible LLM client

- [ ] Implement the non-blocking LLM client in `app/llm/`.
  - Client calls the OpenAI Chat Completions shape, or any endpoint that
    mimics it.
  - Base URL, API key, model name, and optional extra headers are
    configurable.
  - Calls never stall the game loop.
  - Per-call timeout defaults to 8 seconds.
  - Client returns text only and never decodes move-shaped responses.
  - Streaming responses can progressively update chat when supported.
- [ ] Verify endpoint compatibility.
  - OpenAI at `api.openai.com`.
  - OpenRouter.
  - Local Ollama through its `/v1` OpenAI-compatible mode.
  - LM Studio.

### 7.6 Endpoint settings & API key storage

- [ ] Build LLM settings and secure API-key storage.
  - Settings include base URL, API key, model name, optional extra headers,
    and test connection.
  - Defaults are blank; LLM chat is opt-in.
  - Without an endpoint, AI seats stay silent and the game is fully playable.
  - API key uses platform secure storage where available: macOS Keychain and
    iOS Keychain.
  - Linux fallback is a local file with a clear in-app notice.
  - API key is never logged, included in crash reports, or saved in game
    files.
  - User can forget the API key.
  - First enable shows a short "where does my data go?" explainer.

### 7.7 Character chat HUD

- [ ] Build the character chat UI and session controls.
  - Each AI seat shows avatar and name.
  - Incoming chat appears as a speech bubble or banner.
  - Chat is non-modal and never blocks turns or pauses the algorithm.
  - Player can mute or unmute a character from its avatar.
  - Human can talk back through a per-session text input.
  - Chat history is available from a sidebar or drawer.
  - Character text can be auto-translated to the player's locale through the
    same LLM endpoint.

### 7.8 Cost, rate & failure controls

- [ ] Add LLM cost, rate, and silent-failure controls.
  - Calls per deal are capped by a conservative user-adjustable setting.
  - At most one LLM call per character is in flight at a time.
  - Event sources are throttled, such as one bid reaction per character per
    auction round.
  - Missing key, 4xx, 5xx, timeout, parse failure, and rate limit errors are
    silent at the table.
  - Settings show the last diagnostic error for debugging.
  - Per-character daily call counter is visible in settings.
  - Built-in cast can use pre-baked offline lines when the LLM is
    unavailable.

### 7.9 Character editor UI

- [ ] Build the character picker and editor.
  - Game start lets the player choose a character or "Silent" for each AI
    seat.
  - Editor includes avatar slot, name, description, system-prompt textarea,
    voice/tone selector, default difficulty selector, and bluff style.
  - "Test in chat" sends a sample prompt and shows the response without game
    state.
  - Custom characters show a diff against their parent built-in character.
  - Avatar import can load an image from the save directory.

---

## Phase 8 — Education mode

Thousand is complicated by modern card-game standards — bidding, the
talon, marriages, must-trump and the barrel are all unfamiliar concepts
to many players. Education mode is the dedicated learning path for
people who want to **study** the game rather than just play it.

Distinct from the single-deal tutorial in Phase 4, Education mode is a
multi-lesson course from the main menu.

- [ ] Build the Education mode hub and lesson framework.
  - Main menu has "Learn to play".
  - Lesson list contains roughly seven 3–5 minute lessons.
  - Lessons are interactive scripted hands with hint balloons, not pure text.
- [ ] Implement the lesson sequence.
  - Lesson 1: deck and card rank.
  - Lesson 2: bidding.
  - Lesson 3: talon, pass, and raise.
  - Lesson 4: marriages and trump flips.
  - Lesson 5: trick-taking under must-follow, must-beat, and must-trump.
  - Lesson 6: scoring a deal and the barrel.
  - Lesson 7: variations primer for Russian, Polish, Ukrainian, 2-player,
    and 4-player templates.
- [ ] Add education support screens and progress.
  - Glossary scene is searchable and available from a `?` icon.
  - Progress tracking records per-lesson completion and resume state.
  - Lesson copy is keyed through `t()` and translated with the rest of the
    app.
- [ ] Add learner practice aids.
  - Practice mode is a one-deal sandbox where AI offers gentle suggestions.
  - Quick-reference popover is available during a real game.
  - Completion badges stay limited to simple checkmarks.

---

## Phase 9 — Release readiness

Goal: signed, localised, distributable builds for macOS, Linux and iOS.

### 9.1 Localisation

The i18n plumbing has existed since Phase 0; this section is translation
work against keys already used in the code.

- [ ] Finalise the English source locale and populate release translations.
  - English locale table is reviewed and treated as source of truth.
  - Russian, Polish, and Ukrainian tables are populated against the same
    keys.
  - Built-in character names and descriptions are localised into all four
    languages.
- [ ] Audit localisation in full play sessions.
  - No missing-key warnings occur in any locale.
  - Locale auto-detection works on first launch.
  - Manual language override is available in settings.

### 9.2 Persistence

The save format and save/load UI already land in Phase 2 and Phase 4.
This section hardens persistence for release.

- [ ] Audit auto-save across platform suspension points.
  - iOS app backgrounding.
  - macOS app quit.
  - Linux SIGTERM.
  - Terminal Ctrl-C during development.
- [ ] Add persistence migration and update survival.
  - Saves from earlier versions either migrate forward or are rejected with a
    clear, localised message.
  - User-saved rule templates, characters, and saved games survive app
    updates.
  - Score history for the last N games is viewable in the menu.

### 9.3 Packaging & distribution

- [ ] Build signed release packages for v1 platforms.
  - macOS `.app` bundle is code-signed and notarised.
  - Linux `.AppImage` and `.tar.gz` fallback are produced.
  - iOS `.ipa` is ready for App Store Connect.
- [ ] Prepare release metadata and privacy materials.
  - Store description and screenshots are ready.
  - Privacy policy explicitly says LLM chat is opt-in and the user's API key
    never leaves the device except when calling their configured endpoint.
- [ ] Add release diagnostics and versioning.
  - Crash reporting is opt-in and anonymised.
  - Crash reports scrub the API key.
  - Semver is stored in `conf.lua` and shown in the settings About screen.
- [ ] Add desktop update guidance.
  - Desktop builds include either an auto-update channel or a clear check for
    updates link.

---

## Standing engineering rules

These are not checklist tasks; they apply to every phase.

- Keep [Rules of Play](../rules/setup.md) in sync with code. If they
  disagree, fix the docs first.
- Every PR runs lint and tests; no merges on red.
- Every player-visible string goes through `t()`. No hard-coded UI
  literals, including placeholders, errors, and tutorials.
- No platform-conditional code in `core/` or `app/`. Platform-specific
  work lives in `ui/` or `platform/`.
- No absolute filesystem paths. Use `love.filesystem`.
- Touch and mouse input stay equivalent so the same code covers iOS,
  desktop, and later Android.
- Update this task list as work changes: tick completed tasks, add newly
  discovered tasks in sequence, and strike obsolete tasks with a note
  instead of deleting them.
- Each phase-closing PR includes a short retrospective.

---

## Phase 10 — Windows desktop *(post-v1)*

Goal: signed Windows build with the same Lua source.

- [ ] Arrange Windows test hardware and verify the existing `.love`.
  - Test with stock `love.exe` on Windows 10+.
- [ ] Package, sign, and validate the Windows build.
  - Windows `.exe` or installer is produced and code-signed.
  - Save files land in the expected per-user location and round-trip.
- [ ] Add Windows release polish.
  - Windows-specific app icon and metadata are ready.
  - CI matrix includes a Windows runner.

---

## Phase 11 — Android *(post-v1)*

Goal: Play Store build with the same Lua source.

- [ ] Arrange Android test hardware and wire love-android packaging.
  - Phone and tablet test devices are available.
  - Gradle project embeds the current `.love`.
- [ ] Re-validate Android runtime behavior.
  - Touch hit-targets meet the 48 dp Android convention.
  - Layout reflows across phone and tablet form factors.
  - `love.filesystem` save round-trip works in the Android sandbox.
- [ ] Prepare the Play Store build.
  - App icon, adaptive icon, and Play Store metadata are ready.
  - Signed `.aab` is ready for Play Console upload.
- [ ] Add Android platform polish.
  - Android haptic feedback matches iOS behavior where practical.
  - CI matrix includes an Android build runner.
