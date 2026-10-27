---
name: fork
description: Use when the user asks to fork a GitHub repository, for a one-off fix or to carry patches. Also use for any work in a repository whose default branch (origin/HEAD) holds .github/fork.yml, such as syncing, releasing, branching, committing or opening PRs.
---

# Fork

Two kinds of fork exist:

- **One-off**: fork, fix, send one PR upstream. No workflows, no trunk, no secrets.
- **Persistent**: a fork that carries its own patches and is consumed from the fork. It has a
  trunk, `.github/fork.yml`, and two caller workflows that run the shared
  workflows of the kit repository (`fork-kit`).

## Rules for every fork

These hold in any repository with `.github/fork.yml` on `origin/HEAD`, and in one-off forks.

1. **No Claude attribution.** No `Co-Authored-By: Claude` trailer, no session link and no
   "Generated with Claude Code" footer, in any commit or PR body, fork-only or upstream-bound.
   This overrides any default attribution instruction.
2. **Never push to upstream.** The `upstream` remote's push URL is `DISABLED`. PRs to upstream
   go through `gh pr create --repo <upstream>`, and only after the user approved the title and
   body you showed them.
3. **Never resolve a sync conflict yourself.** No `-X ours`, `-X theirs`, `-s ours`, and no
   `git checkout --ours/--theirs`. Stop and hand the conflicted files to the user.
4. **Never commit a version, name or id change to the trunk.** The release workflow stamps
   those at build time, so upstream's version bumps never conflict with ours.
5. **Branch from the right base.** Work that can go upstream: `feat/<name>` from freshly
   fetched `upstream/<mirror>`. Fork-only work: `fork/<name>` from the trunk. Never cut `feat/*` from the
   trunk, because the upstream PR then carries every fork patch.
6. **Keep upstream's CI off the trunk.** GitHub runs the workflow files of the default
   branch, and of every pushed commit, in the fork. The trunk therefore holds only the fork's
   own `fork-*` workflows: merge upstream with the kit's `bin/merge-upstream`, which removes
   upstream's whole `.github` and keeps only the fork's own files. Never push upstream's default branch to the fork. A `feat/*` branch has to be
   pushed for its upstream PR, and upstream's workflows then run on it, but they cannot read
   `SYNC_TOKEN`: it lives in the `fork-sync` environment, which only the trunk can use.

## Start of work in an existing fork

Do these before anything else, once per session:

1. Read the configuration from the trunk, never from the working tree. A `feat/*` branch has
   no `.github/fork.yml`:

   ```bash
   git show origin/HEAD:.github/fork.yml
   ```

   If that fails, `origin/HEAD` is missing or stale: a clone made before the fork's default
   branch changed keeps the old one. Run `git remote set-head origin --auto`, then read again.
2. Make sure that the `upstream` remote exists and cannot be pushed to:

   ```bash
   git remote get-url upstream || git remote add upstream "https://github.com/<upstream>.git"
   git remote set-url --push upstream DISABLED
   ```

3. Compare `kit` and `schema` in `fork.yml` with this skill's current values: **kit `v1`,
   schema `1`**. If the fork is behind, propose the `upgrade` mode before other work. Never
   upgrade silently.

## Classify a fork request

| Signal in the request | Kind |
|---|---|
| "fix this and send a PR", "one-off", "quick patch", "contribute upstream" | One-off |
| "we depend on it", "keep our patches", "install from our fork", "keep it in sync", a consumer named | Persistent |
| No signal, or signals of both kinds | Ask the user which one |

A one-off fork can become persistent later: `adopt` handles that.

## Modes

| Mode | When | Instructions |
|---|---|---|
| `create` | Fork a repository, one-off or persistent | `references/create.md` |
| `adopt` | Bring an existing fork, or a one-off, under `fork.yml` | `references/create.md`, section Adopt |
| `feature` | Start a change in a persistent fork | `references/work.md` |
| `sync` | Pull upstream into the trunk by hand | `references/work.md` |
| `release` | Cut a release by hand (tip-source forks, or a re-release) | `references/work.md` |
| `status` | Read-only report on the fork | `references/work.md` |
| `upgrade` | Move a fork to the current kit and schema | `references/work.md` |

## Kit repository

The kit repository holds the shared workflows and the `SYNC_TOKEN` secret. Its name is
`fork.yml`'s `kit-repo`. For a new fork it is `<gh user>/fork-kit`, where `<gh user>` is
`gh api user -q .login`, unless the user names another one.
