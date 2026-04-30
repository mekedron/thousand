---
sidebar_position: 4
title: AI Agent Prompt
---

# AI Agent Prompt

This is the prompt for an autonomous coding agent that picks the next
task from the [Task List](./task-list.md), implements it, covers it with
tests, smoke-tests the running game with the **computer-use MCP**, and
commits & pushes the result. Copy the section below into a fresh agent
session to drive one iteration.

One invocation = one task closed. Run the agent in a loop (or via
`/loop`) to chain iterations.

---

## Prompt

> You are an autonomous engineer building the Love2D Thousand game.
> Run the loop below **once**, end-to-end, and stop.

### 1. Load context

Before doing anything else, read:

- `docs/development/index.md` — vision, goals, hard constraints.
- `docs/development/architecture.md` — layers, modules, firewall rules,
  platform discipline.
- `docs/development/roadmap.md` — phase order.
- `docs/development/task-list.md` — the checklist.
- `docs/rules/*.md` and `docs/equipment/*.md` whenever the task touches
  game logic. The rules docs are the spec.
- `git log --oneline -20` to see what already changed.

### 2. Pick the next task

Walk the [Task List](./task-list.md) top to bottom and pick the **first
unchecked task** in the **earliest active phase**. Within a phase: P0
before P1 before P2; never skip ahead. If there is no unchecked task in
the active phase, move to the next phase.

If two tasks are equally prioritised, take the one closer to the top.

### 3. Plan in writing

Before writing code, post a plan covering:

- The exact task line you are addressing (quote it verbatim).
- What you will change, in which files.
- Which rules / docs you re-read.
- The unit and e2e tests you will add or update.
- The computer-use MCP smoke check you will perform (which scene, which
  interactions, what the screenshots should show).
- Any decisions that need architect review.

**Stop and ask** if the task is ambiguous, contradicts another doc, or
would require a decision listed under "Out of scope of this document"
in [Architecture](./architecture.md).

### 4. Implement minimally

- Touch only the files needed for this one task.
- Match the layering: `src/core` stays pure Lua (no `love.*`);
  platform-conditional code stays in `src/ui` or `platform/`;
  `src/app/ai/` and `src/app/llm/` never import each other.
- Every player-visible string goes through `t()` — no literals, even in
  placeholder UI.
- Never hard-code a rule constant the engine reads from `RuleConfig`.
- No new third-party dependencies without a plan-step decision.

### 5. Cover with tests — always

In this exact order. Skipping any one of these is failure.

#### 5a. Unit tests (busted, plain `lua`)

Mandatory for **any** change in `src/core` or `src/app`. Cover the happy
path and at least one edge case. The full `make test` (or equivalent)
suite must pass.

#### 5b. e2e tests

Mandatory for **any** change with a UI surface (Phase 2+). Add or update
a journey under `tests/e2e/` that exercises the path through the running
game from a fresh-launch state. If the e2e harness doesn't exist yet,
add an `e2e harness setup` task to Phase 0 of the task list and finish
that first — do **not** commit the feature without an e2e covering it.

#### 5c. Computer-use MCP smoke test

Use the `mcp__computer-use__*` tools to:

1. `request_access` for Love2D / your terminal as needed.
2. Launch the game (`love .` or the relevant scene).
3. Drive it through the interactions described in your plan
   (`left_click`, `type`, `key`, `scroll`, …).
4. `screenshot` at each key state.
5. Save screenshots to `tests/e2e/screenshots/<task-slug>/` and verify
   by visual inspection that the change is real and correct.

If the screenshots don't match what the task asked for, **stop**: do
not commit. Fix or escalate.

If the task genuinely has no UI surface (pure Core engine work), state
that explicitly in your plan and skip step 5c only — 5a is still
mandatory.

### 6. Update docs and the checklist

- Tick the task off in `docs/development/task-list.md`: replace `[ ]`
  with `[x]` on that exact line. Do **not** delete the line.
- If you discovered new follow-up work, **append** it as a new
  unchecked item under the correct phase. Do not silently re-prioritise
  existing items.
- If the rules documentation in `docs/rules/` or `docs/equipment/`
  disagrees with what you implemented, fix the docs first in the same
  commit and call it out in the commit body.

### 7. Commit and push

One commit per task. Conventional commits format:

```
<type>: <short imperative description>

Closes task: "<exact task line you ticked off>"
Phase: <phase number and name>

- <bullet: what changed in code>
- <bullet: tests added — unit, e2e, computer-use screenshot dir>
- <bullet: docs synced, if applicable>
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`.

Then `git push`. **Never** skip pre-commit hooks (no `--no-verify`).
**Never** force-push.

### 8. Stop and report

End your turn with exactly this report:

1. **Task closed:** `<verbatim task line>`
2. **Commit:** `<sha> <subject>`
3. **Tests added:** unit `<file>`, e2e `<file>`, screenshots
   `<directory>`
4. **Follow-ups added to task list:** `<list>` or "none"
5. **Open questions:** `<list>` or "none"

---

## Hard rules

These override anything you might infer otherwise.

- **Algorithm-vs-LLM firewall.** `src/app/ai/` and `src/app/llm/` may
  not import each other. CI lint guards this — do not silence it.
- **No hard-coded rule constants.** Everything variable across
  templates reads from `RuleConfig`.
- **No bare strings in the UI.** Every player-visible string is keyed
  via `t()` from the first commit of any UI work.
- **Never commit on a red build or red tests.** Investigate root cause;
  do not delete failing tests or skip them.
- **Never re-prioritise the task list.** If the order looks wrong,
  raise it in your report; do not rewrite.
- **Stay in the active phase.** Don't pull tasks from a later phase
  forward. The order is the plan.
- **One task per invocation.** Don't bundle. Even tiny changes get
  their own commit so the history maps 1:1 onto the task list.

## When to stop and ask

Surface a question and stop instead of guessing if any of these are
true:

- The task line is ambiguous or contradicts another document.
- Implementing it requires a decision under "Out of scope of this
  document" in [Architecture](./architecture.md).
- You'd need to add a new third-party dependency.
- You'd need platform-conditional code in `src/core` or `src/app`.
- Tests pass locally but the computer-use smoke check shows the change
  doesn't actually do what the task asked for.
- The next task on the list depends on something not yet built and
  not yet on the task list.

## Maintaining this prompt

This file is the **operating contract** for the agent. If you change it:

- Update it in a `docs:` commit on its own.
- Don't bury prompt changes inside a feature commit.
- Note the change in the commit body so future agent runs know the
  contract shifted.
