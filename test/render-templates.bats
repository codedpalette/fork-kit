load helpers

setup() {
    make_repo
    VALUES="$BATS_TEST_TMPDIR/values.json"
    cat >"$VALUES" <<'JSON'
{"kit_repo": "me/fork-kit", "upstream": "org/project", "mirror": "main", "trunk": "dev",
 "node": "22", "source": "release", "tag_prefix": "",
 "verify": "yarn && yarn run lint:no-fix # comment: kept && echo 'a: b'",
 "suffix": "patched", "build": "yarn run build", "version_file": "package.json",
 "stamp": {"manifest.json": ".version = $version | .name = \"X (patched)\""},
 "assets": ["main.js", "manifest.json"], "commit": [], "install": "Add `org/project` in BRAT."}
JSON
}

@test "renders every file, and fork.yml reads back exactly" {
    run "$BIN/render-templates" "$VALUES" .
    [ "$status" -eq 0 ]
    for f in .github/fork.yml .github/workflows/fork-sync.yml .github/workflows/fork-release.yml \
        .github/workflows/fork-check.yml FORK.md; do [ -s "$f" ]; done
    [ "$(yq -r .sync.verify .github/fork.yml)" = "$(jq -r .verify "$VALUES")" ]
    [ "$(yq -r '.release.stamp["manifest.json"]' .github/fork.yml)" = "$(jq -r '.stamp["manifest.json"]' "$VALUES")" ]
    [ "$(yq -o=json -I=0 .release.assets .github/fork.yml)" = '["main.js","manifest.json"]' ]
    [ "$(yq -r '.sync["tag-prefix"]' .github/fork.yml)" = "" ]
}

@test "leaves GitHub's own expressions alone and no placeholder behind" {
    "$BIN/render-templates" "$VALUES" .
    ! grep -rE '\{\{[a-z_]+\}\}' .github FORK.md
    grep -qF '${{ secrets.SYNC_TOKEN }}' .github/workflows/fork-sync.yml
    grep -qF 'uses: me/fork-kit/.github/workflows/sync.yml@v1' .github/workflows/fork-sync.yml
    grep -qF '# Contract: https://github.com/me/fork-kit#forkyml' .github/fork.yml
}

@test "release source keeps the marked lines and drops only the marker" {
    "$BIN/render-templates" "$VALUES" .
    ! grep -q 'tip:remove' .github/workflows/*.yml
    [ "$(yq '.jobs.release.with.ref' .github/workflows/fork-sync.yml)" = '${{ needs.sync.outputs.sha }}' ]
    grep -q '^    # Builds the commit that the sync pushed' .github/workflows/fork-sync.yml
    [ "$(yq '.on.push.branches[0]' .github/workflows/fork-release.yml)" = dev ]
}

@test "tip source drops the marked lines" {
    jq '.source = "tip"' "$VALUES" >v2.json
    "$BIN/render-templates" v2.json .
    [ "$(yq '.jobs | has("release")' .github/workflows/fork-sync.yml)" = false ]
    [ "$(yq '.on | has("push")' .github/workflows/fork-release.yml)" = false ]
}

@test "the install text goes under its heading" {
    "$BIN/render-templates" "$VALUES" .
    grep -A2 '^## Install$' FORK.md | grep -qF 'Add `org/project` in BRAT.'
}

@test "a missing value fails" {
    jq 'del(.build)' "$VALUES" >v2.json
    run "$BIN/render-templates" v2.json .
    [ "$status" -ne 0 ]
    [[ "$output" == *build* ]]
}

@test "a bad trunk name fails" {
    jq '.trunk = "dev; rm -rf /"' "$VALUES" >v2.json
    run "$BIN/render-templates" v2.json .
    [ "$status" -eq 1 ]
}

@test "a value of the wrong type fails before anything is written" {
    for change in '.verify = null' '.node = null' '.stamp = ".version = $version"' \
        '.assets = "main.js"' '.install = {"a": 1}' '.trunk = "dev\n"' '.trunk = "a..b"' \
        '.trunk = "dev.lock"' '.trunk = "dev/"'; do
        jq "$change" "$VALUES" >v2.json
        run "$BIN/render-templates" v2.json .
        [ "$status" -eq 1 ] || { echo "accepted: $change"; false; }
        [ ! -e .github/fork.yml ]
    done
}

@test "a missing value exits 1, names it and writes nothing" {
    jq 'del(.assets, .build)' "$VALUES" >v2.json
    run "$BIN/render-templates" v2.json .
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing values: assets build"* ]]
    [ ! -e .github/fork.yml ]
}

@test "a value that fails fork-config writes nothing" {
    jq '.tag_prefix = "-bad"' "$VALUES" >v2.json
    run "$BIN/render-templates" v2.json .
    [ "$status" -eq 1 ]
    [ ! -e .github/fork.yml ]
}

@test "a trunk that YAML would retype stays a string in the workflows" {
    jq '.trunk = "true"' "$VALUES" >v2.json
    "$BIN/render-templates" v2.json .
    [ "$(yq '.on.pull_request.branches[0] | type' .github/workflows/fork-check.yml)" = '!!str' ]
}
