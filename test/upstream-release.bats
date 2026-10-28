load helpers

setup() {
    make_repo
    commit a
    UPSTREAM="$REPO"
}

@test "tip source prints nothing and exits 0" {
    run "$BIN/upstream-release" "$UPSTREAM" tip
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "tag source: highest semver tag, ignoring prerelease and fork tags" {
    git tag v1.2.0
    commit b; git tag v1.10.0
    commit c; git tag v1.11.0-rc.1
    commit d; git tag v1.10.0-patched.1
    run "$BIN/upstream-release" "$UPSTREAM" tag
    [ "$status" -eq 0 ]
    [ "$output" = "v1.10.0" ]
}

@test "tag source without tags exits 3" {
    run "$BIN/upstream-release" "$UPSTREAM" tag
    [ "$status" -eq 3 ]
}

@test "tag source with a prefix: only tags with that prefix count" {
    git tag release-1.2.0
    commit b; git tag release-1.10.0
    commit c; git tag 9.9.9
    commit d; git tag release-1.11.0-rc.1
    run "$BIN/upstream-release" "$UPSTREAM" tag release-
    [ "$status" -eq 0 ]
    [ "$output" = "release-1.10.0" ]
}

@test "a prefix with regex characters matches only itself" {
    git tag pkg@1.0.0
    commit b; git tag pkgX1.5.0
    run "$BIN/upstream-release" "$UPSTREAM" tag 'pkg@'
    [ "$output" = "pkg@1.0.0" ]
    run "$BIN/upstream-release" "$UPSTREAM" tag 'pkg.'
    [ "$status" -eq 3 ]
}

@test "npm is no longer a source" {
    run "$BIN/upstream-release" "$UPSTREAM" npm
    [ "$status" -eq 2 ]
}

@test "unknown source exits 2" {
    run "$BIN/upstream-release" "$UPSTREAM" weekly
    [ "$status" -eq 2 ]
}
