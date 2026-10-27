# bin/check-release-files checks the files a release build produced, after
# they were unpacked into an empty directory, before anything uses them.

load helpers

CHECK="$BATS_TEST_DIRNAME/../bin/check-release-files"

setup() {
    OUT="$BATS_TEST_TMPDIR/out"
    mkdir -p "$OUT/dist"
    echo a >"$OUT/main.js"
    echo b >"$OUT/dist/lib.js"
    echo '{}' >"$OUT/package.json"
}

@test "listed files and files under listed directories pass" {
    run "$CHECK" "$OUT" main.js dist package.json
    [ "$status" -eq 0 ]
}

@test "a file nobody listed fails" {
    echo x >"$OUT/extra.txt"
    run "$CHECK" "$OUT" main.js dist package.json
    [ "$status" -eq 1 ]
    [[ "$output" == *extra.txt* ]]
}

@test "a symlink fails" {
    ln -s /etc/passwd "$OUT/dist/secret.js"
    run "$CHECK" "$OUT" main.js dist package.json
    [ "$status" -eq 1 ]
}

@test "a hard link fails" {
    ln "$OUT/main.js" "$OUT/dist/copy.js"
    run "$CHECK" "$OUT" main.js dist package.json
    [ "$status" -eq 1 ]
}

@test "anything under a .git directory fails, even when listed" {
    mkdir -p "$OUT/dist/.git"
    echo x >"$OUT/dist/.git/config"
    run "$CHECK" "$OUT" main.js dist package.json
    [ "$status" -eq 1 ]
}

@test "a listed path with .. fails" {
    run "$CHECK" "$OUT" main.js ../etc package.json
    [ "$status" -eq 1 ]
}

@test "an absolute listed path fails" {
    run "$CHECK" "$OUT" /etc/passwd
    [ "$status" -eq 1 ]
}

@test "a FIFO fails" {
    mkfifo "$OUT/dist/pipe"
    run "$CHECK" "$OUT" main.js dist package.json
    [ "$status" -eq 1 ]
}
