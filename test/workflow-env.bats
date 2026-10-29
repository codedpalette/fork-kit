# Every uppercase $VARIABLE a workflow step's script uses must come from that
# step's env:, from the runner or from bash. Lowercase names are the scripts'
# own locals.
# A variable missing from env: expands to nothing, silently.

KNOWN='^(GITHUB_[A-Z_]+|RUNNER_[A-Z_]+|BASH_[A-Z_]+|HOME|PATH|PWD|CI)$'

undefined_vars() {  # <workflow file>
    local file="$1" job step count i
    for job in $(yq -r '.jobs | keys | .[]' "$file"); do
        count="$(yq ".jobs.$job.steps | length" "$file")"
        for ((i = 0; i < count; i++)); do
            local script env_keys
            script="$(yq -r ".jobs.$job.steps[$i].run // \"\"" "$file")"
            [ -n "$script" ] || continue
            env_keys="$(yq -r ".jobs.$job.steps[$i].env // {} | keys | .[]" "$file")"
            grep -oE '\$\{?[A-Z][A-Z0-9_]*' <<<"$script" | tr -d '${' | sort -u |
                while read -r var; do
                    [[ "$var" =~ $KNOWN ]] && continue
                    grep -qx "$var" <<<"$env_keys" ||
                        echo "$file: job $job, step $i ($(yq -r ".jobs.$job.steps[$i].name // \"\"" "$file")): \$$var is not in env"
                done
        done
    done
}

@test "workflow scripts use only variables their step defines" {
    local out=""
    for f in "$BATS_TEST_DIRNAME"/../.github/workflows/*.yml; do
        out+="$(undefined_vars "$f")"
    done
    echo "$out"
    [ -z "$out" ]
}
