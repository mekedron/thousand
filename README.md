# Thousand

A faithful, beautiful, offline-first digital implementation of
**Thousand** — the trick-taking card game played across Russia, Poland,
Ukraine and the diaspora. Built on [LÖVE](https://love2d.org/) (Lua), v1
ships on macOS, Linux and iOS from a single codebase.

The full vision, rule reference, architecture and roadmap live in the
docs site:

- **Online**: [the project's GitHub Pages site](#).
- **Local sources**: [`docs/`](./docs).

## Run the game

```sh
love .
# or, equivalently
make run
```

LÖVE 11.x is required. Install from <https://love2d.org/#download>.

## Run the tests

The test runner is [busted](https://lunarmodules.github.io/busted/). The
engine is pure Lua and unit-tests run from the command line — no LÖVE
required.

```sh
make test
```

If `busted` is not on PATH, install it via LuaRocks:

```sh
luarocks install busted
```

## Coverage

The engine targets at least **80% line coverage** across `core/`, gated
in CI on every push. Run the report locally with:

```sh
make coverage
```

This re-runs the busted suite under
[luacov](https://lunarmodules.github.io/luacov/), parses
`luacov.report.out`, and exits non-zero if any `core/*.lua` file is
missing from the report or if total `core/` coverage is below 80%.

If `luacov` is not installed locally, `make coverage` prints an install
hint and exits cleanly — the hard gate lives in CI. Install via
LuaRocks:

```sh
luarocks install luacov
```

## Lint and format

```sh
make lint          # luacheck
make format        # rewrite all .lua with stylua
make format-check  # CI parity — fails if anything would be reformatted
make check         # lint + format-check + tests
```

Install the tools via your platform's package manager:

```sh
brew install luacheck stylua   # macOS
# or
sudo apt install luacheck      # Linux; stylua via cargo / GitHub releases
```

## Pre-commit hook (recommended)

Wire git up to run `make check` before every commit:

```sh
make install-hooks
```

This points `core.hooksPath` at [`.githooks/`](./.githooks). Skip with
`git commit --no-verify` if you really must — but the same checks run
in CI on every push, so a red main is just delayed, not avoided.

## Build a `.love` for distribution

```sh
make package
```

Produces `thousand.love` at the repo root. Drop it onto `love.exe`,
`love-ios`, or run it directly with `love thousand.love`.

## Project layout

```
core/      — pure-Lua rules engine (no love.*)
app/       — orchestration: AI, LLM, persistence, templates, i18n
ui/        — scenes, rendering, input
assets/    — i18n tables, fonts, sounds, card skins, avatars
platform/  — packaging shells per OS (macos, linux, ios)
tests/     — busted unit specs + e2e harness
docs/      — vision, architecture, roadmap, task list, rule reference
```

See [`docs/development/architecture.md`](./docs/development/architecture.md)
for what depends on what and the algorithm-vs-LLM firewall.

## License

MIT — see [`LICENSE`](./LICENSE).
