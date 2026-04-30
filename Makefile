# Project make targets for Thousand. All targets assume luacheck, stylua and
# busted are on PATH — install via your platform's package manager (e.g.
# `brew install luacheck stylua` on macOS, plus `luarocks install busted`).

.PHONY: help test lint format format-check check clean run

help:
	@echo "Targets:"
	@echo "  test          run the busted test suite"
	@echo "  lint          run luacheck across the project"
	@echo "  format        rewrite all .lua files with stylua"
	@echo "  format-check  fail if any .lua file would be reformatted"
	@echo "  check         lint + format-check + test (CI parity)"
	@echo "  run           launch the game with love ."
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

clean:
	rm -f *.love
