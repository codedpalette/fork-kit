load helpers

# Upstream's main: a, b tagged 8.6.0, then c and d, which are not released yet.
setup() {
    make_repo
    commit a; commit b; git tag 8.6.0
    commit c; commit d
    git branch upstream-main
}

@test "a trunk on the release plus fork patches passes" {
    git switch -q -c trunk 8.6.0
    commit patch
    run "$BIN/check-released" 8.6.0 upstream-main
    [ "$status" -eq 0 ]
}

@test "a trunk on upstream's tip fails and counts the unreleased commits" {
    git switch -q -c trunk upstream-main
    commit patch
    run "$BIN/check-released" 8.6.0 upstream-main
    [ "$status" -eq 1 ]
    [[ "$output" == *"2 upstream commits that are not in the release 8.6.0"* ]]
}

@test "a release on a maintenance branch off main passes" {
    git switch -q -c maint 8.6.0
    commit fix; git tag 8.6.1
    git switch -q -c trunk 8.6.1
    commit patch
    run "$BIN/check-released" 8.6.1 upstream-main
    [ "$status" -eq 0 ]
}

@test "wrong argument count exits 2" {
    run "$BIN/check-released" 8.6.0
    [ "$status" -eq 2 ]
}
