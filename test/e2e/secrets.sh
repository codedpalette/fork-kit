#!/usr/bin/env bash
#
# End-to-end tests for distribute-secret.yml.
# Usage: test/e2e/secrets.sh        (ONLY="scenario ..." runs a subset)
#
# Scenarios are called by name through run_scenarios.
# shellcheck disable=SC2317,SC2329

# shellcheck source=test/e2e/lib.sh
source "$(dirname "$0")/lib.sh"

secret_updated_since() {  # <repo> <iso time>
    local updated
    updated="$(gh secret list -R "$1" --json name,updatedAt -q '.[] | select(.name == "SYNC_TOKEN") | .updatedAt')"
    [ -n "$updated" ] && [[ "$updated" > "$2" ]]
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

run_scenarios distributes_to_one_repo refuses_other_owners refuses_malformed_target
