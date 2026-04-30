# Project make targets for Thousand. All targets assume luacheck, stylua and
# busted are on PATH — install via your platform's package manager (e.g.
# `brew install luacheck stylua` on macOS, plus `luarocks install busted`).

.PHONY: help test lint format format-check check clean run package install-hooks

LOVE_FILE := thousand.love

help:
	@echo "Targets:"
	@echo "  test          run the busted test suite"
	@echo "  lint          run luacheck across the project"
	@echo "  format        rewrite all .lua files with stylua"
	@echo "  format-check  fail if any .lua file would be reformatted"
	@echo "  check         lint + format-check + test (CI parity)"
	@echo "  run           launch the game with love ."
	@echo "  package       build $(LOVE_FILE) for distribution"
	@echo "  install-hooks point git at .githooks/ so pre-commit runs check"
	@echo "  clean         remove generated artifacts"

test:
	busted

lint:
	luacheck .

format:
	stylua .

format-check:
	stylua --check .

check: lint format-check test

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
		-x 'stylua.toml' \
		-x '.gitignore' \
		-x '.mcp.json' \
		-x 'README.md' \
		-x '$(LOVE_FILE)'

# Wire git up to use the repo's pre-commit hook. Idempotent — re-running
# is a no-op. Removes the wiring with `git config --unset core.hooksPath`.
install-hooks:
	git config core.hooksPath .githooks
	@echo "Git hooks installed: .githooks/pre-commit will run on every commit."

clean:
	rm -f *.love
