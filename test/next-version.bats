load helpers

setup() { make_repo; commit a; }

@test "first release on a base is .1" {
    run "$BIN/next-version" 8.6.0 patched
    [ "$status" -eq 0 ]
    [ "$output" = "8.6.0-patched.1" ]
}

@test "uses the highest N numerically, not the count" {
    git tag 8.6.0-patched.1
    git tag 8.6.0-patched.2
    git tag 8.6.0-patched.10
    run "$BIN/next-version" 8.6.0 patched
    [ "$output" = "8.6.0-patched.11" ]
}

@test "N resets on a new base" {
    git tag 8.5.0-patched.4
    run "$BIN/next-version" 8.6.0 patched
    [ "$output" = "8.6.0-patched.1" ]
}

@test "upstream's bare tag is not counted" {
    git tag 8.6.0
    run "$BIN/next-version" 8.6.0 patched
    [ "$output" = "8.6.0-patched.1" ]
}

@test "other suffixes are not counted" {
    git tag v3.1.3-expofp.5
    run "$BIN/next-version" v3.1.3 patched
    [ "$output" = "v3.1.3-patched.1" ]
}
