---
sidebar_position: 2
title: Roadmap
---

# Roadmap

Phases are **strictly ordered** — each one depends on the previous ones
being stable. The [Task List](./task-list.md) breaks each phase into
actionable items.

## v1 phases

| # | Phase | What "done" looks like |
|---|---|---|
| 0 | **Project setup** | `love .` opens a window. CI green on macOS and Linux. Lint, formatter, test runner and **i18n plumbing** all in place. |
| 1 | **Core rules engine** | Pure-Lua rules pass a unit-test suite for a full standard 3-player Russian deal. Engine reads from `RuleConfig` from day one. |
| 2 | **Hot-seat MVP** | Three humans play a complete game to 1000 on one desktop. Functional UI; every UI string keyed via `t()`. |
| 3 | **Rule template system** | Built-in templates for Russian, Polish, Ukrainian, 2-player and 4-player. Players can clone, edit and save custom templates. |
| 4 | **UX & polish** | Animations, sounds, polished scoreboard, settings, interactive tutorial, multiple selectable card skins. |
| 5 | **iOS port — cross-platform prototype** 🎯 | The base game runs on **macOS, Linux and iOS** from one codebase. Hot-seat only; AI deferred. |
| 6 | **AI opponents (algorithmic)** | Single human vs. two algorithmic AI seats at one difficulty. Silent AI — no LLM yet. AI is legal under every built-in `RuleConfig`. |
| 7 | **AI characters & psychology** | Built-in and user-saved character presets. User-configured OpenAI-compatible LLM endpoint produces in-character chat. *Inviolable invariant: the algorithm picks every move; the LLM only writes dialogue.* |
| 8 | **Release readiness** | Russian, Polish and Ukrainian translations shipped. Save-game, crash reporting, store assets, signed builds for all three v1 targets. |

🎯 Phase 5 is the **product owner's prototype checkpoint**: confirm the
base game is real on every v1 target before any AI work starts.

## Post-v1 phases

These are confirmed targets; they're separated only because the team
currently has no Windows or Android devices to test on. The codebase
must stay platform-clean (see [Architecture](./architecture.md)) so they
remain packaging-and-QA work, not a Lua rewrite.

| # | Phase | What "done" looks like |
|---|---|---|
| 9 | **Windows desktop** | Same `.love` packaged as a signed `.exe` / installer; runs on Windows 10+ and tested on real hardware. |
| 10 | **Android** | Same Lua source packaged via love-android into a Play Store `.aab`; runs on Android 10+ phones and tablets. |
