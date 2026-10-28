# Work in a persistent fork

Read `fork.yml` from `origin/HEAD` first, as `SKILL.md` describes. `<mirror>`, `<trunk>` and
`<upstream>` below come from it.

## feature

Ask the user whether the change is upstream-bound or fork-only. If unsure, treat it as
upstream-bound: a branch based on pristine upstream can still merge into the trunk.

Upstream-bound:

```bash
git fetch upstream
git fetch origin
git switch -c feat/<name> "$(git merge-base origin/<trunk> upstream/<mirror>)"
```

The merge base is the newest upstream commit that the trunk holds: its upstream release, or
the tip it last merged. The upstream PR shows only the branch's own commits, because
upstream's `<mirror>` already holds that commit. If upstream asks for a rebase onto its tip,
rebase the PR branch only. The trunk keeps the version that it merged.

Fork-only:

```bash
git fetch origin
git switch -c fork/<name> origin/<trunk>
```

To ship an upstream-bound change before upstream merges it, merge the `feat/*` branch into the
trunk with `--no-ff`. When upstream later releases the same change, the next sync removes the
duplicate on its own or stops on a conflict. On a conflict, upstream's version usually wins.

If a release stops with "The trunk holds upstream code", a branch from upstream's tip was
merged into the trunk. Rebuild the trunk from its upstream release plus the fork's own
commits. Show the user the result, and force-push it only after the user approves:

```bash
git fetch upstream --tags
git switch -c rebuild "refs/tags/<tag-prefix><base>"           # the base the error names
git rm -r -q --ignore-unmatch .github                           # none of upstream's .github
git commit -q -m "chore: remove upstream's .github"
git log --reverse --no-merges --format=%H origin/<trunk> ^upstream/<mirror> -- . ':!.github' |
  xargs git cherry-pick                                        # the fork's own commits
git checkout origin/<trunk> -- .github/fork.yml '.github/workflows/fork-*'
git commit -q -m "chore: restore the fork tooling"
"$KIT_DIR/bin/check-own-github" rebuild                       # prints any file that is not the fork's
```

The last command must print nothing. Any file it prints would run on the trunk with the
fork's secrets. Remove it before the push.

## sync

The scheduled `fork-sync.yml` normally does this. Do it by hand only on the user's request.

```bash
git fetch upstream --tags
git fetch origin
git switch <trunk>
git merge --ff-only origin/<trunk>
"$KIT_DIR/bin/merge-upstream" "$(git rev-parse '<release ref, or upstream/<mirror> for the tip>^{commit}')" "Merge upstream <ref>"
```

`KIT_DIR` is as in `references/create.md`. The script merges and removes upstream's `.github`, which
must never reach the trunk. It prints `merged`, `current` or `conflict`. On `conflict`,
repeat the merge with `git merge --no-ff --no-commit`, list the files with
`git diff --name-only --diff-filter=U`, and hand them to the user. Do not resolve them. On
`merged`, run the `verify` command from `fork.yml` before you push. Never push upstream's
branches to the fork.

A push to the trunk starts the release workflow on its own, unless `sync.source` is `tip`.
Do not also dispatch `fork-release.yml`, because a second run publishes a duplicate release.
For a `tip` fork, offer the `release` mode after the push.

If the workflow parked a conflict in a `sync/<ref>` PR, the PR body lists the conflicting files
and the steps. Follow them with the user:

1. Update the local trunk: `git fetch origin`, `git switch <trunk>`, `git merge --ff-only
   origin/<trunk>`.
2. Merge: `git merge --no-ff -m "Merge upstream <ref>" origin/sync/<ref>`.
3. Show the user each conflict and agree on the resolution. Where upstream now does what a
   fork patch did, propose upstream's version. Never pick a side without the user.
4. Run the `verify` command, then push the trunk. GitHub marks the PR as merged, and the
   push starts the release workflow on its own.
5. Never use the PR's merge button. A squash or rebase merge drops upstream's commits from
   the trunk's history.

## release

```bash
gh workflow run fork-release.yml -R <owner>/<name>                    # computed version
gh workflow run fork-release.yml -R <owner>/<name> -f version=<base>-<suffix>.<N>   # explicit version, only for the trunk's base
```

Fork release tags always end in `-<suffix>.<N>`. Upstream tags never have that suffix.

## status

Read-only. Report:

```bash
git fetch upstream --tags -q && git fetch origin --tags -q
git rev-list --left-right --count upstream/<mirror>...origin/<trunk>
git ls-tree -r --name-only origin/<trunk> -- .github   # only fork.yml and fork-* files
gh release list -R <owner>/<name> -L 1                      # last release
gh pr list -R <owner>/<name> --search 'head:sync/'          # parked conflicts
gh run list -R <owner>/<name> --workflow fork-sync.yml -L 3
gh workflow view fork-sync.yml -R <owner>/<name>            # disabled after 60 quiet days?
```

If the trunk has CI files other than `fork-*`, report them as a security problem: upstream's
workflows run in the fork with its secrets. Also list the `feat/*` branches whose commits upstream already has: `git cherry -v
upstream/<mirror> <branch>` marks those commits with a minus sign. Report whether `kit` and `schema`
are current. For a tip-source fork, report whether upstream started to publish releases.

## upgrade

1. Read the kit's `CHANGELOG.md` for every kit and schema version after the fork's.
2. On an `upgrade/kit-<version>` branch from the trunk, render the current templates again
   with the values from the old `fork.yml`. Apply the schema changes from the changelog.
3. Open a PR to the trunk. List what changed and why, from the changelog.
