# The sync's "Offer the kit's new major version" step. These tests run the
# step's own script against a local kit, a local fork origin and a fake gh.

load helpers

SYNC="$BATS_TEST_DIRNAME/../.github/workflows/sync.yml"

setup() {
    # The kit, with its major tags, served for https://github.com/owner/fork-kit.
    KIT="$BATS_TEST_TMPDIR/kit.git"
    git init -q --bare "$KIT"
    make_repo
    commit kit
    git push -q "$KIT" HEAD:refs/heads/main
    for tag in v1 v1.4.0 v2 v2.0.0; do git push -q "$KIT" "HEAD:refs/tags/$tag"; done
    export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$BATS_TEST_TMPDIR/.insteadOf" \
        GIT_CONFIG_VALUE_0=https://github.com/owner/
    mv "$KIT" "$BATS_TEST_TMPDIR/fork-kit.git"

    # The fork's trunk, as the sync renders it.
    rm -rf "$REPO" && make_repo
    git switch -q -c trunk
    mkdir -p .github/workflows
    printf 'schema: 1\nkit: v1\nkit-repo: owner/fork-kit\n' >.github/fork.yml
    printf 'jobs:\n  sync:\n    uses: owner/fork-kit/.github/workflows/sync.yml@v1\n  release:\n    uses: owner/fork-kit/.github/workflows/release.yml@v1         # a comment\n' \
        >.github/workflows/fork-sync.yml
    printf 'jobs:\n  check:\n    uses: other/repo/.github/workflows/check.yml@v1\n' \
        >.github/workflows/fork-other.yml
    git add .github && git commit -q -m tooling
    ORIGIN="$BATS_TEST_TMPDIR/origin.git"
    git init -q --bare "$ORIGIN"
    git remote add origin "$ORIGIN"
    git push -q origin trunk

    # gh: "pr list" answers with $PR_LIST, everything else is logged.
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/sh\necho "$*" >>"%s/gh.log"\ncase "$1 $2" in "pr list") echo "${PR_LIST:-}" ;; esac\n' \
        "$BATS_TEST_TMPDIR" >"$BATS_TEST_TMPDIR/bin/gh"
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export TRUNK=trunk KIT_REPO=owner/fork-kit OWNER=owner PUSH_TOKEN=x GH_REPO=owner/fork
}

run_step() {
    run bash -e -c "$(yq -r '.jobs.push.steps[] | select(.name == "Offer the kit'"'"'s new major version") | .run' "$SYNC")"
}

@test "a fork on v1 gets one PR that moves it to v2" {
    run_step
    [ "$status" -eq 0 ]
    git -C "$ORIGIN" show fork/kit-v2:.github/fork.yml | grep -qx 'kit: v2'
    sync="$(git -C "$ORIGIN" show fork/kit-v2:.github/workflows/fork-sync.yml)"
    grep -q 'sync.yml@v2$' <<<"$sync"
    grep -q 'release.yml@v2 *# a comment$' <<<"$sync"
    git -C "$ORIGIN" show fork/kit-v2:.github/workflows/fork-other.yml | grep -q 'check.yml@v1$'
    grep -q '^pr create --base trunk --head fork/kit-v2' "$BATS_TEST_TMPDIR/gh.log"
    [ "$(git -C "$ORIGIN" rev-list --count trunk..fork/kit-v2)" -eq 1 ]
    grep -q 'releases/tag/v2.0.0' body.md
    [ "$(git rev-parse --abbrev-ref HEAD)" = trunk ]
}

@test "an open or closed PR for the branch means no new PR" {
    PR_LIST=7 run_step
    [ "$status" -eq 0 ]
    ! grep -q '^pr create' "$BATS_TEST_TMPDIR/gh.log"
    ! git -C "$ORIGIN" rev-parse -q --verify refs/heads/fork/kit-v2
}

@test "a fork on the newest major gets nothing" {
    sed -i.bak 's/^kit: v1$/kit: v2/' .github/fork.yml
    run_step
    [ "$status" -eq 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/gh.log" ]
}

@test "a fork pinned to a full version or a commit gets nothing" {
    for kit in v1.4.0 0123456789abcdef0123456789abcdef01234567; do
        printf 'kit: %s\nkit-repo: owner/fork-kit\n' "$kit" >.github/fork.yml
        run_step
        [ "$status" -eq 0 ]
    done
    [ ! -e "$BATS_TEST_TMPDIR/gh.log" ]
}
