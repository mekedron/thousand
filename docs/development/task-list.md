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
- [x] Set up the e2e test harness for Phase 2+ UI work.
  - Pure-Lua mock of the `love` global so journey tests run under busted with
    no Love2D runtime.
  - Driver loads `main.lua` against the mock and exposes step / click /
    keypress / resize, plus a localised-string finder.
  - Recording captures `clear`, `print`, `printf`, `setColor`, `rectangle`,
    and `push` / `pop` / `translate` so journeys can assert what was drawn.
  - First sanity-check journey passes against the placeholder `main.lua` and
    is ready to extend when the scene skeleton lands.
  - Busted picks up `tests/e2e/` automatically and the 80%-of-`core/`
    coverage gate stays untouched.

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

- [x] Define the canonical `RuleConfig` baseline and the card model.
  - Card has suit (♠♣♦♥) and rank (9,J,Q,K,10,A).
  - Card point values are A=11, 10=10, K=4, Q=3, J=2, 9=0.
  - Trick rank order is A > 10 > K > Q > J > 9.
  - These values are read from the canonical Phase 1 `RuleConfig`, not
    duplicated as unrelated constants.
- [x] Build the deterministic 24-card deck module.
  - Deck builder returns exactly one card for every suit/rank pair.
  - Total deck card points equal 120.
  - Shuffle is seedable and reproducible in tests.

### 1.2 Dealing

- [x] Implement standard 3-player deal and deal validation.
  - Deal sequence is 3+3+3, 2 to talon, 2+2, 1 to talon, 2+2.
  - Each player ends with 7 cards and the talon has 3 cards.
  - Every completed deal still contains exactly 24 unique cards.
  - Misdeals such as wrong count or exposed card return typed errors.

### 1.3 Auction / bidding

- [x] Implement the auction state machine.
  - Auction starts at forehand and advances clockwise.
  - Opening minimum is 100; pre-talon maximum is 120.
  - Bid increments are 5 below 200 and 10 from 200 onward.
  - Pass is permanent.
  - Auction ends when two players have passed.
  - Declarer is the last remaining bidder at their final bid.
  - Illegal bid attempts return typed errors.

### 1.4 Talon, pass and raise

- [x] Implement talon reveal, pickup, pass, and post-talon raise.
  - The 3 talon cards are publicly revealed.
  - Declarer takes the talon and reaches 10 cards; opponents stay at 7.
  - Declarer passes 1 face-down card to each opponent, producing 8 / 8 / 8.
  - Declarer may raise after seeing the talon but cannot lower the bid.
  - Illegal raises, including wrong increment and below-current-bid values,
    return typed errors.

### 1.5 Marriages and trump

- [x] Implement marriage detection, declaration, bonuses, and trump state.
  - A marriage is K + Q of the same suit in one hand.
  - Marriage values are ♥=100, ♦=80, ♣=60, ♠=40.
  - A marriage is declared by leading the K or Q while on lead.
  - The bonus posts immediately.
  - No trump exists until the first declared marriage.
  - Declared marriage suit becomes trump from the next trick.
  - Multiple marriages are allowed in one deal and each replaces trump.
  - A marriage formed through the talon is legal.

### 1.6 Trick-taking

- [x] Implement legal-play validation and trick resolution.
  - Player must follow suit if possible.
  - Player must beat the led card if possible when following suit.
  - Player must trump when void in led suit and trump exists.
  - Player must overtrump if possible.
  - Player may discard freely only when holding neither led suit nor trump.
  - Trick winner is highest trump, otherwise highest card of led suit.
  - Trick winner leads next.
  - A deal is exactly 8 tricks.
  - Every illegal play is logged with the rule it broke.
- [x] Fix trick-count inconsistency in `docs/rules/setup.md`.
  - The overview at line 21 says "7 tricks played"; every other rules
    page and this task list establish 8 tricks per deal (each player
    holds 8 cards after the talon pass).

### 1.7 Scoring & barrel

- [x] Implement deal scoring and contract resolution.
  - Captured card points sum to at most 120 across all sides.
  - Marriage bonuses are credited to the player who declared them.
  - Captured card points round to nearest 5; marriage bonuses stay exact.
  - Declarer made contract when deal score is at least the bid.
  - Successful declarer adds the bid to running total.
  - Failed declarer subtracts the bid from running total.
  - Defenders independently add their captured deal scores.
- [x] Implement barrel and game-end scoring.
  - At 880, score freezes and the player has 3 deals to make 120 and win.
  - Falling off the barrel applies −120 and returns the player to 760.
  - Reaching 1000 wins.
  - Barrel collision rule is last-mounter survives; others fall off.
  - If multiple players cross 1000 in the same deal, declarer wins ties.

### 1.8 Engine tests

- [x] Build the core rules test suite.
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

- [x] Build the scene skeleton and game navigation.
  - Main menu, table, and end-of-game scenes exist.
  - New-game and abandon-game controls are available from the menu.
  - Buttons render hover, focus, pressed, and disabled visual states; menus
    are fully keyboard-navigable (Tab/arrows + Enter/Space + Esc).
  - Table scene exposes a visible `Menu` button so the back-out path works
    on touch devices, not just via Esc.
- [x] Build touch-ready input and reflowable table foundations.
  - Mouse and touch use the same action paths.
  - No required interaction depends on hover.
  - Primary card/table controls are sized for finger input from the first UI
    pass.
  - Table layout responds to window size instead of using fixed desktop-only
    coordinates.
- [x] Render the playable table state with placeholder assets.
  - 24-card deck, player hand, talon, current turn, current bid, running
    scoreboard, and end-of-game winner/final scores are visible.
- [x] Connect hot-seat input to the rules engine.
  - Player can click or tap cards through hit-tests.
  - Auction UI lets each player bid or pass in turn.
  - Talon reveal and pass-card interactions are playable.
  - Marriage declaration is available when leading a K or Q from a held
    marriage.
