#!/usr/bin/env bash
#
# SessionStart hook: tell the agent to load the fork skill when the session's
# repository is a fork managed by fork-kit.
#
# The trunk is the fork's default branch, so origin/HEAD normally points at it.
# Reading fork.yml from there, not from the working tree, also catches feat/*
# branches, which are cut from the mirror and never contain the fork's files.
# A clone made before the fork's default branch changed keeps a stale
# origin/HEAD, so every remote branch is checked, origin/HEAD among them.
#
# Never fetches, never fails: outside a fork it prints nothing and exits 0.

# One git process for all branches: a repository can have thousands.
git for-each-ref --format='%(refname):.github/fork.yml' refs/remotes/origin 2>/dev/null |
    git cat-file --batch-check 2>/dev/null |
    grep -q ' blob ' || exit 0

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"This repository is a fork managed by the fork-kit plugin: .github/fork.yml is on one of its remote branches. Load the fork-kit:fork skill before you work here."}}
JSON
