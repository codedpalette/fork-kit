load helpers

setup() {
    make_repo
    mkdir -p .github
    cat >.github/fork.yml <<'YAML'
schema: 1
kit: v1
kit-repo: codedpalette/fork-kit
upstream: owner/project
mirror: main
trunk: patched
node: 22
sync:
  source: release
  npm-package: ''
  verify: npm ci && npm test
release:
  suffix: patched
  build: npm run build
  version-file: package.json
  stamp:
    package.json: '.version = $version'
  assets: [dist/a.js, package.json]
  commit: []
YAML
}

value() { grep "^$1=" <<<"$output" | cut -d= -f2-; }

@test "prints every key as name=value for GITHUB_OUTPUT" {
    run "$BIN/fork-config" .github/fork.yml
    [ "$status" -eq 0 ]
    [ "$(value upstream)" = owner/project ]
    [ "$(value trunk)" = patched ]
    [ "$(value source)" = release ]
    [ "$(value verify)" = "npm ci && npm test" ]
    [ "$(value suffix)" = patched ]
    [ "$(value assets)" = '["dist/a.js","package.json"]' ]
    [ "$(value commit)" = '[]' ]
    [ "$(value stamp)" = '{"package.json":".version = $version"}' ]
}

@test "missing optional keys get defaults" {
    yq -i 'del(.release) | del(.sync.verify) | del(.node)' .github/fork.yml
    run "$BIN/fork-config" .github/fork.yml
    [ "$status" -eq 0 ]
    [ "$(value suffix)" = patched ]
    [ "$(value verify)" = true ]
    [ "$(value assets)" = '[]' ]
    [ "$(value version-file)" = package.json ]
}

@test "an unknown schema fails with a message" {
    yq -i '.schema = 2' .github/fork.yml
    run "$BIN/fork-config" .github/fork.yml
    [ "$status" -eq 1 ]
    [[ "$output" == *"schema 2"* ]]
}

@test "an unknown sync source fails" {
    yq -i '.sync.source = "weekly"' .github/fork.yml
    run "$BIN/fork-config" .github/fork.yml
    [ "$status" -eq 1 ]
}

@test "a missing required key fails" {
    yq -i 'del(.trunk)' .github/fork.yml
    run "$BIN/fork-config" .github/fork.yml
    [ "$status" -eq 1 ]
    [[ "$output" == *trunk* ]]
}
