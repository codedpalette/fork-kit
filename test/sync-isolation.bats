# Static checks for the security layout of sync.yml (see its header comment).
# Each invariant is tested on the real file, and on a copy broken on purpose
# to prove that the check notices.

load helpers

CHECK="$BATS_TEST_DIRNAME/check-sync-isolation"
SYNC="$BATS_TEST_DIRNAME/../.github/workflows/sync.yml"

setup() { cp "$SYNC" "$BATS_TEST_TMPDIR/sync.yml"; COPY="$BATS_TEST_TMPDIR/sync.yml"; }

@test "sync.yml keeps SYNC_TOKEN away from upstream code" {
    run "$CHECK" "$SYNC"
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "notices SYNC_TOKEN in the merge job" {
    yq -i '.jobs.merge.steps[0].with.token = "${{ secrets.SYNC_TOKEN }}"' "$COPY"
    run "$CHECK" "$COPY"
    [ "$status" -eq 1 ]
    [[ "$output" == *"SYNC_TOKEN"* ]]
}

@test "notices a merge checkout that keeps credentials" {
    yq -i 'del(.jobs.merge.steps[0].with.persist-credentials)' "$COPY"
    run "$CHECK" "$COPY"
    [ "$status" -eq 1 ]
    [[ "$output" == *"persist-credentials"* ]]
}

@test "notices write permissions on the merge job" {
    yq -i '.jobs.merge.permissions.contents = "write"' "$COPY"
    run "$CHECK" "$COPY"
    [ "$status" -eq 1 ]
}

@test "notices the verify command running in the push job" {
    yq -i '.jobs.push.steps += [{"name": "Verify", "run": "bash -euo pipefail -c \"$VERIFY\""}]' "$COPY"
    run "$CHECK" "$COPY"
    [ "$status" -eq 1 ]
}

@test "notices a package manager in the push job" {
    yq -i '.jobs.push.steps += [{"name": "Install", "run": "npm ci"}]' "$COPY"
    run "$CHECK" "$COPY"
    [ "$status" -eq 1 ]
}

@test "notices a third-party action in the push job" {
    yq -i '.jobs.push.steps += [{"uses": "actions/setup-node@v4"}]' "$COPY"
    run "$CHECK" "$COPY"
    [ "$status" -eq 1 ]
}

@test "notices a third job that gets SYNC_TOKEN" {
    yq -i '.jobs.extra = {"runs-on": "ubuntu-latest", "steps": [{"run": "echo ${{ secrets.SYNC_TOKEN }}"}]}' "$COPY"
    run "$CHECK" "$COPY"
    [ "$status" -eq 1 ]
}
