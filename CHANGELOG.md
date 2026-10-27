# Changelog

The skill's `upgrade` mode reads this file. Each entry names the kit version, the `fork.yml`
schema version and what a fork must change.

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
