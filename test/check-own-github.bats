load helpers

setup() { make_repo; mkdir -p .github/workflows; }

@test "only fork.yml and fork-* workflows pass" {
    echo a >.github/fork.yml; echo b >.github/workflows/fork-sync.yml
    git add -A; git commit -q -m own
    run "$BIN/check-own-github" HEAD
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "upstream's workflows and other .github files fail, by name" {
    echo a >.github/fork.yml; echo b >.github/workflows/ci.yml; echo c >.github/FUNDING.yml
    git add -A; git commit -q -m mixed
    run "$BIN/check-own-github" HEAD
    [ "$status" -eq 1 ]
    [[ "$output" == *".github/workflows/ci.yml"* ]]
    [[ "$output" == *".github/FUNDING.yml"* ]]
}

@test "a workflow named like a fork file in another folder fails" {
    mkdir -p .github/actions; echo a >.github/actions/fork-x.yml
    git add -A; git commit -q -m other
    run "$BIN/check-own-github" HEAD
    [ "$status" -eq 1 ]
}

@test "no .github at all passes" {
    commit a
    run "$BIN/check-own-github" HEAD
    [ "$status" -eq 0 ]
}
