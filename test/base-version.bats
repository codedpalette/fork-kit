load helpers

setup() { make_repo; }

# An upstream tag, where the workflows fetch them: refs/upstream-tags/<name>.
utag() { git update-ref "refs/upstream-tags/$1" "${2:-HEAD}"; }

@test "release source: nearest bare upstream tag, ignoring prerelease and fork tags" {
    commit a; utag 8.5.0
    commit b; utag 108.5.0-preview.1
    commit c; utag 8.6.0
    commit d; git tag 8.6.0-patched.1
    commit e
    run "$BIN/base-version" release
    [ "$status" -eq 0 ]
    [ "$output" = "8.6.0" ]
}

@test "a high version tagged on an old commit never becomes the base" {
    commit a; utag 99.0.0
    commit b; utag 8.6.0
    commit c
    run "$BIN/base-version" release
    [ "$output" = "8.6.0" ]
}

@test "two tags on one commit: the higher version wins" {
    commit a; utag 8.6.0; utag 8.6.1
    run "$BIN/base-version" release
    [ "$output" = "8.6.1" ]
}

@test "the fork's own tags and tags outside HEAD's history never count" {
    commit a; utag 1.0.0
    commit b; git tag 2.0.0
    git switch -q -c other; commit c; utag 3.0.0; git switch -q -
    run "$BIN/base-version" release
    [ "$output" = "1.0.0" ]
}

@test "non-version tags never count" {
    commit a; utag 1.0.0
    commit b; utag nightly2026; utag release-1.2.3
    run "$BIN/base-version" release
    [ "$output" = "1.0.0" ]
}

@test "keeps upstream's v prefix" {
    commit a; utag v3.1.3
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
    commit a; git tag 1.0.0; utag 1.0.0-patched.1
    run "$BIN/base-version" release
    [ "$status" -eq 3 ]
}

@test "tip source without a version file: date of the newest upstream commit merged in" {
    GIT_COMMITTER_DATE="2026-01-05T23:30:00Z" commit upstream-work
    git branch upstream-tip
    GIT_COMMITTER_DATE="2026-03-09T10:00:00Z" commit fork-patch
    run "$BIN/base-version" tip package.json upstream-tip
    [ "$status" -eq 0 ]
    [ "$output" = "2026.1.5" ]
}

@test "tip source: a version file wins over the date" {
    echo '{"version": "2.4.0"}' >package.json
    commit a
    run "$BIN/base-version" tip package.json HEAD
    [ "$output" = "2.4.0" ]
}

@test "tip source without a version file or an upstream ref exits 3" {
    commit a
    run "$BIN/base-version" tip
    [ "$status" -eq 3 ]
}

