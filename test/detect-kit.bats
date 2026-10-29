load helpers

HOOK="$BATS_TEST_DIRNAME/../scripts/detect-kit.sh"

make_kit() {
    make_repo
    mkdir -p .claude-plugin .github/workflows sub
    echo '{ "name": "fork-kit" }' >.claude-plugin/plugin.json
    echo 'name: Sync upstream' >.github/workflows/sync.yml
}

@test "the kit prints the context JSON, from any directory in it" {
    make_kit
    cd sub
    run "$HOOK"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("fork-kit:kit-audit")'
}

@test "another plugin with a sync workflow prints nothing" {
    make_kit
    echo '{ "name": "other" }' >.claude-plugin/plugin.json
    run "$HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "a repository without the plugin prints nothing" {
    make_repo
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
