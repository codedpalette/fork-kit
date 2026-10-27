# bin/merge-upstream merges an upstream ref into the trunk and strips
# upstream's CI (.github/workflows, .github/actions) from the result, keeping
# only the fork's own fork-*.yml workflows.

load helpers

# A trunk with one fork workflow and one leftover upstream workflow, and an
# upstream branch to merge.
setup() {
    make_repo
    mkdir -p .github/workflows .github/actions/build
    echo "upstream ci v1" >.github/workflows/ci.yml
    echo "action v1" >.github/actions/build/action.yml
    printf '%s\n' a b c >lib.txt
    git add -A && git commit -q -m "upstream: first"
    git branch upstream
    git switch -q -c trunk
    echo "fork sync" >.github/workflows/fork-sync.yml
    sed -i.bak '1s/.*/a-fork/' lib.txt && rm lib.txt.bak
    git add -A && git commit -q -m "fork: tooling and patch"
}

upstream_commit() {  # <message> <shell snippet>
    git switch -q upstream
    eval "$2"
    git add -A && git commit -q -m "$1"
    UPSTREAM_SHA="$(git rev-parse HEAD)"
    git switch -q trunk
}

ci_files() { git ls-tree -r --name-only HEAD -- .github/workflows .github/actions | tr '\n' ' '; }

@test "merges and keeps only the fork's own workflows" {
    upstream_commit "upstream: new workflow" "echo evil >.github/workflows/new.yml; sed -i.bak '3s/.*/c2/' lib.txt; rm lib.txt.bak"
    run "$BIN/merge-upstream" "$UPSTREAM_SHA" "Merge upstream x"
    [ "$status" -eq 0 ]
    [ "$output" = merged ]
    [ "$(ci_files)" = ".github/workflows/fork-sync.yml " ]
    [ "$(sed -n 1p lib.txt)" = a-fork ]
    [ "$(sed -n 3p lib.txt)" = c2 ]
    [ "$(git log -1 --format=%s)" = "Merge upstream x" ]
    [ "$(git rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" = 3 ]
}

@test "an upstream change to a workflow the trunk already dropped stays dropped" {
    git rm -q -r .github/workflows/ci.yml .github/actions && git commit -q -m "fork: drop upstream ci"
    upstream_commit "upstream: change ci" "echo 'upstream ci v2' >.github/workflows/ci.yml; echo 'action v2' >.github/actions/build/action.yml"
    run "$BIN/merge-upstream" "$UPSTREAM_SHA" "Merge upstream y"
    [ "$status" -eq 0 ]
    [ "$output" = merged ]
    [ "$(ci_files)" = ".github/workflows/fork-sync.yml " ]
}

@test "a new upstream workflow named like a fork workflow is still stripped" {
    upstream_commit "upstream: impostor" "echo evil >.github/workflows/fork-release.yml"
    run "$BIN/merge-upstream" "$UPSTREAM_SHA" "Merge upstream z"
    [ "$output" = merged ]
    [ "$(ci_files)" = ".github/workflows/fork-sync.yml " ]
}

@test "a conflict outside CI files is reported and leaves the trunk untouched" {
    before="$(git rev-parse HEAD)"
    upstream_commit "upstream: same line" "sed -i.bak '1s/.*/a-upstream/' lib.txt; rm lib.txt.bak"
    run "$BIN/merge-upstream" "$UPSTREAM_SHA" "Merge upstream w"
    [ "$status" -eq 0 ]
    [ "$output" = conflict ]
    [ "$(git rev-parse HEAD)" = "$before" ]
    [ -z "$(git status --porcelain)" ]
}

@test "an upstream ref already in the trunk is current" {
    run "$BIN/merge-upstream" "$(git rev-parse upstream)" "Merge upstream v"
    [ "$output" = current ]
}

@test "the same inputs give the same tree" {
    upstream_commit "upstream: new workflow" "echo evil >.github/workflows/new.yml"
    start="$(git rev-parse HEAD)"
    "$BIN/merge-upstream" "$UPSTREAM_SHA" "Merge upstream u" >/dev/null
    first="$(git rev-parse 'HEAD^{tree}')"
    git reset -q --hard "$start"
    "$BIN/merge-upstream" "$UPSTREAM_SHA" "Merge upstream u" >/dev/null
    [ "$(git rev-parse 'HEAD^{tree}')" = "$first" ]
}

@test "strip-upstream-ci removes all CI files and commits" {
    run "$BIN/strip-upstream-ci" "Remove upstream CI"
    [ "$status" -eq 0 ]
    [ -z "$(ci_files)" ]
    [ "$(git log -1 --format=%s)" = "Remove upstream CI" ]
}