- [x] Add hot-seat privacy and hand-off flow.
  - A pass-to-next-player overlay hides inactive hands.
  - Each player only sees their own hand during private decisions.
- [x] Add a Settings scene with a hot-seat privacy toggle.
  - `app/settings.lua` persists user preferences to `settings.json` via
    `love.filesystem`, validated by `schemaVersion`.
  - `app/json.lua` provides the minimal encoder/decoder reused by Phase 2
    auto-save and Phase 3 templates.
  - Settings scene exposes one row + Back; Phase 5's full settings
    screen extends this scene with locale, sound, theme, and animation
    speed.
  - Disabling the toggle suppresses the privacy curtain entirely so a
    single tester can drive every seat without dismissing between turns.
- [x] Add legal-action affordances.
  - Cards that are legal under must-follow, must-beat, and must-trump rules
    can be visually distinguished.
  - Illegal player actions are blocked with localised feedback.
- [x] Route every player-visible string in the hot-seat MVP through `t()`.
  - This includes placeholder UI, error messages, button labels, and
    end-of-game text.
- [x] Add baseline auto-save and restore.
  - One auto-save slot writes on app suspend, graceful quit, and after every
    scored deal.
  - Save format is JSON via `love.filesystem`.
  - Save includes `schemaVersion`, running scores, hands, talon, bids,
    played tricks, declared marriages, and current trump.
  - Next launch restores the auto-save if present.

---

## Phase 3 — Rule template system

Goal: every variant from [Variations](../variations/index.md) is
represented as data in a single `RuleConfig` system and the engine
honours every selectable toggle. Each documented toggle is either
implemented and selectable, or explicitly marked deferred so built-in
templates and saved custom templates cannot accidentally depend on it.

### 3.1 `RuleConfig` model & engine wiring

- [x] Expand `RuleConfig` into the single schema for every engine toggle.
  - Every field has a type, allowed values, default value, and
    `schemaVersion` handling.
  - Every field records whether it is implemented, selectable, or deferred.
  - `RuleConfig` round-trips through JSON for persistence and saved games.
  - Incompatible combinations are rejected with clear, localisable errors.
- [x] Refactor the core engine so every variable rule reads from
  `RuleConfig`.
  - No hard-coded constants remain for rules that variants can change.
  - Engine tests pass under every built-in template added in this phase.

### 3.2 Toggle catalogue

Group toggles in `RuleConfig` so the UI can render clear sections. Each
toggle's wording maps to [House Rules](../variations/house-rules.md),
which remains the source of truth for behavior. Catalogue tasks mean
schema, validation, and UI representation; gameplay behavior is required
only for toggles marked selectable.

- [x] Add players and seating toggles.
  - Player count (2 / 3 / 4).
  - Partnership mode (none / fixed across-the-table), valid only for 4
    players.
  - 4-player configuration (dealer plays no talon / dealer sits out).
  - 2-player configuration (closed-talon draw stock / fixed deal no draw).
- [x] Add dealing and redeal-trigger toggles.
  - 4-nine redeal (off / optional / mandatory).
  - 3-nine redeal (off / optional).
  - 4-jack redeal (off / on).
  - Weak-hand redeal options.
  - Misdeal handling options.
  - All-pass handling options, including распасы reverse-scoring.
- [x] Add talon toggles.
  - Talon size (0 / 2 / 3).
  - Talon distribution options.
  - Talon-flip-after-first-round.
  - Pass-the-talon.
  - Buyback.
  - Hidden talon on minimum-100 contract.
  - Bad-talon redeal.
  - Talon re-buy.
  - Open discard.
- [x] Add bidding toggles.
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
- [x] Add marriage toggles.
  - Hearts / Diamonds / Clubs / Spades values.
  - Half-marriage capture bonus.
  - Trump activation timing.
  - Marriage announcement timing.
  - Drowned-marriage rule.
  - Ace marriage / тузовый марьяж.
  - One trump per deal.
- [x] Add trick-play toggles.
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
- [x] Add scoring toggles.
  - Rounding granularity.
  - Score declarer's actual deal points instead of bid on success.
  - Defender contributions.
  - Failed-contract distribution.
  - Declarer rounding before contract check.
- [x] Add opening-game, barrel, and endgame toggles.
  - Golden deal settings.
  - Barrel threshold, pit lock-in, deal count, fall-off penalty, collision
    rule, overshoot penalty, and reverse barrel.
  - Target score, going-over-target rule, tiebreaker, and dump truck /
    самосвал settings.
- [x] Add special-contract and penalty toggles.
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

- [x] Add built-in 3-player regional templates.
  - `Russian Thousand` is canonical and default at first launch.
  - `Polish Tysiąc` uses 2-card talon, 10-step increments only, and strict
    *przebijanie*.
  - `Ukrainian Тисяча` includes the bolt rule and optional 2-deal barrel.
- [x] Add built-in 2-player and 4-player templates.
  - `Two-player A` uses closed talon, 9-card hands, and draw stock.
  - `Two-player B` uses fixed deal, 7-card hands, and no draw.
  - `Four-player A` has dealer play, no talon, and 6 cards each.
  - `Four-player B` has dealer sit out and otherwise standard 3-player
    rules.
- [x] Add scripted engine tests for every built-in template.
  - Built-in templates use only implemented selectable toggles.
  - Each template can complete a full scripted deal.
  - Template-specific edge rules are asserted.

### 3.4 Custom templates

- [x] Implement custom template lifecycle and persistence.
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

- [x] Build the template picker and editor.
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

### 3.6 Toggle gameplay

Each toggle catalogued in 3.2 lands here as engine behaviour matching
[House Rules](../variations/house-rules.md), with table-scene UI that
exposes every new affordance and reflects every flow change. A task
flips its fields from `deferred` to `selectable` (or `implemented`
where the engine reads the value directly), adds any sibling fields
the variants reference, wires every variant into the table scene, and
ships scripted engine tests covering every value.

