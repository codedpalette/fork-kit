# Shared fixtures for the bats tests. Each test gets a throwaway git repository
# in BATS_TEST_TMPDIR, so tests never touch the network or each other.

BIN="$BATS_TEST_DIRNAME/../bin"

# Create an empty repository and cd into it.
make_repo() {
    REPO="$BATS_TEST_TMPDIR/repo"
    git init -q -b main "$REPO"
    cd "$REPO"
    git config user.name test
    git config user.email test@example.com
}

# Add one commit; the message doubles as the file content so each commit differs.
commit() {
    printf '%s\n' "$1" >>file.txt
    git add file.txt
    git commit -q -m "$1"
}
