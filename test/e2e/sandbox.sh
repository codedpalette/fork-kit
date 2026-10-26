#!/usr/bin/env bash
#
# Build or reset the sandbox pair used by the end-to-end tests:
#
#   codedpalette/forker-demo-upstream   plays upstream: a tiny Node project with releases
#   codedpalette/forker-demo            plays the fork: mirror `main`, trunk `patched`
#
#   test/e2e/sandbox.sh setup   create both repositories (once)
#   test/e2e/sandbox.sh reset   put both back to the baseline before a scenario
#
# Baseline: upstream has release v0.1.0 and `main` at it. The fork's `patched`
# equals its `e2e-baseline` branch: v0.1.0 plus one fork-only commit that edits
# line 1 of lib.js, plus the fork tooling.

# shellcheck source=test/e2e/lib.sh
source "$(dirname "$0")/lib.sh"

UPSTREAM="${UPSTREAM:-codedpalette/forker-demo-upstream}"
WORK="${TMPDIR:-/tmp}/forker-e2e"

# Clone (or refresh) a working copy and print its path.
workdir() {  # <repo> <dir name>
    local dir="$WORK/$2"
    if [ -d "$dir/.git" ]; then
        git -C "$dir" fetch -q --prune --tags --force origin
    else
        rm -rf "$dir"
        git clone -q "git@github.com:$1.git" "$dir"
    fi
    git -C "$dir" config user.name "fork-kit e2e"
    git -C "$dir" config user.email "e2e@users.noreply.github.com"
    printf '%s' "$dir"
}

setup_upstream() {
    gh repo view "$UPSTREAM" >/dev/null 2>&1 ||
        gh repo create "$UPSTREAM" --public --description "Sandbox upstream for fork-kit end-to-end tests" >/dev/null
    local dir="$WORK/upstream"
    rm -rf "$dir" && mkdir -p "$dir/.github/workflows" && cd "$dir" || exit 1
    git init -q -b main
    git config user.name "fork-kit e2e"
    git config user.email "e2e@users.noreply.github.com"
    cat >package.json <<'JSON'
{
  "name": "forker-demo",
  "version": "0.1.0",
  "scripts": { "test": "node test.js" }
}
JSON
    printf '%s\n' "export const greeting = 'hello';" "export const answer = 42;" >lib.js
    printf '%s\n' "import { answer } from './lib.js';" \
        "if (answer !== 42) { console.error('answer changed'); process.exit(1); }" \
        "console.log('tests pass');" >test.js
    jq '. + {type: "module"}' package.json >p.tmp && mv p.tmp package.json
    printf '%s\n' "name: noop" "on: workflow_dispatch" "jobs:" "  noop:" \
        "    runs-on: ubuntu-latest" "    steps:" "      - run: echo v1" >.github/workflows/noop.yml
    git add -A && git commit -q -m "feat: first version"
    git tag v0.1.0
    git remote add origin "git@github.com:$UPSTREAM.git"
    git push -q --force origin main v0.1.0
    gh release create v0.1.0 -R "$UPSTREAM" --title v0.1.0 --notes "First version" >/dev/null
}

setup_fork() {
    local dir
    dir="$(workdir "$SANDBOX" fork)"
    cd "$dir" || exit 1
    git remote remove upstream 2>/dev/null || true
    git remote add upstream "https://github.com/$UPSTREAM.git"
    git remote set-url --push upstream DISABLED
    git fetch -q upstream --tags
    git push -q --force origin upstream/main:refs/heads/main
    git switch -q -C patched v0.1.0
    sed -i '' "1s/.*/export const greeting = 'hello from the fork';/" lib.js
    git commit -q -am "fork: greet from the fork"
    mkdir -p .github/workflows
    cat >.github/fork.yml <<'YAML'
schema: 1
kit: main
kit-repo: codedpalette/fork-kit
upstream: codedpalette/forker-demo-upstream
mirror: main
trunk: patched
node: 22
sync:
  source: release
  npm-package: ''
  verify: npm test
release:
  suffix: patched
  build: 'true'
  version-file: package.json
  stamp:
    package.json: '.version = ($version | ltrimstr("v"))'
  assets: [package.json]
  commit: []
YAML
    cat >.github/workflows/fork-sync.yml <<'YAML'
name: Fork sync

on:
  workflow_dispatch:

concurrency: fork-sync

jobs:
  sync:
    uses: codedpalette/fork-kit/.github/workflows/sync.yml@main
    permissions:
      contents: read
      pull-requests: write
      issues: write
    secrets: inherit
YAML
    git add -A && git commit -q -m "chore: set up fork tooling"
    git push -q --force origin patched:refs/heads/patched patched:refs/heads/e2e-baseline
    gh repo edit "$SANDBOX" --default-branch patched >/dev/null
}

reset() {
    local dir
    # Upstream: only v0.1.0, and main at it.
    gh release list -R "$UPSTREAM" --json tagName -q '.[].tagName' | while read -r tag; do
        [ "$tag" = v0.1.0 ] || gh release delete "$tag" -R "$UPSTREAM" --yes --cleanup-tag >/dev/null
    done
    dir="$(workdir "$UPSTREAM" upstream)"
    git -C "$dir" ls-remote --tags --refs origin | sed 's|.*refs/tags/||' | while read -r tag; do
        [ "$tag" = v0.1.0 ] || git -C "$dir" push -q origin ":refs/tags/$tag"
    done
    git -C "$dir" push -q --force origin 'v0.1.0^{commit}:refs/heads/main'
    git -C "$dir" fetch -q --prune --prune-tags origin

    # Fork: no open PRs, no sync branches, trunk at the baseline, mirror at v0.1.0.
    gh pr list -R "$SANDBOX" --state open --json number -q '.[].number' | while read -r pr; do
        gh pr close "$pr" -R "$SANDBOX" >/dev/null
    done
    dir="$(workdir "$SANDBOX" fork)"
    git -C "$dir" ls-remote --heads origin 'sync/*' | sed 's|.*refs/heads/||' | while read -r branch; do
        git -C "$dir" push -q origin ":refs/heads/$branch"
    done
    git -C "$dir" ls-remote --tags --refs origin | sed 's|.*refs/tags/||' | while read -r tag; do
        git -C "$dir" push -q origin ":refs/tags/$tag"
    done
    gh release list -R "$SANDBOX" --json tagName -q '.[].tagName' | while read -r tag; do
        gh release delete "$tag" -R "$SANDBOX" --yes >/dev/null
    done
    git -C "$dir" push -q --force origin origin/e2e-baseline:refs/heads/patched
    git -C "$dir" fetch -q upstream 2>/dev/null || git -C "$dir" remote add upstream "https://github.com/$UPSTREAM.git"
    git -C "$dir" fetch -q --tags upstream
    git -C "$dir" push -q --force origin 'v0.1.0^{commit}:refs/heads/main'
}

case "${1:-}" in
    setup) mkdir -p "$WORK"; setup_upstream; setup_fork ;;
    reset) mkdir -p "$WORK"; reset ;;
    *) echo "usage: ${0##*/} setup|reset" >&2; exit 2 ;;
esac