- [x] Implement players and seating gameplay.
  - `count` 2 runs end-to-end under both `two_player_config` values.
  - `count` 4 runs end-to-end under both `four_player_config` values.
  - `partnership_mode` `fixed_across_table` pools partner scores and
    routes lead/legality through the partnership.
  - Table layout reflows for 2- and 4-player counts (seat positions,
    hand sizes, scoreboard rows).
  - `partnership_mode` shows a partner indicator on each seat and a
    pooled-score row on the scoreboard.
  - `four_player_config` `dealer_sits_out` marks the dealer's seat as
    inactive during the deal.
  - `count`, `partnership_mode`, `four_player_config`, and
    `two_player_config` all flip to selectable.
  - Engine tests run scripted full deals for every player-count and
    seating-config combination.
- [x] Implement dealing and redeal triggers.
  - `four_nine_redeal` `optional` offers the entitled player a redeal;
    `mandatory` forces it.
  - `three_nine_redeal` `optional` offers the entitled player a redeal.
  - `four_jack_redeal` `on` offers the entitled player a redeal.
  - `weak_hand_redeal` `strict`, `loose`, and `counted` each detect
    weakness by their documented criteria; `counted` reads a new
    sibling threshold field.
  - `misdeal_handling` `soft_penalty` rotates dealer; `flat_penalty`
    deducts a new sibling penalty amount.
  - `all_pass_handling` `pass_out` rotates the deal without scoring;
    `raspassy` plays the deal under reverse-scoring.
  - Optional redeals (4-nine, 3-nine, 4-jack, weak-hand) prompt the
    entitled player with a "Redeal?" dialog; `mandatory` shows a
    non-dismissible banner before redealing.
  - `misdeal_handling` shows the dealer-rotate banner under
    `soft_penalty` and the deduction line under `flat_penalty`.
  - `all_pass_handling` distinguishes redeal, pass-out, and raspassy
    reverse-scoring play with their own banners.
  - All six fields flip to selectable.
  - Engine tests cover every variant value against scripted dealing
    fixtures.
- [x] Implement talon variants.
  - `flip_after_first_round` `on` keeps the talon closed during the
    first round of bidding.
  - `pass_the_talon` `on` lets the declarer concede the deal at the
    bid after seeing the talon.
  - `buyback` `on` lets the declarer discard the hand for a fresh deal
    at the new sibling `buyback_penalty`.
  - `hidden_on_minimum_100` `minimum_100_only` and `any_forced_100`
    suppress the talon reveal to defenders.
  - `bad_talon_redeal` `any_contract` and `minimum_100_only` redeal on
    a worthless talon (threshold lives in the new sibling
    `bad_talon_threshold`).
  - `open_discard` `on` deals the declarer's discards face-up.
  - `pass_the_talon` adds a "Concede deal" button after the talon
    reveal; `buyback` adds a "Buy back hand" button with the active
    penalty.
  - `hidden_on_minimum_100` keeps the talon closed to defenders;
    `bad_talon_redeal` shows a "Redeal — bad talon" modal driven by
    the same pattern as the dealing-time redeal modal.
  - `flip_after_first_round` shows the talon closed during the first
    round of bidding and flips it once a second round opens.
  - `open_discard` deals the declarer's discards face-up at the
    table.
  - Six house-rule fields flip to selectable
    (`flip_after_first_round`, `pass_the_talon`, `buyback`,
    `hidden_on_minimum_100`, `bad_talon_redeal`, `open_discard`); three
    new sibling fields (`buyback_penalty`, `bad_talon_threshold`,
    `rebuy_contract_value`) land in the schema. `size` and
    `distribution` keep their current status; `rebuy` stays deferred.
  - Engine tests cover every variant value against scripted talon
    scenarios.
- [x] Implement talon rebuy.
  - `rebuy` `on` triggers a second auction at the
    `rebuy_contract_value` after talon reveal; the rebuyer becomes the
    new declarer.
  - Table scene adds a "Buy talon at higher contract" affordance
    after the reveal.
  - `rebuy` flips to selectable; engine tests cover scripted rebuy
    scenarios end-to-end.
- [x] Implement Polish 2-card talon distribution.
  - `distribution` `pass_without_taking` runs the Polish flow where
    the declarer never picks the talon up.
  - `size = 2` lifts the engine's `unsupported_talon_size` guard for
    the Polish layout.
  - Talon area shrinks to two cards; pickup phase is replaced with a
    direct pass affordance.
  - `distribution` flips to selectable for `pass_without_taking`;
    `size` flips to implemented; engine tests cover a scripted full
    Polish deal.
- [x] Implement 2-player stock_draw talon distribution.
  - `distribution` `stock_draw` runs the 2-player Schnapsen-style
    per-trick draw on top of the existing 2-player Variant A stock
    infrastructure.
  - `distribution` flips to selectable for `stock_draw`; engine tests
    cover a scripted full 2-player Variant A deal.
- [x] Implement bidding house rules.
  - `forced_opening` `on` forces forehand to open at the minimum bid.
  - `forced_dealer_bid` `on` lands the dealer in the minimum-100
    contract when everybody else passes.
  - `blind_bid` `first_bid_double` doubles a successful or failed
    in-the-dark first bid.
  - `re_entry_after_pass` `on` lets a passed player re-enter the
    auction once.
  - `contra` `contra_only` arms defender doubles;
    `contra_and_redouble` adds the declarer's redouble; the engine
    doubles or redoubles the contract value accordingly.
  - `forced_bid_concession` `equal_split`, `each_full`, and
    `preset_ratio` each split the conceded bid by their documented
    rule.
  - `no_contract_without_marriage` `no_120_without_marriage` blocks
    bids ≥ 120 without a held marriage; `capped_by_marriages` caps the
    maximum bid at `120 + held marriage values`.
  - `negative_score_restriction` `on` limits a player at negative
    running score to the forced minimum-100 contract.
  - `named_contracts` `on` admits the special-contract bids at the
    auction.
  - `forced_opening` greys out forehand's pass button on the first
    bid.
  - `forced_dealer_bid` shows a banner assigning the dealer the
    minimum-100 contract when everyone passes.
  - `blind_bid` adds a "Bid blind" button before hand reveal and
    shows the doubling on outcome.
  - `re_entry_after_pass` exposes a "Re-enter" affordance to passed
    players.
  - `contra` adds defender "Contra" and declarer "Redouble" buttons
    before play.
  - `forced_bid_concession` adds a "Concede" button with the active
    split mode previewed.
  - `no_contract_without_marriage` greys out bids ≥ 120 (or above the
    marriage cap) when the player holds no marriage.
  - `negative_score_restriction` locks the restricted player's bid
    panel to "Take 100".
  - `named_contracts` surfaces the special-contract bid buttons in
    the auction.
  - All nine fields flip to selectable.
  - Auction state-machine tests cover every variant value.
