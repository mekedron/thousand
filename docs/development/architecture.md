---
sidebar_position: 1
title: Architecture (High-Level)
---

# Architecture (High-Level)

A **map of the codebase, not a specification** — enough for a new
engineer to know where things live and what depends on what. Detailed
design (data structures, algorithms, file formats) belongs in code
review, not here.

## Stack at a glance

| Layer | Choice | Why |
|---|---|---|
| Engine | **Love2D** (Lua 5.1/LuaJIT) | Tiny, stable, perfect for 2D cards. Hard constraint. |
| Language | **Lua** | What Love2D speaks. |
| Build for desktop | `love` runtime + platform launchers | Native on macOS and Linux today; Windows uses the same runtime when added post-v1. |
| Build for iOS | **love-ios** (Love2D's iOS port) via Xcode wrapper | Same Lua source, packaged as an iOS app. |
| Build for Android *(post-v1)* | **love-android** Gradle project | Same Lua source; packaging only. |
| Persistence | Love2D `love.filesystem` (JSON files) | No DB; v1 has only local data. |
| Localisation | Plain Lua tables keyed by locale, used **from day one** | Every UI string is keyed via `t()`; translations are added in Phase 9 against the same keys, not retrofitted. |

We are **not** introducing a separate UI framework, ECS, networking
library or scripting layer. Love2D is enough.

## Logical layers

The codebase is divided into four layers. Each layer may only depend on
the layers **below** it.

```
┌─────────────────────────────────────────────────────────┐
│  4. Platform / Shell    (entry points, packaging)       │
├─────────────────────────────────────────────────────────┤
│  3. Presentation        (scenes, rendering, input, SFX) │
├─────────────────────────────────────────────────────────┤
│  2. Application         (game loop, AI, persistence)    │
├─────────────────────────────────────────────────────────┤
│  1. Core / Rules        (pure Lua, deterministic)       │
└─────────────────────────────────────────────────────────┘
```

### 1. Core / Rules — pure Lua, no Love2D

- The deck, cards, hands, the talon.
- The auction state machine.
- Trick-taking with must-follow / must-beat / must-trump.
- Marriages and trump switching.
- Scoring and the barrel.
- A **`RuleConfig`** value object — the single source of truth for every
  rule toggle (player count, talon size, bid increments, marriage values,
  must-trump strictness, barrel deal count, …). The rules engine **reads
  every variable rule from `RuleConfig`** rather than from hard-coded
  constants. The known variants (Russian / Polish / Ukrainian / 2-player /
  4-player) are simply **built-in `RuleConfig` instances**.

This layer **must not import `love`**. It must be runnable and unit-testable
under plain `lua` from the command line. This is the part that the
[Rules of Play](../rules/setup.md) directly maps onto.

### 2. Application — orchestration

- The high-level game loop: deal → bid → talon → tricks → score.
- **Algorithmic AI players** (one or more difficulty levels). This module
  is what actually decides every move. **It must not import the LLM
  client.**
- **Save / load** of in-progress games. Auto-save on every scored deal
  and on suspend; manual named-slot saves between deals. The save
  payload includes a snapshot of the active rule template's toggles
  (not just its name) so a loaded game replays under the exact rules
  it started with, even if the template has since been edited or
  deleted. JSON-on-disk via `love.filesystem`, versioned by
  `schemaVersion`.
- **Template manager** for `RuleConfig` (built-in + user-saved).
- **Character manager**: a `CharacterPreset` data type that pairs a
  personality (name, avatar, description, LLM system prompt, voice/tone
  hints, default difficulty) with an algorithmic AI seat. Built-in
  characters ship as constants; users can clone / edit / save their own.
  Same shape as the rule-template system — characters are **data**, not
  code.
- **LLM client** (`app/llm/`): a tiny OpenAI-compatible HTTP client
  used purely for character chat. Configured globally with endpoint URL,
  API key and model name. Returns **text only**; has no API for picking
  moves. Failures (timeout, 4xx/5xx, missing key) degrade silently — the
  character just doesn't speak.
- **Skin manager**: registers built-in card-skin asset packs (face cards,
  backs, table felt) and exposes the active skin to the Presentation
  layer.
- **i18n module**: a tiny `t(key, …)` lookup against the locale table
  loaded from `assets/i18n/<locale>.lua`. The active locale lives in
  settings. Every UI string in the codebase goes through this from the
  first UI commit; translation work in Phase 9 is purely populating
  locale tables.
- Settings (active rule template, default characters per seat, active
  card skin, LLM endpoint config, language, sound, accessibility).

This layer uses the Core layer and exposes a clean interface to the
Presentation layer. It uses Love2D only for filesystem and timers — and,
in the LLM client, the network.

### 3. Presentation — what the player sees and hears

- Scenes: main menu, settings, table, scoreboard, tutorial, end-of-game,
  template editor, character editor.
- Card rendering and animations (deal, play, capture, trump-flip),
  driven by the **active card skin** (asset pack) chosen in settings.
- Input: mouse / keyboard on desktop, touch on iOS.
- Sound effects and music.
- **Character chat HUD**: a small banner / speech-bubble per AI seat that
  surfaces text from the LLM client when it arrives, and a player-side
  text input so the human can talk back. Subscribes to the LLM client;
  never queries it for a move.
- Localised text and number formatting.

### 4. Platform / Shell — the boring outer ring

- `main.lua` and `conf.lua` for Love2D.
- macOS `.app` packaging.
- Linux `.AppImage` / tarball packaging.
- iOS Xcode project that embeds the Love2D iOS runtime and our `.love`
  payload.
- App icons, splash, signing, store metadata.

## Module map (proposed top-level layout)

```
core/                   -- layer 1 (pure Lua, no love.*)
  rules/                -- engine, parameterised by RuleConfig
  rule_config.lua       -- RuleConfig schema + built-in templates
  characters.lua        -- CharacterPreset schema + built-in characters
app/                    -- layer 2 (orchestration, persistence, AI, LLM)
  ai/                   -- algorithmic AI — picks moves, never talks
  llm/                  -- OpenAI-compatible client — talks, never picks
  templates/            -- user-saved RuleConfig persistence
  characters/           -- user-saved CharacterPreset persistence
  skins/                -- skin registry
ui/                     -- layer 3 (scenes, rendering, input, chat HUD)
assets/
  skins/                -- one subdirectory per built-in skin
  avatars/              -- one image per built-in character
  fonts/, sounds/, i18n/
main.lua                -- layer 4 entry point
conf.lua
tests/                  -- pure-Lua unit tests against core/ and app/
platform/
  macos/
  linux/
  ios/
docs/                   -- this site
```

The exact filenames inside each directory are **not** dictated here — that
is for the developer to settle as they implement, with code review.

## The algorithm-vs-LLM firewall

This is the most important architectural rule in the codebase:

> **`app/ai/` and `app/llm/` never import each other.**
> A move is decided by `app/ai/` from `core/` state and nothing
> else. A chat line is generated by `app/llm/` from game state and
> personality, with no return path that could affect a move.

Both layers may **observe** the same `core` game state. Neither may call
the other. CI should enforce this with a simple import-graph lint.

## Network & LLM concerns

Until v1, the only network traffic the app makes is **outbound HTTPS to
the user-configured LLM endpoint**. Concretely:

- **Endpoint shape.** OpenAI-compatible Chat Completions only. The user
  provides base URL, API key, and model name. Defaults are blank — the
  feature is opt-in.
- **Storage.** Endpoint URL and model name are stored in clear in
  settings; the API key is stored using the platform's secure store
  where one is available (macOS Keychain, iOS Keychain) and falls back
  to a local file on Linux with a clear warning to the user.
- **Failure handling.** Any error (no key, 4xx, 5xx, timeout, parse
  failure, rate limit) is **silent** at the game-state level — the
  character simply does not speak. A single discreet indicator in
  settings shows the last error for debugging.
- **Cost & rate.** Calls are debounced and capped per deal. The user can
  set a per-deal max-call limit; the default is conservative.
- **Privacy.** No telemetry to any service we run. The LLM endpoint is
  whichever the user picked — they are aware of and consent to whatever
  data goes to it.

## Platform discipline

These rules apply across all platforms — present (macOS, Linux, iOS) and
post-v1 (Windows, Android). Following them keeps the post-v1 ports as
packaging-and-QA work rather than a Lua rewrite.

- **Input model.** Touch + mouse parity. Anything that works under touch
  on iOS works under mouse on desktop, and vice versa. Hit-targets are
  finger-sized (44 pt minimum on iOS, 48 dp minimum on Android).
- **Screen sizes.** Resizable window on desktop; portrait and landscape
  on iPhone and iPad. The table layout reflows — no pixel-pinned
  positions.
- **Filesystem.** `love.filesystem` exclusively. Never read or write
  absolute paths; iOS and Android sandboxes forbid it.
- **Save format.** JSON under `love.filesystem.getSaveDirectory()`,
  forward-compatible with a `schemaVersion` field from day one.
- **No platform-conditional code in `core/` or `app/`.** Anything
  platform-specific lives in `ui/` or `platform/`.
- **No vendor-locked APIs in shared code** — no GameCenter / StoreKit /
  Metal-only / Play Games. Shell-only.
- **Performance.** A table view is cheap; Love2D runs this comfortably
  even on the oldest supported iPhone. No profiler needed in v1.

## Out of scope of this document

Concrete data structures, the exact AI algorithm, animation internals,
build scripts and CI configuration are **not** decided here. When a
decision is needed, the engineer proposes it in the PR and the architect
signs off. We do not pre-design things we are not yet building.
