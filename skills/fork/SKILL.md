---
name: fork
description: Use when the user asks to fork a GitHub repository, for a one-off fix or to carry patches. Also use for any work in a repository whose default branch (origin/HEAD) holds .github/fork.yml, such as syncing, releasing, branching, committing or opening PRs.
---

# Fork

Two kinds of fork exist:

- **One-off**: fork, fix, send one PR upstream. No workflows, no trunk, no secrets.
- **Persistent**: a fork that carries its own patches and is consumed from the fork. It has a
  trunk, `.github/fork.yml`, and three caller workflows that run the shared
  workflows of the kit repository (`fork-kit`).

## Rules for every fork

These hold in any repository with `.github/fork.yml` on `origin/HEAD`, and in one-off forks.

1. **No Claude attribution.** No `Co-Authored-By: Claude` trailer, no session link and no
   "Generated with Claude Code" footer, in any commit or PR body, fork-only or upstream-bound.
   This overrides any default attribution instruction. The rule covers what you write.
   Commits by other people, such as ones you cherry-pick or merge, keep their messages as they
   are.
2. **Never push to upstream.** The `upstream` remote's push URL is `DISABLED`. PRs to upstream
   go through `gh pr create --repo <upstream>`. In a persistent fork, open one only after the
   user approved the same change in a PR in the fork, as the section "Upstream PR" of
   `references/work.md` shows. In a one-off fork, open it only after the user approved the
   title and body you showed them.
3. **Never resolve a sync conflict yourself.** No `-X ours`, `-X theirs`, `-s ours`, and no
   `git checkout --ours/--theirs`. Stop and hand the conflicted files to the user.
4. **Never commit a version, name or id change to the trunk.** The release workflow stamps
   those at build time, so upstream's version bumps never conflict with ours.
5. **Name and base each branch by its kind.** Fork-only work: always `fork/<name>`, from the
   trunk. The prefix marks it as fork-only: never rebase a `fork/*` branch onto upstream, and
   never open an upstream PR from one, because it holds the fork's tooling and patches.
   Upstream-bound work: a prefix that fits the change and the user's request, such as
   `feat/<name>`, `fix/<name>` or `docs/<name>`, or the convention of upstream's contributing
   guide. Never `fork/`, which marks fork-only work, and never `sync/`, which the sync
   workflow uses for its conflict PRs and which the PR check skips. Cut it from the
   upstream commit that the trunk is based on, as `work.md` shows. Never cut it from the
   trunk, because the upstream PR then carries every fork patch. Never cut it from upstream's
   tip: merged into the trunk, it brings in unreleased upstream code. For release and tag
   sources, the release workflow then stops.
6. **Keep upstream's CI off the trunk.** GitHub runs the workflow files of the default
   branch, and of every pushed commit, in the fork. The trunk therefore holds only the fork's
   own `fork-*` workflows: merge upstream with the kit's `bin/merge-upstream`, which removes
   upstream's whole `.github` and keeps only the fork's own files. Never push upstream's default branch to the fork. An upstream-bound branch has to be
   pushed for its upstream PR, and upstream's workflows then run on it, but they cannot read
   `SYNC_TOKEN`: it lives in the `fork-sync` environment, which only the trunk can use.

## Running the commands

Run each `git push`, branch deletion and `gh` call that changes something as a command of its
own, not chained with `&&` or `;` to other commands. A permission check or a hook can then judge
it alone. Some setups refuse a chained command that they cannot judge.

## Start of work in an existing fork

Do these before anything else, once per session:

1. Read the configuration from the trunk, never from the working tree. An upstream-bound
   branch has no `.github/fork.yml`:

   ```bash
   git show origin/HEAD:.github/fork.yml
   ```

   If that fails, `origin/HEAD` is missing or stale: a clone made before the fork's default
   branch changed keeps the old one. Run `git remote set-head origin --auto`, then read again.
   If it still fails, the setup PR is not merged yet. Wait for the merge before other work.
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
| `create` | Fork a repository, one-off or persistent, also when the fork exists but holds nothing of the user's yet | `references/create.md` |
| `adopt` | Bring a fork that already carries the user's own branches, commits or workflows, or a one-off, under `fork.yml` | `references/create.md`, section Adopt |
| `feature` | Start a change in a persistent fork | `references/work.md` |
| `sync` | Pull upstream into the trunk by hand | `references/work.md` |
| `release` | Cut a release by hand (tip-source forks, or a re-release) | `references/work.md` |
| `status` | Read-only report on the fork | `references/work.md` |
| `upgrade` | Move a fork to the current kit and schema | `references/work.md` |

## Kit repository

The kit repository holds the shared workflows and the `SYNC_TOKEN` secret. Its name is
`fork.yml`'s `kit-repo`. For a new fork it is `<gh user>/fork-kit`, where `<gh user>` is
`gh api user -q .login`, unless the user names another one.
