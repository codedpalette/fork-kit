# The "Find the kit" step turns fork.yml's kit value into a ref that only a
# tag or a commit can match. These tests run the step's own script.

load helpers

WORKFLOWS="$BATS_TEST_DIRNAME/../.github/workflows"

find_kit_script() {  # <workflow> <job>
    yq -r ".jobs.$2.steps[] | select(.name == \"Find the kit\") | .run" "$WORKFLOWS/$1"
}

run_find_kit() {  # <kit value>
    mkdir -p .github
    printf 'kit-repo: owner/fork-kit\nkit: %s\n' "$1" >.github/fork.yml
    GITHUB_OUTPUT="$BATS_TEST_TMPDIR/out"
    : >"$GITHUB_OUTPUT"
    export GITHUB_OUTPUT
    run bash -e -c "$(find_kit_script sync.yml merge)"
}

setup() { make_repo; }

@test "every Find the kit step is the same script" {
    first="$(find_kit_script sync.yml merge)"
    [ -n "$first" ]
    [ "$(find_kit_script sync.yml push)" = "$first" ]
    [ "$(find_kit_script release.yml build)" = "$first" ]
    [ "$(find_kit_script release.yml publish)" = "$first" ]
}

@test "a version tag becomes a fully qualified tag ref" {
    run_find_kit v1
    [ "$status" -eq 0 ]
    grep -qx 'ref=refs/tags/v1' "$GITHUB_OUTPUT"
    grep -qx 'repo=owner/fork-kit' "$GITHUB_OUTPUT"
}

@test "a full commit SHA is used as it is" {
    run_find_kit 0123456789abcdef0123456789abcdef01234567
    [ "$status" -eq 0 ]
    grep -qx 'ref=0123456789abcdef0123456789abcdef01234567' "$GITHUB_OUTPUT"
}

@test "a branch name or anything else is refused" {
    for value in main refs/heads/v1 "v1 x" "'v1;id'"; do
        run_find_kit "$value"
        [ "$status" -ne 0 ]
    done
}
