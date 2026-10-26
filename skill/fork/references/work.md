# Work in a persistent fork

Read `fork.yml` from `origin/HEAD` first, as `SKILL.md` describes. `<mirror>`, `<trunk>` and
`<upstream>` below come from it.

## feature

Ask the user whether the change is upstream-bound or fork-only. If unsure, treat it as
upstream-bound: a branch based on pristine upstream can still merge into the trunk.

Upstream-bound:

```bash
git fetch upstream --tags
git fetch origin
git switch -c feat/<name> upstream/<mirror>
```

Fork-only:

```bash
git fetch origin
git switch -c fork/<name> origin/<trunk>
```

To ship an upstream-bound change before upstream merges it, merge the `feat/*` branch into the
trunk with `--no-ff`. When upstream later releases the same change, the next sync removes the
duplicate on its own or stops on a conflict. On a conflict, upstream's version usually wins.

## sync

The scheduled `fork-sync.yml` normally does this. Do it by hand only on the user's request.

```bash
git fetch upstream --tags
git fetch origin
git switch <trunk>
git merge --ff-only origin/<trunk>
git merge --no-ff <release ref, or upstream/<mirror> for the tip>
```

On a conflict, stop. List the files with `git diff --name-only --diff-filter=U` and hand them
to the user. Do not resolve them. On a clean merge, run the `verify` command from `fork.yml`
before you push. Never push the mirror by hand: the workflow keeps it equal to upstream.

If the workflow parked a conflict in a `sync/<ref>` PR, the PR body lists the conflicting files
and the steps. Follow them with the user:

1. Update the local trunk: `git fetch origin`, `git switch <trunk>`, `git merge --ff-only
   origin/<trunk>`.
2. Merge: `git merge --no-ff -m "Merge upstream <ref>" origin/sync/<ref>`.
3. Show the user each conflict and agree on the resolution. Where upstream now does what a
   fork patch did, propose upstream's version. Never pick a side without the user.
4. Run the `verify` command, then push the trunk. GitHub marks the PR as merged.
5. Never use the PR's merge button. A squash or rebase merge drops upstream's commits from
   the trunk's history.

## release

```bash
gh workflow run fork-release.yml -R <owner>/<name>                    # computed version
gh workflow run fork-release.yml -R <owner>/<name> -f version=<tag>   # explicit version
```

Fork release tags always end in `-<suffix>.<N>`. Upstream tags never have that suffix.

## status

Read-only. Report:

```bash
git fetch upstream --tags -q && git fetch origin --tags -q
git rev-list --count origin/<mirror>..upstream/<mirror>     # mirror lag, expected 0
git rev-list --left-right --count upstream/<mirror>...origin/<trunk>
gh release list -R <owner>/<name> -L 1                      # last release
gh pr list -R <owner>/<name> --search 'head:sync/'          # parked conflicts
gh run list -R <owner>/<name> --workflow fork-sync.yml -L 3
gh workflow view fork-sync.yml -R <owner>/<name>            # disabled after 60 quiet days?
```

Also list the `feat/*` branches whose commits upstream already has: `git cherry -v
upstream/<mirror> <branch>` marks those commits with a minus sign. Report whether `kit` and `schema`
are current. For a tip-source fork, report whether upstream started to publish releases.

## upgrade

1. Read the kit's `CHANGELOG.md` for every kit and schema version after the fork's.
2. On an `upgrade/kit-<version>` branch from the trunk, render the current templates again
   with the values from the old `fork.yml`. Apply the schema changes from the changelog.
3. Open a PR to the trunk. List what changed and why, from the changelog.