- [x] Implement marriage house rules.
  - `half_marriage_capture_bonus` `on` credits the defender who
    captures both K and Q of the same suit; the bonus value lives in a
    new sibling field.
  - `trump_activation_timing` `immediate` re-ranks cards already
    played to the declaring trick.
  - `marriage_announcement_timing` `hand_announcement` lets the leader
    declare without leading the K or Q; `pre_first_trick` restricts
    declarations to the moment before the first trick.
  - `drowned_marriage` `retroactive_cancel` cancels declared marriages
    when a half is later captured.
  - `ace_marriage` `on` scores the four-aces bonus; `sets_trump` sets
    trump from the first Ace led after declaration.
  - `one_trump_per_deal` `on` keeps only the first declared marriage
    as the trump trigger.
  - `half_marriage_capture_bonus` shows the bonus row in the deal
    scoreboard when defenders capture both halves.
  - `trump_activation_timing` `immediate` plays a re-rank animation
    for cards already in the declaring trick.
  - `marriage_announcement_timing` exposes "Announce marriage"
    affordances at the points the active variant allows.
  - `drowned_marriage` `retroactive_cancel` plays a cancellation
    banner when the half is captured.
  - `ace_marriage` adds a "Declare four aces" affordance and an
    ace-marriage scoreboard row.
  - `one_trump_per_deal` suppresses the trump-flip animation on
    later marriages while still showing the bonus.
  - All six fields flip to selectable.
  - Engine tests cover every variant value against scripted marriage
    scenarios.
- [x] Implement trick-play house rules.
  - `must_overtake_strictness` `polish_strict` enforces the Polish
    `przebijanie` escalation when following suit.
  - `must_trump_strictness` `polish_strict` extends the same
    escalation to trump and overtrump obligations.
  - `defender_must_overtrump_declarer` `on` forces a defender to
    overtrump declarer's trump when able.
  - `lazy_revoke` `on` only punishes a misplay when called before the
    next lead.
  - `partial_trumping` `on` lets a defender holding only a lower trump
    discard rather than play it.
  - `last_trick_bonus` `on` credits the winner of the eighth trick;
    the bonus value lives in a new sibling field.
  - `slam_bonus` `fixed` adds a new sibling fixed bonus on a clean
    sweep; `doubled_bid` doubles the contract value on success.
  - `slam_against_penalty` `on` penalises a declarer who takes zero
    tricks.
  - `lead_trump_after_marriage` `on` forces a trump lead on the trick
    after a marriage declaration.
  - Stricter legality variants (`polish_strict`,
    `defender_must_overtrump_declarer`) update the legal-action
    highlights on each player's hand.
  - `lazy_revoke` only flags misplays during the short window before
    the next lead.
  - `partial_trumping` lights up the discard affordance when only
    lower trumps are held.
  - `last_trick_bonus`, `slam_bonus`, and `slam_against_penalty` each
    add their bonus or penalty row to the deal scoreboard with a
    matching animation.
  - `lead_trump_after_marriage` highlights only trump cards as legal
    on the trick after a marriage.
  - All nine fields flip to selectable.
  - Trick-resolution and legality tests cover every variant value.
- [x] Implement scoring house rules.
  - `actual_points_on_success` `on` scores `max(bid, actual deal
    points)` for the declarer.
  - `defender_contributions` `pooled` sums and splits defender deal
    points equally.
  - `failed_contract_distribution` `split_among_defenders`,
    `each_defender_full`, and `mirrors_forced_concession` each
    distribute the failed bid by their documented rule.
  - `declarer_rounding_before_contract_check` `on` rounds the
    declarer's captured points before comparing them to the bid.
  - `actual_points_on_success` shows the actual deal points alongside
    the bid when the override applies.
  - `defender_contributions` `pooled` collapses defender rows into a
    pooled-score row.
  - `failed_contract_distribution` renders the active split in the
    deal scoreboard.
  - `declarer_rounding_before_contract_check` shows the rounded total
    beside the raw captured points.
  - All four fields flip to selectable.
  - Scoring tests cover every variant value against scripted deal
    outcomes.
