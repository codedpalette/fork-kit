# shellcheck shell=bash
# Shared helpers for the end-to-end tests. They run real workflows on GitHub,
# so they need `gh` logged in as the kit owner.

set -euo pipefail

KIT="${KIT:-codedpalette/fork-kit}"
SANDBOX="${SANDBOX:-codedpalette/forker-demo}"
FAILED=0

# dispatch <repo> <workflow> [-f key=value ...]
# Start a workflow_dispatch run, wait for it, and set RUN_ID and RUN_OK.
dispatch() {
    local repo="$1" workflow="$2"; shift 2
    local since
    since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    gh workflow run "$workflow" -R "$repo" "$@" >/dev/null
    RUN_ID=""
    for _ in $(seq 1 30); do
        RUN_ID="$(gh run list -R "$repo" --workflow "$workflow" --event workflow_dispatch \
            --created ">=$since" --limit 1 --json databaseId -q '.[0].databaseId // empty')"
        [ -n "$RUN_ID" ] && break
        sleep 2
    done
    [ -n "$RUN_ID" ] || { echo "no run of $workflow appeared in $repo" >&2; return 1; }
    if gh run watch "$RUN_ID" -R "$repo" --exit-status >/dev/null 2>&1; then RUN_OK=1; else RUN_OK=0; fi
}

# check <description> <command...>: record a pass or a failure, never exit.
check() {
    local what="$1"; shift
    if "$@"; then
        echo "  ok   $what"
    else
        echo "  FAIL $what"
        FAILED=1
    fi
}

run_ok() { [ "$RUN_OK" = 1 ]; }
run_failed() { [ "$RUN_OK" = 0 ]; }

# run_scenarios <function...>: run the named scenarios, or the ones given in $ONLY.
run_scenarios() {
    local scenario
    for scenario in ${ONLY:-$*}; do
        echo "$scenario"
        "$scenario"
    done
    exit "$FAILED"
}
