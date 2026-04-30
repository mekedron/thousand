# Project make targets for Thousand. All targets assume luacheck, stylua and
# busted are on PATH — install via your platform's package manager (e.g.
# `brew install luacheck stylua` on macOS, plus `luarocks install busted`).

.PHONY: help test coverage lint format format-check check clean run package install-hooks check-i18n

LOVE_FILE := thousand.love

help:
	@echo "Targets:"
	@echo "  test          run the busted test suite"
	@echo "  coverage      run busted under luacov; gate core/ at 80% (skips if luacov absent)"
	@echo "  lint          run luacheck across the project"
	@echo "  format        rewrite all .lua files with stylua"
	@echo "  format-check  fail if any .lua file would be reformatted"
	@echo "  check         lint + format-check + check-i18n + test (CI parity)"
	@echo "  check-i18n    flag hard-coded UI strings outside locale tables"
	@echo "  run           launch the game with love ."
	@echo "  package       build $(LOVE_FILE) for distribution"
	@echo "  install-hooks point git at .githooks/ so pre-commit runs check"
	@echo "  clean         remove generated artifacts"

test:
	busted

# Coverage gate. Runs the busted suite under luacov, renders the
# report, then asserts core/ line coverage is at or above 80% via
# tools/coverage_gate.lua. Skips gracefully when luacov is not on
# PATH so devs without it can still run `make coverage` and get a
# clear hint instead of an opaque rocks error. The hard gate lives
# in CI (.github/workflows/ci.yml).
coverage:
	@if ! command -v busted >/dev/null 2>&1; then \
	  echo "make coverage: busted not on PATH — install with 'luarocks install busted'."; \
	  exit 1; \
	fi
	@if ! command -v luacov >/dev/null 2>&1; then \
	  echo "make coverage: luacov not on PATH — install with 'luarocks install luacov'"; \
	  echo "               (skipped, exit 0; CI enforces the gate)."; \
	  exit 0; \
	fi
	rm -f luacov.stats.out luacov.report.out
	busted --coverage
	luacov
	lua tools/coverage_gate.lua luacov.report.out 80

lint:
	luacheck .

format:
	stylua .

format-check:
	stylua --check .

check: lint format-check check-i18n test

check-i18n:
	./tools/check_i18n.sh

run:
	love .

# Build a .love archive ready to drop into love-ios / love-android or
# distribute on desktop. Excludes everything that should not ship in
# the runtime: docs, the documentation site, tests, tooling configs,
# the .git tree and any local third-party clones.
package:
	rm -f $(LOVE_FILE)
	zip -r $(LOVE_FILE) . \
		-x '.git/*' \
		-x '.github/*' \
		-x '.githooks/*' \
		-x 'docs/*' \
		-x 'docs-site/*' \
		-x 'love2d-mcp/*' \
		-x '.luarocks/*' \
		-x 'tests/*' \
		-x 'platform/*' \
		-x 'Makefile' \
		-x '.luacheckrc' \
		-x '.busted' \
		-x '.luacov' \
		-x 'stylua.toml' \
		-x '.gitignore' \
		-x '.mcp.json' \
		-x 'README.md' \
		-x 'luacov.stats.out' \
		-x 'luacov.report.out' \
		-x 'tools/*' \
		-x '$(LOVE_FILE)'

# Wire git up to use the repo's pre-commit hook. Idempotent — re-running
# is a no-op. Removes the wiring with `git config --unset core.hooksPath`.
install-hooks:
	git config core.hooksPath .githooks
	@echo "Git hooks installed: .githooks/pre-commit will run on every commit."

clean:
	rm -f *.love
