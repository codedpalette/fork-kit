load helpers

setup() { make_repo; }

@test "writes the version into each listed file" {
    printf '{"version": "1.2.3", "name": "x"}\n' >package.json
    printf '{"version": "1.2.3"}\n' >manifest.json
    run "$BIN/stamp-files" 1.2.3-patched.4 \
        '{"package.json": ".version = $version", "manifest.json": ".version = $version | .name = \"y\""}'
    [ "$status" -eq 0 ]
    [ "$(jq -r .version package.json)" = 1.2.3-patched.4 ]
    [ "$(jq -r .name package.json)" = x ]
    [ "$(jq -r .name manifest.json)" = y ]
    [ ! -e package.json.stamped ]
}

@test "an empty map changes nothing" {
    run "$BIN/stamp-files" 1.2.3-patched.4 '{}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "a missing file fails" {
    run "$BIN/stamp-files" 1.2.3-patched.4 '{"package.json": ".version = $version"}'
    [ "$status" -ne 0 ]
}

@test "a wrong number of arguments exits 2" {
    run "$BIN/stamp-files" 1.2.3-patched.4
    [ "$status" -eq 2 ]
}
