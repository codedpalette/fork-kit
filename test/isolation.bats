# Static checks for the security layout of sync.yml and release.yml (see their
# header comments).
# Each invariant is tested on the real file, and on a copy broken on purpose
# to prove that the check notices.

load helpers

CHECK="$BATS_TEST_DIRNAME/check-isolation"
SYNC="$BATS_TEST_DIRNAME/../.github/workflows/sync.yml"
RELEASE="$BATS_TEST_DIRNAME/../.github/workflows/release.yml"

setup() { cp "$SYNC" "$BATS_TEST_TMPDIR/sync.yml"; COPY="$BATS_TEST_TMPDIR/sync.yml"; }

@test "sync.yml keeps SYNC_TOKEN away from upstream code" {
    run "$CHECK" "$SYNC" merge push fork-sync
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "release.yml keeps write access away from upstream code" {
    run "$CHECK" "$RELEASE" build publish fork-sync
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "notices write permissions on the release build job" {
    cp "$RELEASE" "$COPY"
    yq -i '.jobs.build.permissions.contents = "write"' "$COPY"
    run "$CHECK" "$COPY" build publish
    [ "$status" -eq 1 ]
}

@test "notices the build command running in the publish job" {
    cp "$RELEASE" "$COPY"
    yq -i '.jobs.publish.steps += [{"name": "Build", "run": "bash -c \"$BUILD\""}]' "$COPY"
    run "$CHECK" "$COPY" build publish
    [ "$status" -eq 1 ]
}

@test "notices SYNC_TOKEN in the merge job" {
    yq -i '.jobs.merge.steps[0].with.token = "${{ secrets.SYNC_TOKEN }}"' "$COPY"
    run "$CHECK" "$COPY" merge push fork-sync
    [ "$status" -eq 1 ]
    [[ "$output" == *"SYNC_TOKEN"* ]]
}

@test "notices a merge checkout that keeps credentials" {
    yq -i 'del(.jobs.merge.steps[0].with.persist-credentials)' "$COPY"
    run "$CHECK" "$COPY" merge push fork-sync
    [ "$status" -eq 1 ]
    [[ "$output" == *"persist-credentials"* ]]
}

@test "notices write permissions on the merge job" {
    yq -i '.jobs.merge.permissions.contents = "write"' "$COPY"
    run "$CHECK" "$COPY" merge push fork-sync
    [ "$status" -eq 1 ]
}

@test "notices the verify command running in the push job" {
    yq -i '.jobs.push.steps += [{"name": "Verify", "run": "bash -euo pipefail -c \"$VERIFY\""}]' "$COPY"
    run "$CHECK" "$COPY" merge push fork-sync
    [ "$status" -eq 1 ]
}

@test "notices a package manager in the push job" {
    yq -i '.jobs.push.steps += [{"name": "Install", "run": "npm ci"}]' "$COPY"
    run "$CHECK" "$COPY" merge push fork-sync
    [ "$status" -eq 1 ]
}

@test "notices a third-party action in the push job" {
    yq -i '.jobs.push.steps += [{"uses": "actions/setup-node@v4"}]' "$COPY"
    run "$CHECK" "$COPY" merge push fork-sync
    [ "$status" -eq 1 ]
}

@test "notices a third job that gets SYNC_TOKEN" {
    yq -i '.jobs.extra = {"runs-on": "ubuntu-latest", "steps": [{"run": "echo ${{ secrets.SYNC_TOKEN }}"}]}' "$COPY"
    run "$CHECK" "$COPY" merge push fork-sync
    [ "$status" -eq 1 ]
}

# The breakages the security review found, each of which the old check missed.

@test "notices secrets in bracket syntax in the merge job" {
    yq -i '.jobs.merge.steps[0].with.token = "${{ secrets[\"SYNC_TOKEN\"] }}"' "$COPY"
    run "$CHECK" "$COPY" merge push fork-sync
    [ "$status" -eq 1 ]
}

@test "notices a new job that calls another workflow with secrets: inherit" {
    yq -i '.jobs.extra = {"uses": "other/repo/.github/workflows/x.yml@v1", "secrets": "inherit"}' "$COPY"
    run "$CHECK" "$COPY" merge push fork-sync
    [ "$status" -eq 1 ]
}

@test "notices permissions: write-all on the merge job" {
    yq -i '.jobs.merge.permissions = "write-all"' "$COPY"
    run "$CHECK" "$COPY" merge push fork-sync
    [ "$status" -eq 1 ]
}

@test "notices a custom shell in the push job" {
    yq -i '.jobs.push.steps += [{"name": "Node", "shell": "node {0}", "run": "console.log(1)"}]' "$COPY"
    run "$CHECK" "$COPY" merge push fork-sync
    [ "$status" -eq 1 ]
}

@test "notices a heredoc fed to a shell in the push job" {
    yq -i '.jobs.push.steps += [{"name": "Heredoc", "run": "bash <<EOF\nnpm ci\nEOF"}]' "$COPY"
    run "$CHECK" "$COPY" merge push fork-sync
    [ "$status" -eq 1 ]
}

@test "notices the verify command run through env in the push job" {
    yq -i '.jobs.push.steps += [{"name": "Env", "env": {"VERIFY": "x"}, "run": "env $VERIFY"}]' "$COPY"
    run "$CHECK" "$COPY" merge push fork-sync
    [ "$status" -eq 1 ]
}

@test "a here-string does not hide the lines after it" {
    yq -i '.jobs.push.steps += [{"name": "Herestring", "run": "cat <<<y\nnpm ci"}]' "$COPY"
    run "$CHECK" "$COPY" merge push fork-sync
    [ "$status" -eq 1 ]
}

@test "notices a container on the push job" {
    yq -i '.jobs.push.container = "node:22"' "$COPY"
    run "$CHECK" "$COPY" merge push fork-sync
    [ "$status" -eq 1 ]
}

@test "notices github.token in a merge-job step after the verify step" {
    yq -i '.jobs.merge.steps += [{"name": "Late", "env": {"GH_TOKEN": "${{ github.token }}"}, "run": "gh api user"}]' "$COPY"
    run "$CHECK" "$COPY" merge push fork-sync
    [ "$status" -eq 1 ]
}

@test "notices a push job that leaves its environment" {
    yq -i 'del(.jobs.push.environment)' "$COPY"
    run "$CHECK" "$COPY" merge push fork-sync
    [ "$status" -eq 1 ]
}


@test "check.yml holds no secrets and no write access" {
    check="$BATS_TEST_DIRNAME/../.github/workflows/check.yml"
    ! grep -Eq '(^|[^A-Za-z_])secrets([^A-Za-z_]|$)|github\.token' "$check"
    [ "$(yq '[.jobs[].permissions | to_entries[] | .value] | all_c(. == "read" or . == "none")' "$check")" = true ]
    [ "$(yq '[.jobs[].steps[] | select(.uses // "" | test("^actions/checkout@")) | .with["persist-credentials"]] | all_c(. == false)' "$check")" = true ]
}

# The templates hold {{...}} placeholders, so render them before yq reads them.
render() { sed -e 's/{{[a-z_]*}}/x/g' -e 's/[[:space:]]*# tip:remove$//' "$BATS_TEST_DIRNAME/../skills/fork/templates/$1"; }

@test "a release after a sync builds the commit that the sync pushed" {
    [ "$(render fork-sync.yml | yq '.jobs.release.with.ref')" = '${{ needs.sync.outputs.sha }}' ]
    [ "$(yq '.on.workflow_call.outputs.sha.value' "$SYNC")" = '${{ jobs.push.outputs.sha }}' ]
    [ "$(yq '.jobs.build.steps[0].with.ref' "$RELEASE")" = '${{ inputs.ref }}' ]
    grep -qF 'echo "sha=$(git rev-parse HEAD)" >>"$GITHUB_OUTPUT"' "$SYNC"
}

@test "both release callers share one concurrency group" {
    [ "$(render fork-release.yml | yq '.concurrency.group')" = fork-release ]
    [ "$(render fork-sync.yml | yq '.jobs.release.concurrency.group')" = fork-release ]
}
