load helpers

HOOK="$BATS_TEST_DIRNAME/../skill/fork/hooks/detect-fork.sh"

# A clone whose origin/HEAD (the trunk) has .github/fork.yml, checked out on a
# branch cut from the mirror, which does not.
make_fork_clone() {
    make_repo
    commit upstream
    git branch -q mirror
    git switch -q -c trunk
    mkdir -p .github && echo 'schema: 1' >.github/fork.yml
    git add .github && git commit -q -m tooling
    ORIGIN="$BATS_TEST_TMPDIR/origin.git"
    git clone -q --bare "$REPO" "$ORIGIN"
    git -C "$ORIGIN" symbolic-ref HEAD refs/heads/trunk
    CLONE="$BATS_TEST_TMPDIR/clone"
    git clone -q "$ORIGIN" "$CLONE"
    cd "$CLONE"
    git switch -q -c feat/probe origin/mirror
}

@test "fork clone on a branch without fork.yml prints the context JSON" {
    make_fork_clone
    [ ! -e .github/fork.yml ]
    run "$HOOK"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"'
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("fork skill")'
}

@test "repository without fork.yml prints nothing" {
    make_repo
    commit a
    run "$HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "directory outside git prints nothing" {
    cd "$BATS_TEST_TMPDIR"
    run "$HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
