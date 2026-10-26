#!/usr/bin/env bash
#
# End-to-end tests for distribute-secret.yml and token-expiry.yml.
# Usage: test/e2e/secrets.sh        (ONLY="scenario ..." runs a subset)
#
# Scenarios are called by name through run_scenarios.
# shellcheck disable=SC2329

# shellcheck source=test/e2e/lib.sh
source "$(dirname "$0")/lib.sh"

secret_updated_since() {  # <repo> <iso time>
    local updated
    updated="$(gh secret list -R "$1" --json name,updatedAt -q '.[] | select(.name == "SYNC_TOKEN") | .updatedAt')"
    [ -n "$updated" ] && [[ "$updated" > "$2" ]]
}

open_expiry_issues() {
    gh issue list -R "$KIT" --state open --json title \
        -q '[.[] | select(.title | startswith("SYNC_TOKEN"))] | length'
}

distributes_to_one_repo() {
    local before
    before="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    dispatch "$KIT" distribute-secret.yml -f repo="$SANDBOX"
    check "run is green" run_ok
    check "SYNC_TOKEN updated on $SANDBOX" secret_updated_since "$SANDBOX" "$before"
}

refuses_other_owners() {
    dispatch "$KIT" distribute-secret.yml -f repo=octocat/Hello-World
    check "run fails" run_failed
}

refuses_malformed_target() {
    dispatch "$KIT" distribute-secret.yml -f repo='codedpalette/x; echo pwned'
    check "run fails" run_failed
}

expiry_issue_once() {
    dispatch "$KIT" token-expiry.yml -f warn-days=4000
    check "first run is green" run_ok
    check "one open expiry issue" test "$(open_expiry_issues)" = 1
    local number
    number="$(gh issue list -R "$KIT" --state open --json number,title \
        -q '.[] | select(.title | startswith("SYNC_TOKEN")) | .number')"
    check "issue assigned to the owner" test \
        "$(gh issue view "$number" -R "$KIT" --json assignees -q '.assignees[0].login')" = "${KIT%%/*}"
    dispatch "$KIT" token-expiry.yml -f warn-days=4000
    check "second run is green" run_ok
    check "still one open expiry issue" test "$(open_expiry_issues)" = 1
    check "second run commented" test \
        "$(gh issue view "$number" -R "$KIT" --json comments -q '.comments | length')" -ge 1
    gh issue close "$number" -R "$KIT" --comment "Closed by the end-to-end test." >/dev/null
}

no_issue_outside_window() {
    dispatch "$KIT" token-expiry.yml -f warn-days=0
    check "run is green" run_ok
    check "no open expiry issue" test "$(open_expiry_issues)" = 0
}

run_scenarios distributes_to_one_repo refuses_other_owners refuses_malformed_target \
    expiry_issue_once no_issue_outside_window
