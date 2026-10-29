load helpers

setup() {
    make_repo
    commit 'feat: first'
    git tag v1.2.3
}

@test "no commit after the last release prints nothing" {
    run "$BIN/kit-version" HEAD
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "a fix is a patch" {
    commit 'fix(sync): something'
    run "$BIN/kit-version" HEAD
    [ "$output" = v1.2.4 ]
}

@test "a docs or other prefix is a patch" {
    commit 'docs: readme'
    run "$BIN/kit-version" HEAD
    [ "$output" = v1.2.4 ]
}

@test "a feat is a minor, even with a fix next to it" {
    commit 'fix: one'
    commit 'feat(skill): two'
    run "$BIN/kit-version" HEAD
    [ "$output" = v1.3.0 ]
}

@test "a bang before the colon is a major" {
    commit 'feat: one'
    commit 'fix(sync)!: two'
    run "$BIN/kit-version" HEAD
    [ "$output" = v2.0.0 ]
}

@test "a BREAKING CHANGE line in the body is a major" {
    printf 'x\n' >>file.txt
    git commit -q -am 'fix: one' -m 'BREAKING CHANGE: fork.yml loses a key'
    run "$BIN/kit-version" HEAD
    [ "$output" = v2.0.0 ]
}

@test "merge commits are skipped" {
    git switch -q -c topic
    commit 'docs: one'
    git switch -q main
    git merge -q --no-ff -m 'feat!: a merge message that is not the author'"'"'s' topic
    run "$BIN/kit-version" HEAD
    [ "$output" = v1.2.4 ]
}

@test "the highest version tag counts, not the newest or a major tag" {
    commit 'fix: one'
    git tag v1.10.0
    git tag v1
    commit 'fix: two'
    run "$BIN/kit-version" HEAD
    [ "$output" = v1.10.1 ]
}

@test "no version tag fails" {
    git tag -d v1.2.3 >/dev/null
    run "$BIN/kit-version" HEAD
    [ "$status" -eq 1 ]
}
