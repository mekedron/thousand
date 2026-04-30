---
sidebar_position: 0
title: Vision & Scope
---

# Development Plan

This section is the product brief for the digital implementation of
**Thousand**. The authoritative game rules are in
[Rules of Play](../rules/setup.md); this section is about *what we ship
and in what order*.

## Vision

> **A faithful, beautiful, offline-first digital Thousand for desktop
> and mobile that respects the game's regional traditions and is fun the
> very first time you open it.**

The product is **not** a generic online card platform. It is a focused,
opinionated implementation that:

- Treats **3-player Russian Thousand** as the canonical experience.
- Exposes every rule difference between variants as a **toggle in a
  unified rule template**. Russian, Polish, Ukrainian, 2-player and
  4-player ship as **built-in templates**; players can clone any of them
  and **save their own custom templates**.
- Plays well **offline against AI opponents**.
- Treats card play as **two layers**: a deterministic algorithm picks
  every move; an optional LLM-driven personality layer lets AI seats
  banter and bluff. Thousand is not just an algorithm; it is a
  psychology game.
- Looks and feels like a real card table — readable, tactile, animated —
  with **multiple selectable card skins**.
- Speaks **English, Russian, Polish and Ukrainian** out of the box;
  every UI string is i18n-keyed from the first commit.

## Target audience

| Persona | What they want |
|---|---|
| **The veteran** | Quick, accurate Thousand against credible AI. House-rule toggles. |
| **The diaspora player** | Plays the variant from their region the way grandma taught them. |
| **The newcomer** | A guided tutorial that explains bidding, marriages and the barrel. |
| **The two-player couple** | A short, intense head-to-head game on the sofa. |

## Goals (success criteria for v1)

The order is the **shipping order**: 1–3 land before 4–6.

1. A new player can finish a complete game to 1000 points within 25
   minutes of opening the app, with no manual reading.
2. The game runs and is distributable on **macOS**, **Linux** and **iOS**
   from a single source codebase. The cross-platform working prototype
   (hot-seat play on all three) lands before any AI work.
3. A full deal takes under 90 seconds of wall-clock time at a brisk
   pace. Every UI string is localisable.
4. The AI plays correct rule-bound Thousand (no revokes, no illegal
   bids) and at the highest difficulty wins ≥ 50 % of deals against an
   intermediate human.
5. With an LLM endpoint configured, AI characters produce in-character,
   in-context dialogue at least once per deal without ever influencing
   the actual move chosen by the algorithm.
6. The game is **fully playable with no LLM endpoint configured** — AI
   seats stay silent. No degraded-mode banners, no nags.

## Two-layer AI: algorithm vs. personality

The most important design rule in the codebase:

> **The algorithm picks every move. The LLM only writes dialogue.**

| Layer | Owns | Sees | Decides |
|---|---|---|---|
| **Algorithm** (Lua) | Bidding, talon pass, raise, marriage timing, card play | The full game state and the AI seat's hand | **Every move.** Always. |
| **Personality** (LLM) | Chat lines, reactions, bluffs, banter | Game state, the seat's hand (for convincing bluffs), recent chat | **Nothing the game cares about.** |

If the LLM is slow, unavailable, rate-limited, returns garbage, or is not
configured at all, the game continues uninterrupted — the character
simply stops talking.

## Hard constraints

- **Engine:** [Love2D](https://love2d.org/) (Lua).
- **v1 targets:** the same codebase must build and run on macOS, Linux
  and iOS.
- **Multi-language by default.** Every player-visible string is keyed
  via i18n from the first UI commit. English ships first; Russian,
  Polish and Ukrainian translations land in Phase 9 against the same
  keys.
- **No backend of our own.** The LLM endpoint is user-supplied and the
  API key lives only on the user's device.
- **Algorithm-vs-personality firewall.** The LLM client cannot return
  moves; nothing in the move-selection path may import it.

## Non-goals for v1

- Online multiplayer / matchmaking / accounts.
- Web builds.
- In-app purchases, ads, telemetry beyond crash reporting.
- A 6-player variant.
- Custom card-art skin store.

## Planned for after v1

Confirmed targets, deferred only because the team currently has no
hardware to test on:

- **Windows desktop** — same Lua source, packaged via Love2D's Windows
  runtime.
- **Android** — same Lua source, packaged via love-android.

The codebase must stay platform-clean so adding them is packaging and QA
work, not a Lua rewrite.

## Documents in this section

- [Architecture](./architecture.md) — high-level shape of the codebase.
- [Roadmap](./roadmap.md) — phase order from prototype through release.
- [Task List](./task-list.md) — the living checklist; tick items off as
  you go.

:::tip[One source of truth]
If the code disagrees with the rules documentation, **the documentation
wins** — fix the code. If the rules documentation is wrong, fix the docs
first in a separate change, then update the code.
:::