- [x] Implement opening-game, barrel, and endgame house rules.
  - `golden_deal` `on` forces every player in turn through a mandatory
    120 contract for the opening N deals; the marriages-doubled,
    blind-allowed, and penalty-doubling sub-flags live in new sibling
    fields.
  - `pit_lock_in` `on` adds an intermediate lock-in score; the pit
    score lives in a new sibling field.
  - `collision_rule` `first_mounter` and `all_collide_fall_off` each
    resolve simultaneous barrel arrivals by their documented rule.
  - `overshoot_penalty` `on` penalises a hero-bid above 120 from the
    barrel.
  - `reverse_barrel` `on` mirrors the barrel state machine at -880.
  - `going_over_target` `exact_only` caps the running total at
    `target_score - 1` until a player lands on it exactly.
  - `tiebreaker` `high_score` and `continuation` each break ties by
    their documented rule.
  - `dump_truck` `positive_only` resets the running total at +555;
    `both_signs` triggers at ±555.
  - `golden_deal` shows a "Golden deal — forced 120" banner for each
    opening deal, skips the bidding step, and assigns the contract
    directly to the next player in turn.
  - `pit_lock_in` shows the pit marker on the scoreboard (e.g. "700
    lock — must clear").
  - `collision_rule` resolves simultaneous barrel arrivals with a
    banner that names the active rule.
  - `overshoot_penalty`, `reverse_barrel`, and `dump_truck` each
    render their state on the scoreboard with a matching animation.
  - `going_over_target` `exact_only` shows a "must land exactly"
    indicator above the target row.
  - `tiebreaker` resolves cross-target ties with a banner that names
    the active rule.
  - All eight fields flip to selectable.
  - Scoring and state-machine tests cover every variant value.
- [x] Implement special contracts.
  - `mizere` `on` admits the zero-tricks no-trump contract; the
    contract value lives in a new sibling field.
  - `slam_contract` `on` admits the all-tricks contract; the contract
    value lives in a new sibling field.
  - `open_hand` `on` plays the deal face-up with doubled scoring on
    success and failure.
  - The engine's auction, trick-play, and scoring all honour each
    special end-to-end.
  - The auction surfaces "Mizère", "Slam", and "Open hand" bid
    buttons under `named_contracts`.
  - The deal scene shows the active contract as a banner ("0 tricks
    goal", "all 8 tricks", "open hand") and adapts legality, scoring,
    and visibility accordingly.
  - `open_hand` reveals the declarer's hand to all seats for the
    duration of the deal.
  - All three fields flip to selectable.
  - Engine tests run scripted full deals for every special contract.
- [x] Implement penalty house rules.
  - `revoke` `flat` deducts a fixed 120; `configurable` deducts a new
    sibling fixed amount.
  - `talon_look` `stricter` forfeits the deal and awards the bid to
    the opposing side.
  - `showing_hand` `strict` deducts the full bid.
  - `zero_tricks` `consecutive_three` and `any_three` (бoлт / палка)
    track and penalise zero-trick streaks; the declarer-exempt and
    golden-deal-doubled sub-flags live in new sibling fields.
  - `cross` `on` accumulates two crosses before deducting a fixed
    penalty; the penalty value lives in a new sibling field.
  - Each penalty (revoke, talon-look, showing-hand, zero-tricks
    бoлт, cross) shows a deduction animation and a deal-scoreboard
    row when triggered.
  - The bolt and cross counters are visible on the running scoreboard
    so players see how close they are to the threshold.
  - All five fields flip to selectable.
  - Penalty engine tests cover every variant value.
- [x] Extend the built-in template engine tests to full scripted deals.
  - `Polish Tysiąc` plays a scripted deal under `talon.size = 2` once
    the talon-variants gameplay task lifts the dealer's
    `unsupported_talon_size` guard.
  - `Two-player A` and `Two-player B` each play a scripted deal once
    the players-and-seating gameplay task lifts the dealer's
    `unsupported_player_count` guard for `count = 2`.
  - `Four-player A` and `Four-player B` each play a scripted deal
    once the same task lifts the guard for `count = 4`.
  - Tests live alongside `tests/spec/core/builtins_spec.lua` and
    replace the existing typed-error pins.
- [x] Implement named-contract scoring & play.
  - Follow-up to the Phase 3.6 bidding-house-rules wiring: the
    auction now accepts mizère / slam / open-hand bids and the table
    scene renders the buttons, but `Session:on_auction_end` returns
    `not_yet_supported_named_contract` when one wins because
    `core/scoring.lua` does not yet understand structured `final_bid`
    values. This task wires the scoring + play paths so a winning
    named bid becomes a playable deal.
  - Define mizère scoring (declarer must take zero tricks; canonical
    contract value 120; failure penalises the bid amount).
  - Define slam scoring (declarer must take all eight tricks; contract
    value reads from `bidding.slam_contract_value` once that sibling
    field exists).
  - Define open-hand scoring (declarer plays face-up; success and
    failure both doubled per house-rules.md).
  - Extend `core/scoring.lua` to dispatch on `type(final_bid) ==
    "table"`; route to the per-contract scorer.
  - Drop the `not_yet_supported_named_contract` stub from
    `app/session.lua`'s `on_auction_end`.
  - Engine + session + e2e tests covering the three contracts.

### 3.7 Canonical Russian alignment with book ruleset

Goal: align `canonical_russian` and the engine with the "common
standard" Russian rules described in the reference book
(`TMP - Rules according to a book.md`). The audit identified six
engine gaps and a small set of default-value mismatches; this
section closes the gaps (or marks them explicitly deferred), updates
the canonical defaults, and brings the docs in line with the book's
terminology.

Gaps the audit flagged against the book's standard:

- **Not implemented:** marriage trick-required precondition,
  write-off / сдача mid-deal concession, no-win-for-3-rounds penalty,
  every-third-write-off penalty, reset-to-zero on third barrel
  fall-off, dark-game stick doubling.
- **Partially implemented:** dedicated "two nines in the widow"
  redeal trigger (today subsumed by the `bad_talon_threshold` path),
  multiple-players-on-the-barrel coexistence (the existing comment
  in `core/rule_config.lua` mentions a future `coexist` value that
  is not in `allowed`), configurable dump-truck threshold (canonical
  ±555 hard-coded; book mentions a +550 variant).
- **Out of scope (explicitly deferred):** 32-card deck variant
  (book's optional 6-A deck with sevens = 7, eights = 0), cut-deck
  nine/jack penalty (procedural, not suitable for software
  simulation).

The work is grouped into four agent-sized chunks. Tasks 1–3 close
the engine gaps; the closing task flips the canonical defaults and
brings the docs in line. The write-off task lands first because the
every-third-write-off counter in task 2 depends on it.

- [x] Implement write-off / сдача and the every-third-write-off
  penalty.
  - Book: a declarer who sees they cannot make their contract may
    "write off" — subtract the full bid from themselves and credit
    half of the bid to each opponent. Every third write-off then
    triggers the standard 120 penalty. Distinct from
    `bidding.forced_bid_concession`, which only fires on a forced
    100 contract.
  - Add `bidding.write_off` (allowed `{"off", "on"}`, default
    `"off"`) and `bidding.write_off_split` (allowed
    `{"half_to_each", "equal_split"}`, default `"half_to_each"`).
  - Add `penalties.write_off_streak` (allowed `{"off", "any_three"}`,
    default `"off"`), `penalties.write_off_streak_threshold` (default
    3, bounds `[2, 5]`), and `penalties.write_off_streak_penalty_amount`
    (default 120, bounds `[0, 240]`).
  - Engine surfaces a "Write off" action to the declarer between
    tricks (before the eighth trick) and applies the configured
    split, pooling credit through the active
    `scoring.defender_contributions` on partnerships.
  - Engine maintains a per-seat write-off counter; on every Nth
    write-off the penalty fires and the counter resets. The counter
    survives auto-save / resume.
  - All five fields flip to selectable. Engine + session tests cover
    canonical, partnership, and 2-/4-player layouts; counter
    triggering and reset are exercised across scripted multi-deal
    runs.
  - Table scene exposes a localised "Write off" button when the
    toggle is on; the running scoreboard shows the write-off counter
    so players can see how close they are to the threshold.

- [ ] Implement the cross-deal counter penalties: no-win-for-3-rounds,
  three-falls reset, and dark-game stick doubling.
  - Book: a seat with no win in 3 consecutive (or total) rounds takes
    the 120 penalty; a player who fell off the barrel three times
    has their running total reset to zero; in a dark (blind-bid)
    game the received stick is doubled.
  - Add `penalties.no_win_streak` (allowed `{"off",
    "consecutive_three", "any_three"}`, default `"off"`),
    `penalties.no_win_streak_threshold` (default 3, bounds `[2, 5]`),
    and `penalties.no_win_streak_penalty_amount` (default 120, bounds
    `[0, 240]`). Shape mirrors the existing `zero_tricks` cluster.
  - Add `barrel.fall_count_resets_to_zero` (allowed `{"off", "on"}`,
    default `"off"`); the third fall overrides the standard
    `fall_off_penalty` and zeroes the running total.
  - Add `penalties.zero_tricks_dark_game_doubled` (allowed
    `{"off", "on"}`, default `"off"`); shape mirrors the existing
    `zero_tricks_golden_deal_doubled` sub-flag.
  - Engine tracks per-seat winless-streak and barrel-fall-off
    counters; both survive auto-save / resume. "Winning a deal" is
    pinned in the scoring spec as the declarer making contract or a
    defender capturing positive deal points, so the streak rule
    cannot drift downstream.
  - Under `consecutive_three`, the no-win-streak counter resets on
    any winning deal; under `any_three`, only the penalty trigger
    resets it.
  - When `bidding.blind_bid` is active for the deal and the dark-
    game toggle is `"on"`, a zero-tricks seat earns 2 sticks instead
    of 1.
  - All five fields flip to selectable. Scoring engine tests cover
    every counter path across scripted multi-deal runs; auto-save
    round-trips assert the counters persist.
  - Running scoreboard shows the no-win and barrel-fall counters
    next to the existing zero-tricks/cross counters so players see
    their progress toward the threshold.

- [ ] Implement marriage trick-required precondition and the minor
  book toggles.
  - Book default: a marriage may only be declared once the seat has
    already taken at least one trick; the trickless variant is the
    exception. Plus a cluster of smaller book items needed for
    parity.
  - Add `marriages.trick_required` (allowed `{"on", "off"}`, default
    `"on"`); the engine refuses K-Q lead-time declaration when the
    seat has no captured trick. `marriage_announcement_timing`
    interacts correctly under both values
    (`hand_announcement` / `pre_first_trick` still gate on the trick
    requirement). The four-aces ace marriage already requires a
    trick — sanity-check the path under the new shared field.
  - Extend `barrel.collision_rule` with a new `"coexist"` value
    (multiple players sit on the barrel simultaneously, each
    running their own countdown). Implement fully or land it
    deferred with a comment citing this task.
  - Add `endgame.dump_truck_threshold` (default 555, bounds
    `[100, 1000]`) so a table can opt for the +550 variant the book
    mentions; the existing `dump_truck` toggle keys off this value.
  - Add `dealing.two_nines_in_talon_redeal` (allowed `{"off",
    "any_contract", "minimum_100_only"}`, default `"off"`) as a
    dedicated trigger distinct from the threshold-based bad-talon
    redeal.
  - Mark 32-card deck (book's optional 6-A deck with sevens = 7,
    eights = 0) and the cut-deck nine/jack penalty as explicitly
    deferred in the schema with comments naming the deferral
    reason ("out of scope for v1" / "procedural; not suitable for
    software simulation").
  - All four newly-selectable fields flip to selectable; engine
    tests cover marriage trick-required across forehand-leads-first
    scenarios and the four-aces path. Schema specs cover the new
    sibling fields and the deferred markers.
  - Built-in templates that legitimately allow trickless
    declaration pin `marriages.trick_required = "off"` explicitly.

- [ ] Update `canonical_russian` defaults to match the book's standard
  and refresh the documentation.
  - Flip `penalties.zero_tricks` from `"off"` to `"any_three"` (book
    treats the every-3-sticks penalty as part of the standard
    penalty system).
  - Flip `endgame.dump_truck` from `"off"` to `"both_signs"` (book
    describes ±555 reset as a standard rule).
  - Land `marriages.trick_required` at `"on"` (default of the new
    field; matches the book default).
  - All other Phase 3.7 fields stay at their `"off"` defaults — the
    book frames them as agreed-in-advance.
  - Non-Russian built-ins (`polish`, `ukrainian`, `two_player_a`,
    `two_player_b`, `four_player_a`, `four_player_b`) override any
    new default that would change their scripted scoring or
    legality.
  - Update every spec that asserts the old defaults; the full
    `tests/spec/core/builtins_spec.lua` scripted deals still pass.
  - `docs/rules/*` adopts the book's vocabulary where it fits
    naturally: widow / прикуп, stick / pole, boast / overboast,
    dump truck / самосвал, write-off / сдача.
  - `docs/variations/russian.md` lists the canonical defaults
    explicitly (3-sticks penalty on, dump truck on, marriage
    requires a trick) and the toggles that remain off-by-default.
  - `docs/variations/house-rules.md` gains entries for the new
    toggles introduced in tasks 1–3 (write-off, every-third-
    write-off, no-win-streak, three-falls reset, dark-game stick
    double, coexist barrel collision, dump-truck threshold,
    two-nines-in-talon redeal).
  - `docs/variations/index.md` adds a "Comparison with the
    reference book" section that lists every gap that stays
    deferred after 3.7 (32-card deck, cut-deck procedural rule).

---

## Phase 4 — Bot opponents (algorithmic)

Goal: a single human plays against the rest of the seats filled by
algorithmic bots. **No LLM yet — silent bots.** The hard requirement is
legal play under every built-in `RuleConfig`. Every selection a human
makes at the table — every modal, every toggle-gated affordance, and
every per-turn action introduced by Phase 3.6 — has a matching bot
hook so a non-human seat can be driven without clicks. Strategy
quality starts with the canonical Russian template and improves
incrementally; legality is universal from the first commit.

:::warning[The bot is pure decision]
The bot module observes a read-only session view and returns engine
actions. It must never mutate state directly, never import from
`ui/`, and never import from `app/llm/`. CI guards the import graph.
Phase 7 (LLM characters) extends presentation only — moves stay
algorithmic.
:::

### 4.1 Bot interface and engine-driver loop

- [ ] Define the bot player interface in `app/bot/`.
  - Interface covers `chooseBid`, `chooseTalonPass`, `chooseRaise`,
    `chooseCard`, and `chooseMarriage`, plus an entry for every
    additional decision surface introduced by Phase 3.6: accept or
    decline a redeal offer, accept or decline a bad-talon redeal,
    claim or decline a rebuy, take the talon vs concede vs buy back,
    pass talon cards (Russian, Polish, 2-player-B discard), raise or
    skip raise, and start the next deal at deal-done.
  - Each entry is a pure function over a read-only session view and
    the active seat; it returns the action to invoke on the engine,
    not the mutation.
  - The view exposes only the existing read-only session accessors
    (`hands`, `legal_cards`, `current_turn`, `current_phase`,
    `current_bid`, `current_trick`, `trump`, `talon_cards`,
    `redeal_offer`, `bad_talon_offer_state`, `rebuy_offer_state`,
    `available_marriages`, `config`); no UI or LLM imports.
  - CI guards that `app/bot/` imports nothing from `ui/` or
    `app/llm/`.
- [ ] Wire the bot driver into the table scene.
  - When `current_turn()` is a bot seat, the table scene calls the
    bot module for that seat and applies the returned action via
    the same Session mutator a human button would call.
  - Modal awaiting-state phases (`awaiting_redeal_decision`,
    `awaiting_bad_talon_decision`, `awaiting_rebuy_decision`) use
    the same path: the offer state names the responsible seat, the
    bot decides, and the scene routes accept or decline.
  - One-shot intra-phase affordances (talon take / concede / buy
    back, pass talon per opponent, raise or skip raise, Polish pass,
    2-player-B discard, declare-marriage-then-play) chain through
    the same loop — the bot returns one action per call until the
    phase moves on.
  - A "thinking…" indicator runs while a seat is deciding;
    effective decision latency is capped at 2 s including the
    indicator.

### 4.2 Single-player mode and seat assignment

- [ ] Add single-player mode and per-seat bot/human assignment.
  - Single-player is selectable from the main menu and starts a
    game with one human seat and the rest filled by bots under the
    active `RuleConfig`.
  - The new-game flow also exposes per-seat bot vs human pickers so
    mixed compositions (e.g. 2 humans + 1 bot) work for any
    supported player count.
  - The hot-seat privacy curtain is suppressed for bot seats — no
    pass-the-device prompt before a bot move — but stays between
    consecutive human seats under the existing privacy toggle.
  - Save format records each seat's bot binding alongside the
    `RuleConfig` snapshot so saved games restore with the same
    composition. (Phase 5.3's "assigned characters per seat"
    requirement extends this binding; Phase 7 fills the character
    layer.)
- [ ] Add bot difficulty levels.
  - Easy, normal, and hard differ in bidding aggression, marriage
    planning, trump leading, discard quality, and — where the rule
    set permits it — defender cooperation.
  - Difficulty is a per-seat setting on the new-game flow.

### 4.3 Baseline-legal bot play for shipped decision surfaces

These tasks land legal-only bot logic for every surface that already
exists after Phase 2 plus Phase 3.6's first half. Strategy tuning
happens in 4.4.

- [ ] Implement legal bot play for the auction.
  - The bot bids or passes within `bidding.opening_min`,
    `bidding.pre_talon_max`, and the active increment thresholds.
  - The bot never proposes an illegal bid and never passes when the
    engine forbids it.
- [ ] Implement legal bot play for redeal offers.
  - The bot accepts or declines `four_nine_redeal`,
    `three_nine_redeal`, `four_jack_redeal`, and `weak_hand_redeal`
    modal prompts during `awaiting_redeal_decision`.
  - Mandatory variants are auto-accepted; optional variants default
    to accept on weak hands and decline on borderline ones,
    configurable by difficulty.
- [ ] Implement legal bot play for the talon flow.
  - At `talon` revealed status the bot picks one of: take talon,
    concede deal (`pass_the_talon`), buy back hand (`buyback`), or —
    under `pass_without_taking` — pass two talon cards directly to
    opponents, against the active `talon.distribution`.
  - After taking, the bot passes one card to each opponent; under
    `closed_talon_draw_stock` it follows the 2-player Variant A
    flow and under `fixed_deal_no_draw` it picks the discard card.
  - The bot raises by one valid increment when the talon clearly
    boosts the bid value, otherwise calls `skip_raise`.
- [ ] Implement legal bot play for bad-talon and rebuy modals.
  - At `awaiting_bad_talon_decision` the bot accepts a redeal when
    the talon points are below the active threshold and the
    contract is in the gated range; otherwise it declines.
  - At `awaiting_rebuy_decision` each defending bot claims rebuy at
    `talon.rebuy_contract_value` only when the held hand justifies
    the forced contract; otherwise it declines and the queue
    advances to the next defender.
- [ ] Implement legal bot play for tricks.
  - The bot obeys must-follow, must-beat, must-trump, and overtrump
    rules via the engine's `legal_cards()` helper.
  - On lead the bot considers `available_marriages()` and can
    declare a marriage by leading the K or Q.
  - Under 2-player Variant A the bot continues to play through both
    `tricks_phase()` substates (`draw` and `strict`).
  - Bot move legality holds under every built-in `RuleConfig`, not
    just Russian.
- [ ] Implement legal bot play for deal-done.
  - When the seat at `deal_done` is a bot, the table scene auto-
    calls `start_next_deal()` after a short pause that lets the
    final-deal scoreboard settle.

### 4.4 Strategy tuning (canonical Russian first)

- [ ] Tune bot bidding heuristics against the canonical Russian
  template, following the [Strategy](../strategy.md) page.
- [ ] Tune bot talon passing and raise heuristics so the declarer
  retains marriages and trump strength when possible.
- [ ] Tune bot trick play so the leader plans marriages, the
  declarer pulls trumps efficiently, and defenders cooperate where
  the rule set allows.
- [ ] Confirm canonical-Russian tuning against scripted full-game
  fixtures with known good and bad outcomes.

### 4.5 Bot logic for pending Phase 3.6 toggles

Each task lands the bot logic alongside the matching 3.6 toggle once
that toggle's engine and UI ship. Until the matching 3.6 task
lands, the toggle stays deferred for bot seats too — exactly as it
is for human seats.

- [ ] Implement bot logic for bidding house rules.
  - `forced_opening`, `forced_dealer_bid`, `blind_bid`,
    `re_entry_after_pass`, `contra` and redouble,
    `forced_bid_concession`, `no_contract_without_marriage`,
    `negative_score_restriction`, and `named_contracts` each get
    bot behaviour matching the new affordance.
- [ ] Implement bot logic for marriage house rules.
  - `marriage_announcement_timing` `hand_announcement` and
    `pre_first_trick` use the new declaration affordances.
  - Under `ace_marriage` the bot declares the four-aces bonus when
    eligible.
  - `drowned_marriage`, `trump_activation_timing`,
    `half_marriage_capture_bonus`, and `one_trump_per_deal` are
    automatic in the engine; the bot just plays cleanly under them.
- [ ] Implement bot logic for trick-play house rules.
  - Stricter `polish_strict` legality,
    `defender_must_overtrump_declarer`, `partial_trumping`,
    `last_trick_bonus`, `slam_bonus`, `slam_against_penalty`,
    `lead_trump_after_marriage`, and `lazy_revoke` each adjust
    card-choice heuristics.
- [ ] Implement bot logic for special contracts.
  - Mizère: bid only when the held hand is clearly bid-safe; play
    every trick to lose. Slam: bid only on hand strength
    sufficient for an 8-trick sweep. Open hand: keep bidding
    aware of the visible-hand penalty/bonus; play stays
    algorithmic.
- [ ] Implement bot logic for opening-game, barrel, endgame, scoring, and
  penalty toggles.
  - Behaviour changes are mostly bidding posture (forced 100 on
    `golden_deal`, defensive play near `barrel.threshold`, hero-
    bid avoidance under `overshoot_penalty`, exact-landing posture
    under `going_over_target = exact_only`). Penalty rules are
    automatic in the engine; the bot just plays cleanly under them.

### 4.6 Bot legality, latency, and tests

- [ ] Add the all-bot legality guarantee.
  - Every bot move passes through the same engine that gates human
    moves.
  - A property-style test runs N random full games for each
    built-in template with all-bot seats and asserts no illegal
    action is ever proposed.
- [ ] Add a scripted bot stub for journey tests.
  - The stub is deterministic and ignores strategy; it returns
    the first legal action for each surface.
  - Journeys that script all seats by deck-seeding move to bot-
    driven seats backed by the stub, so the journey harness no
    longer needs to know which seats are scripted.
- [ ] Re-test bot play on supported desktop platforms.
  - macOS and Linux runs have no regressions.
  - The "thinking…" indicator and 2 s latency cap hold under the
    real Love2D loop.

---

## Phase 5 — UX & polish

Goal: it looks and feels like a card game, not a prototype.

### 5.1 Look & feel basics

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

### 5.2 Card skins

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

### 5.3 Save & load games

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

## Phase 6 — iOS port (cross-platform prototype)

Goal: the same Lua source builds and runs on **macOS, Linux and iOS**.
The full game plays correctly on every v1 target.

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
  - A complete game can be played on iPhone, iPad, macOS, and Linux
    without regressions.
- [ ] Add iOS platform polish.
  - Haptic feedback fires on card play, trick capture, and marriage.
  - Dynamic Type support is available for accessibility.

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

- [ ] Create the bot/LLM module boundary and import-graph guard.
  - `app/bot/` and `app/llm/` live in separate modules and never import each
    other.
  - CI fails if the import graph is violated.
  - The LLM client's only public output type is text.
  - The LLM client has no method shape that could return a card, bid, or
    move.
- [ ] Prove LLM failures cannot affect gameplay.
  - With the LLM client stubbed to return chaos, errors, or nothing, every
    test from Phases 1, 2, 3, and 4 still passes unchanged.

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

Distinct from the single-deal tutorial in Phase 5, Education mode is a
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

The save format and save/load UI already land in Phase 2 and Phase 5.
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
