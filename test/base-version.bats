load helpers

setup() { make_repo; }

@test "release source: nearest bare upstream tag, ignoring prerelease and fork tags" {
    commit a; git tag 8.5.0
    commit b; git tag 108.5.0-preview.1
    commit c; git tag 8.6.0
    commit d; git tag 8.6.0-patched.1
    commit e
    run "$BIN/base-version" release
    [ "$status" -eq 0 ]
    [ "$output" = "8.6.0" ]
}

@test "keeps upstream's v prefix" {
    commit a; git tag v3.1.3
    commit b; git tag v3.1.3-expofp.5
    run "$BIN/base-version" tag
    [ "$status" -eq 0 ]
    [ "$output" = "v3.1.3" ]
}

@test "tip source: version from the version file" {
    echo '{"version": "2.4.0"}' >package.json
    run "$BIN/base-version" tip
    [ "$status" -eq 0 ]
    [ "$output" = "2.4.0" ]
}

@test "tip source: custom version file" {
    echo '{"version": "1.2.3"}' >manifest.json
    run "$BIN/base-version" tip manifest.json
    [ "$output" = "1.2.3" ]
}

@test "no reachable upstream tag exits 3" {
    commit a; git tag 1.0.0-patched.1
    run "$BIN/base-version" release
    [ "$status" -eq 3 ]
}
