#!/usr/bin/env bash
# CI heuristic: flag string literals in ui/ and app/ that look like
# player-visible text but are NOT routed through the i18n module.
#
# Scope:
#   - Scans every .lua under ui/ and app/.
#   - Skips app/i18n.lua (the module itself) and app/llm/* (LLM system
#     prompts are developer-authored, not player-visible).
#
# Heuristic — accepts both false negatives and false positives.
#   The check looks for double-quoted string literals containing at least
#   one whitespace character. Lines are skipped if they are comments, or
#   contain any of: t(, require(, error(, assert(, io.stderr or the
#   explicit "-- i18n-ok" pragma. (print( is intentionally NOT excluded
#   because love.graphics.print is the primary UI rendering call.)
#
# Fixing a false positive:
#   1. Route the literal through i18n.t("some.key") and add the key to
#      assets/i18n/en.lua, OR
#   2. If the literal is genuinely developer-facing (a log line, a debug
#      print, a programmer-error path), annotate the line with a trailing
#      `-- i18n-ok: <reason>` and the check will skip it.
#
# Phase 0 has no UI code yet, so this script currently emits a no-op
# pass; it starts gating real code from Phase 2 onward.

set -euo pipefail

files=$(
    find ui app -type f -name "*.lua" \
        -not -path "app/i18n.lua" \
        -not -path "app/llm/*" \
        2>/dev/null || true
)

if [ -z "$files" ]; then
    echo "check-i18n: no .lua files under ui/ or app/ to scan — pass."
    exit 0
fi

# Lines containing a double-quoted string literal with at least one space.
# `xargs` over the newline-separated find output works on bash 3.2 (macOS).
hits=$(
    printf '%s\n' "$files" | xargs grep -HnE '"[^"]*[[:space:]][^"]*"' 2>/dev/null || true
)

if [ -z "$hits" ]; then
    echo "check-i18n: no double-quoted whitespace literals found in ui/ or app/."
    exit 0
fi

# Filter out the developer-facing safe contexts. A line passes the gate
# if ANY of these tokens appears on it.
violations=$(
    echo "$hits" \
        | grep -vE '^[^:]*:[^:]*:[[:space:]]*--' \
        | grep -vE '\bt\(' \
        | grep -vE '\brequire\(' \
        | grep -vE '\berror\(' \
        | grep -vE '\bassert\(' \
        | grep -vE 'io\.stderr' \
        | grep -vE 'i18n-ok' \
        || true
)

if [ -n "$violations" ]; then
    echo "check-i18n: hard-coded UI strings detected — route through i18n.t() or annotate '-- i18n-ok: <reason>'."
    echo "$violations"
    exit 1
fi

echo "check-i18n: no hard-coded UI strings."
exit 0
