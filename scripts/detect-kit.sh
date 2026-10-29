#!/usr/bin/env bash
#
# SessionStart hook: tell the agent to load the kit-audit skill when the
# session's repository is the kit itself. The kit is the plugin named fork-kit
# that holds the reusable sync workflow.
#
# Never fetches, never fails: outside the kit it prints nothing and exits 0.

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -f "$root/.github/workflows/sync.yml" ] || exit 0
grep -q '"name": *"fork-kit"' "$root/.claude-plugin/plugin.json" 2>/dev/null || exit 0

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"This repository is the fork-kit itself: its main reaches every fork and every machine. Load the fork-kit:kit-audit skill before you plan a change here, and again before you open or merge a PR."}}
JSON
