# Changelog

The skill's `upgrade` mode reads this file. Each entry names the kit version, the `fork.yml`
schema version and what a fork must change.

## kit v1 update: branch prefixes, token request first (schema 1, unchanged)

- Fork-only branches always start with `fork/`. An upstream-bound branch takes any prefix
  that fits the change, such as `feat/`, `fix/` or `docs/`, but never `fork/` or `sync/`. It
  still starts from the upstream commit that the trunk is based on.
- The PR check skips `sync/*` PRs. GitHub counts a skipped required check as passed.
- The skill asks the user to add a new fork to the kit's token right after it creates the
  fork. It runs the distribute workflow, a sync or a release only after the user's answer,
  and asks the user to merge the setup PR only after the token arrived.
- `FORK.md` describes the new branch rules.

No change in the forks is needed. To update a fork's `FORK.md`, use the `upgrade` mode.

## kit v1 update: template renderer (schema 1, unchanged)

`bin/render-templates` renders the fork templates from one JSON file of values. It writes
every `fork.yml` value as JSON, so no command or filter can break the YAML, and it leaves
GitHub's own `${{ ... }}` expressions alone. `fork.yml`'s comments now sit above their keys.

No change in the forks is needed.

## kit v1 update: tag prefixes, no npm source, release-based features (schema 1, unchanged)

- `sync.tag-prefix` names the text before the version in upstream's release tags, for
  example `release-`. The fork's versions leave it out. Empty by default.
- The `npm` source is gone, and `sync.npm-package` is no longer read. The `tag` source covers
  packages that tag their releases in git.
- `feat/*` branches start from the upstream commit that the trunk is based on, not from
  upstream's tip, so merging one into the trunk never brings in unreleased upstream code.
- The skill deletes the mirror and `setup/fork` branches itself, and asks the user only when
  its permissions block the deletion.
- The PR check fails a PR that would leave any `.github` file on the trunk other than
  `fork.yml` and `fork-*` workflows (`bin/check-own-github`).

No change in the forks is needed, except a fork with `source: npm`, which must switch to
`tag`.

## kit v1 update: a sync release builds the merge (schema 1, unchanged)

The release job of `fork-sync.yml` built the trunk as it was when the sync run started, before
the merge. It published a copy of the previous release. The sync now outputs the commit that
it pushed, and the release builds that commit. Both release callers now share one
concurrency group, so two releases never run at once.

An existing fork must update its two callers from the templates:

1. In `fork-sync.yml`, give the `release` job `with: { ref: ${{ needs.sync.outputs.sha }} }` and
   the `fork-release` concurrency group.
2. In `fork-release.yml`, add the `fork-release` concurrency group.

## kit v1 update: upstream tags apart, stamps checked (schema 1, unchanged)

- The workflows fetch upstream's tags into `refs/upstream-tags/`, apart from the fork's own
  release tags. An upstream tag named like a fork release no longer breaks every fetch.
- The base is the bare-version upstream tag nearest to the trunk's head, and the higher
  version on a tie. A high version tagged on an old commit can no longer become the base.
- The publish job checks that each stamped file still matches its filter after the build.

No change in the forks is needed.

## kit v1 update: PR check and exempt admins (schema 1, unchanged)

The new reusable `check.yml` runs the fork's verify command on every PR into the trunk. A new
ruleset requires its job to pass. The trunk and tag rulesets now exempt admins, so a green PR
merges without the bypass checkbox.

An existing fork must do this:

1. Add `.github/workflows/fork-check.yml` from `skills/fork/templates/fork-check.yml`.
2. Set `bypass_mode` to `exempt` in the trunk and tag rulesets.
3. Create the "trunk: PRs pass the check" ruleset with the command in
   `skills/fork/references/create.md`, step 3.

## kit v1 update: release versions follow the base (schema 1, unchanged)

A release started by hand accepts only `<base>-<suffix>.<N>` for the trunk's own upstream
base. Any workflow in the fork with write access to Actions can start the release workflow,
and a made-up version such as `99.0.0` sorted above every later release.

No change in the forks is needed.

## kit v1 update: no unreleased upstream code in a release (schema 1, unchanged)

A release builds the trunk and labels it with the newest upstream release in it. If the trunk
also held upstream commits after that release, the release shipped them under the old
label. For the `release`, `tag` and `npm` sources, the release now stops with an error in that
case, through `bin/check-released`.

No change in the forks is needed. A fork whose trunk holds such commits must reset its trunk
to an upstream release plus its own patches.

## kit v1 update: whole-.github isolation (schema 1, unchanged)

`bin/merge-upstream` listed upstream's CI files by name, and git quotes names with
non-ASCII bytes, quotes, backslashes or tabs. Such a file was not removed. An upstream
workflow was able to land on the trunk and read `SYNC_TOKEN` from the `fork-sync` environment. Now:

- `bin/merge-upstream` removes upstream's whole `.github` and restores only the trunk's own
  `.github/fork.yml` and `.github/workflows/fork-*`. Nothing is listed by name.
  `bin/strip-upstream-ci` removes the whole `.github` from `sync/<ref>` branches.
- The sync's push job keeps no credentials in `.git/config`. Each push gets the token from a
  credential helper.
- A first release lists the fork's patches on top of the upstream base.
- If a release name belonged to a deleted immutable release, the publish job tries the next
  N. GitHub locks such a name for good.

No change in the forks is needed. Limit the token to the forks: "Only select repositories",
with each fork, not the kit.

## kit v1 update: fork rulesets (schema 1, unchanged)

The release's publish job now creates tags and releases with `SYNC_TOKEN` from the
`fork-sync` environment, not with the job's `GITHUB_TOKEN`. Rulesets in the fork then let
only admins push to the trunk or create tags, so no other workflow can do either.

An existing fork must do this, in order:

1. In `fork-release.yml`, set `permissions: contents: read` and pass
   `secrets: { SYNC_TOKEN: ${{ secrets.SYNC_TOKEN }} }`. In `fork-sync.yml`, do the same for
   the `release` job.
2. Create the trunk ruleset and the tag ruleset, and enable immutable releases, with the
   commands in `skills/fork/references/create.md`, step 4.

## kit v1 update: upstream CI isolation (schema 1, unchanged)

Upstream's own GitHub workflows could read `SYNC_TOKEN`: the sync pushed upstream's commits,
and GitHub ran their workflow files in the fork with its secrets. Now:

- The sync merges with `bin/merge-upstream`, which strips upstream's `.github/workflows` and
  `.github/actions` from the trunk. `sync/<ref>` branches carry a commit that removes them.
- The sync no longer pushes upstream's default branch to the fork.
- The sync's push job runs in the `fork-sync` environment. `distribute-secret.yml` writes
  `SYNC_TOKEN` there and deletes the repository-level copy.

An existing fork must do this, in order, before the next sync:

1. Add Environments (read and write) to the kit's `SYNC_TOKEN` token.
2. On the trunk, remove every file under `.github/workflows` and `.github/actions` that is not
   a `fork-*` file.
3. Delete the fork's copy of upstream's default branch.
4. Create the `fork-sync` environment, with a deployment branch policy for the trunk only.
5. Run `distribute-secret.yml` for the fork.
6. In `fork-sync.yml`, replace `secrets: inherit` with
   `secrets: { SYNC_TOKEN: ${{ secrets.SYNC_TOKEN }} }`. The token reaches the push job only
   when the caller passes it by name.

## kit v1, schema 1

The first release. Nothing to upgrade from.