@test "strip-upstream-ci with nothing to strip makes no commit" {
    git rm -q -r .github && git commit -q -m "no ci"
    before="$(git rev-parse HEAD)"
    run "$BIN/strip-upstream-ci" "Remove upstream CI"
    [ "$status" -eq 0 ]
    [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "upstream cannot take over a fork file by copying it first, then changing it" {
    mkdir -p .github && echo "kit: v1" >.github/fork.yml
    git add -A && git commit -q -m "fork: config"
    # Step 1: upstream adds a byte-identical copy. The merge is clean.
    upstream_commit "upstream: copy" "mkdir -p .github; echo 'kit: v1' >.github/fork.yml"
    run "$BIN/merge-upstream" "$UPSTREAM_SHA" "Merge upstream 1"
    [ "$output" = merged ]
    before="$(git rev-parse HEAD)"
    # Step 2: upstream changes its copy. The trunk keeps its own file.
    upstream_commit "upstream: change" "echo 'kit-repo: evil/kit' >>.github/fork.yml"
    run "$BIN/merge-upstream" "$UPSTREAM_SHA" "Merge upstream 2"
    [ "$output" = merged ]
    [ "$(git show HEAD:.github/fork.yml)" = "kit: v1" ]
}

@test "an upstream change to FORK.md is refused, one to a fork workflow is ignored" {
    echo "# Fork" >FORK.md
    git add -A && git commit -q -m "fork: docs"
    upstream_commit "upstream: copy" "echo '# Fork' >FORK.md; echo 'fork sync' >.github/workflows/fork-sync.yml"
    run "$BIN/merge-upstream" "$UPSTREAM_SHA" "Merge upstream 1"
    [ "$output" = merged ]
    upstream_commit "upstream: change" "echo evil >>FORK.md"
    run "$BIN/merge-upstream" "$UPSTREAM_SHA" "Merge upstream 2"
    [ "$output" = conflict ]
    git switch -q upstream && git reset -q --hard HEAD~1 && git switch -q trunk
    upstream_commit "upstream: change" "echo evil >>.github/workflows/fork-sync.yml"
    run "$BIN/merge-upstream" "$UPSTREAM_SHA" "Merge upstream 3"
    [ "$output" = merged ]
    [ "$(git show HEAD:.github/workflows/fork-sync.yml)" = "fork sync" ]
}

@test "an upstream file identical to the fork's own merges without change" {
    mkdir -p .github && echo "kit: v1" >.github/fork.yml
    git add -A && git commit -q -m "fork: config"
    upstream_commit "upstream: same file" "mkdir -p .github; echo 'kit: v1' >.github/fork.yml"
    run "$BIN/merge-upstream" "$UPSTREAM_SHA" "Merge upstream s"
    [ "$output" = merged ]
}

@test "workflow file names that git quotes are stripped too" {
    upstream_commit "upstream: odd names" "echo evil >'.github/workflows/caf\303\251.yml'; printf evil >\$'.github/workflows/tab\tname.yml'; echo evil >'.github/workflows/quote\"d.yml'"
    run "$BIN/merge-upstream" "$UPSTREAM_SHA" "Merge upstream q"
    [ "$status" -eq 0 ]
    [ "$output" = merged ]
    [ "$(ci_files)" = ".github/workflows/fork-sync.yml " ]
}

@test "the rest of upstream's .github is stripped, the fork's fork.yml stays" {
    mkdir -p .github && echo "kit: v1" >.github/fork.yml
    git add -A && git commit -q -m "fork: config"
    upstream_commit "upstream: more .github" "mkdir -p .github/ISSUE_TEMPLATE; echo x >.github/ISSUE_TEMPLATE/bug.md; echo x >.github/dependabot.yml; echo x >.github/CODEOWNERS"
    run "$BIN/merge-upstream" "$UPSTREAM_SHA" "Merge upstream g"
    [ "$output" = merged ]
    [ "$(git ls-tree -r --name-only HEAD -- .github | tr '\n' ' ')" = ".github/fork.yml .github/workflows/fork-sync.yml " ]
}

@test "strip-upstream-ci removes every .github file, whatever its name" {
    printf evil >".github/workflows/caf\303\251.yml"
    echo x >.github/dependabot.yml
    git add -A && git commit -q -m "odd names"
    run "$BIN/strip-upstream-ci" "Remove upstream CI"
    [ "$status" -eq 0 ]
    [ -z "$(git ls-tree -r --name-only HEAD -- .github)" ]
}

