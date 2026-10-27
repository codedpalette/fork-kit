# Changelog

The skill's `upgrade` mode reads this file. Each entry names the kit version, the `fork.yml`
schema version and what a fork must change.

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

## kit v1, schema 1

The first release. Nothing to upgrade from.
