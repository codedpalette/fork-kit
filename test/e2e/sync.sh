#!/usr/bin/env bash
#
# End-to-end tests for sync.yml, run on the sandbox pair (see sandbox.sh).
# Each scenario resets the sandbox, changes upstream, dispatches the fork's
# sync, and checks the result on GitHub.
# Usage: test/e2e/sync.sh        (ONLY="scenario ..." runs a subset)
#
# Scenarios are called by name through run_scenarios.
# shellcheck disable=SC2317,SC2329

# shellcheck source=test/e2e/lib.sh
source "$(dirname "$0")/lib.sh"

HERE="$(cd "$(dirname "$0")" && pwd)"
UPSTREAM="${UPSTREAM:-codedpalette/forker-demo-upstream}"
WORK="${TMPDIR:-/tmp}/forker-e2e"

reset_sandbox() { "$HERE/sandbox.sh" reset; }

# Commit an upstream change on main. With a tag, also publish it as a release.
# upstream_change <message> <tag or ""> <shell snippet run in the clone>
upstream_change() {
    local dir="$WORK/upstream"
    git -C "$dir" fetch -q origin
    git -C "$dir" switch -q -C main origin/main
    (cd "$dir" && eval "$3")
    git -C "$dir" add -A
    git -C "$dir" commit -q -m "$1"
    git -C "$dir" push -q origin main
    if [ -n "$2" ]; then
        git -C "$dir" tag "$2"
        git -C "$dir" push -q origin "$2"
        gh release create "$2" -R "$UPSTREAM" --title "$2" --notes "$1" >/dev/null
    fi
    UPSTREAM_SHA="$(git -C "$dir" rev-parse HEAD)"
}

branch_sha() { gh api "repos/$1/branches/$2" -q .commit.sha; }
trunk_sha() { branch_sha "$SANDBOX" patched; }
trunk_contains() {  # <sha>
    local status
    status="$(gh api "repos/$SANDBOX/compare/$1...patched" -q .status 2>/dev/null || true)"
    [ "$status" = ahead ] || [ "$status" = identical ]
}
lacks() { ! grep -qi -- "$1" <<<"$2"; }  # <pattern> <text>
mirror_matches_upstream() { [ "$(branch_sha "$SANDBOX" main)" = "$(branch_sha "$UPSTREAM" main)" ]; }
sync_prs() {  # <ref>: number of open PRs from sync/<ref>
    gh pr list -R "$SANDBOX" --state open --head "sync/$1" --json number -q 'length'
}
sync_pr_assignee() {  # <ref>
    gh pr list -R "$SANDBOX" --state open --head "sync/$1" --json assignees -q '.[0].assignees[0].login'
}

no_new_release() {
    reset_sandbox
    local before
    before="$(trunk_sha)"
    upstream_change "docs: unreleased note" "" "echo 'unreleased' >NOTES.md"
    dispatch "$SANDBOX" fork-sync.yml
    check "run is green" run_ok
    check "trunk unchanged" test "$(trunk_sha)" = "$before"
    check "mirror equals upstream main" mirror_matches_upstream
}

release_touching_workflows() {
    reset_sandbox
    upstream_change "ci: change the noop workflow" v0.2.0 \
        "sed -i '' 's/echo v1/echo v2/' .github/workflows/noop.yml"
    dispatch "$SANDBOX" fork-sync.yml
    check "run is green" run_ok
    check "trunk contains v0.2.0" trunk_contains "$UPSTREAM_SHA"
}

conflict_parks_pr() {
    reset_sandbox
    local before
    before="$(trunk_sha)"
    upstream_change "feat: louder greeting" v0.3.0 \
        "sed -i '' \"1s/.*/export const greeting = 'HELLO';/\" lib.js"
    dispatch "$SANDBOX" fork-sync.yml
    check "run is green" run_ok
    check "trunk unchanged" test "$(trunk_sha)" = "$before"
    check "one sync PR" test "$(sync_prs v0.3.0)" = 1
    check "PR assigned to the owner" test "$(sync_pr_assignee v0.3.0)" = "${SANDBOX%%/*}"
    dispatch "$SANDBOX" fork-sync.yml
    check "second run is green" run_ok
    check "still one sync PR" test "$(sync_prs v0.3.0)" = 1
}

verify_failure() {
    reset_sandbox
    local before
    before="$(trunk_sha)"
    upstream_change "feat: new answer" v0.4.0 \
        "sed -i '' '2s/42/43/' lib.js"
    dispatch "$SANDBOX" fork-sync.yml
    check "run fails" run_failed
    check "trunk unchanged" test "$(trunk_sha)" = "$before"
}

# Upstream's test prints everything a malicious dependency could read, in
# base64 so that GitHub's log masking cannot hide a leaked token.
token_isolation() {
    reset_sandbox
    upstream_change "test: dump the environment" v0.4.1 "cat >>test.js <<'JS'
import { execSync } from 'node:child_process';
const dump = execSync('env; cat .git/config; cat \"\$GITHUB_ENV\" \"\$GITHUB_OUTPUT\" 2>/dev/null; true', { shell: '/bin/bash' });
console.log('DUMP:' + dump.toString('base64'));
JS"
    dispatch "$SANDBOX" fork-sync.yml
    check "run is green" run_ok
    local dump
    dump="$(gh run view "$RUN_ID" -R "$SANDBOX" --log | grep -o 'DUMP:[A-Za-z0-9+/=]*' | head -n 1 | cut -c6- | base64 -d)"
    check "the dump was captured" test -n "$dump"
    check "no personal access token" lacks github_pat_ "$dump"
    check "no GitHub Actions token" lacks ghs_ "$dump"
    check "no git credential header" lacks extraheader "$dump"
}

tip_source() {
    reset_sandbox
    local dir="$WORK/fork"
    git -C "$dir" fetch -q origin
    git -C "$dir" switch -q -C patched origin/patched
    sed -i '' 's/source: release/source: tip/' "$dir/.github/fork.yml"
    git -C "$dir" commit -q -am "chore: follow the upstream tip"
    git -C "$dir" push -q origin patched
    upstream_change "feat: unreleased work" "" "echo 'tip' >TIP.md"
    dispatch "$SANDBOX" fork-sync.yml
    check "run is green" run_ok
    check "trunk contains the upstream tip" trunk_contains "$UPSTREAM_SHA"
}

run_scenarios no_new_release release_touching_workflows conflict_parks_pr \
    verify_failure token_isolation tip_source
