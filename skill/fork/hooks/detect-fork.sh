#!/usr/bin/env bash
#
# SessionStart hook: tell the agent to load the fork skill when the session's
# repository is a fork managed by fork-kit.
#
# The trunk is the fork's default branch, so origin/HEAD points at it. Reading
# fork.yml from there, not from the working tree, also catches feat/* branches,
# which are cut from the mirror and never contain the fork's own files.
#
# Never fetches, never fails: outside a fork it prints nothing and exits 0.

git show origin/HEAD:.github/fork.yml >/dev/null 2>&1 || exit 0

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"This repository is a fork managed by the fork skill: .github/fork.yml is on origin/HEAD. Load the fork skill before you work here."}}
JSON
