# Changelog

The skill's `upgrade` mode reads this file. Each entry names the kit version, the `fork.yml`
schema version and what a fork must change.

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
