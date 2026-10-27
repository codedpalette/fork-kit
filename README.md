# fork-kit

Shared machinery for keeping GitHub forks of open-source projects in sync, and a Claude Code
skill that drives it.

A fork made with this kit has a trunk that holds upstream plus our patches, without
upstream's CI. Changes for upstream branch from upstream's default branch, so
their PRs stay clean. Changes that stay in the fork branch from the trunk. A scheduled workflow
merges each upstream release into the trunk, and a release workflow publishes the fork's own
versioned releases.

| Part | Where | Job |
|---|---|---|
| The `fork` skill | `skills/fork/` | Classifies a fork request, creates and adopts forks, guides daily work |
| Detection hook | `hooks/hooks.json`, `scripts/detect-fork.sh` | Tells a fresh agent session to load the skill inside a fork |
| Reusable workflows | `.github/workflows/sync.yml`, `release.yml` | Sync upstream into the trunk, publish releases |
| Secret distribution | `.github/workflows/distribute-secret.yml` | Copies `SYNC_TOKEN` from this repository into each fork |
| Version scripts | `bin/` | Find upstream's release, the base version and the next fork version |

## Set up on a machine

The repository is a Claude Code plugin and its own marketplace. The token and the workflows
live on GitHub, so a machine needs only the plugin.

1. Install `git`, `gh`, `jq` and `yq`, then run `gh auth login`.
2. Install the plugin:

   ```bash
   claude plugin marketplace add codedpalette/fork-kit
   claude plugin install fork-kit@fork-kit
   ```

3. Turn on auto-update for the marketplace: in Claude Code, open `/plugin`, then
   Marketplaces, then `fork-kit`, then "Enable auto-update". Claude Code turns it off by
   default for marketplaces outside Anthropic.
4. Make sure that it works. In a clone of any fork made with the kit, start a new Claude Code
   session and ask "what kind of repository is this?". The answer names the fork's trunk.

The plugin has the skill `fork-kit:fork` and a `SessionStart` hook. In a repository with
`.github/fork.yml` on its default branch, the hook tells a fresh session to load the skill.

### Updates

`plugin.json` has no `version` field, so every commit on `main` is a new plugin version. With
auto-update on, each machine downloads it in the background, up to 10 minutes after the first
message of a session. `/reload-plugins` or a new session loads it. Without auto-update, run
`claude plugin update fork-kit@fork-kit`.

Because every commit on `main` reaches every machine, change the skill on a branch and merge
it when it works.

## Set up from scratch for another GitHub account

1. Copy this repository into your account as a public repository named `fork-kit`. The skill
   looks for `<your login>/fork-kit` by default.
2. Create a fine-grained personal access token at
   <https://github.com/settings/personal-access-tokens/new>:
   - Resource owner: your account
   - Expiration: the longest that the form offers
   - Repository access: Only select repositories, with every fork made with the kit. Not the
     kit itself, and nothing else.
   - Repository permissions: Contents, Workflows, Secrets and Environments set to read and
     write. Nothing else.
3. Store it in your copy of the kit. Paste the token at the prompt, not on the command line,
   so that it stays out of your shell history:

   ```bash
   gh secret set SYNC_TOKEN -R <your login>/fork-kit
   ```

4. Do the steps of "Set up on a machine", with `<your login>/fork-kit` as the marketplace.
   The skill finds your copy of the kit through your GitHub login.

Use your own copy rather than calling `codedpalette/fork-kit` from your forks. The owner of a
kit can move its `v1` tag and change its `main`. Every fork that calls the kit runs that code
in the job that holds the fork's `SYNC_TOKEN`. Every machine with the plugin and auto-update
runs that code too, in Claude Code sessions. If you call someone else's kit anyway, set
`kit` to a full commit SHA, and install the plugin without auto-update.

The token needs Workflows write because the fork's own `.github/workflows` files change with
each kit update, and the built-in `GITHUB_TOKEN` cannot push those. It needs Secrets and
Environments write only for the distribution workflow.

Keep the token to the forks only. A leaked token then reaches nothing but the forks: not
your other repositories, and not the kit, whose `main` and `v1` reach every machine and
every fork. The cost is one manual step per new fork, because GitHub has no API to change a
token's repositories. The skill tells you at the right moment to add the fork to the token.

## Rotate the token

GitHub emails you 7 days before the token expires. Then regenerate it at
<https://github.com/settings/personal-access-tokens>. Store the new value with
`gh secret set SYNC_TOKEN -R <kit repo>`, then copy it into every fork:

```bash
gh workflow run distribute-secret.yml -R <kit repo> -f repo=all
```

## fork.yml

Each persistent fork holds `.github/fork.yml` on its trunk. Schema 1:

| Key | Meaning |
|---|---|
| `schema` | Version of this contract. For a fork that is behind, the skill proposes an upgrade. |
| `kit` | Version tag of the kit, for example `v1`, or a full commit SHA. Branch names are refused, so a branch cannot stand in for the tag. |
| `kit-repo` | The kit repository, for example `codedpalette/fork-kit` |
| `upstream` | `owner/name` of the upstream repository |
| `mirror` | Upstream's default branch. The fork keeps no copy of it. |
| `trunk` | The fork's default branch: upstream plus the fork's patches |
| `node` | Node version for verify and build |
| `sync.source` | How upstream marks a release: `release`, `tag`, `npm` or `tip`. With `tip`, sync merges the upstream branch and nothing releases automatically. |
| `sync.npm-package` | Package name, only for `source: npm` |
| `sync.verify` | Command that must pass before a sync pushes |
| `release.suffix` | Release version is `<upstream base>-<suffix>.<N>` |
| `release.build` | Command that builds the files to release |
| `release.version-file` | File whose `.version` is the base, only for `source: tip`. Without that file or field, the base is the UTC date of the newest upstream commit in the trunk, as `YYYY.M.D` (for example `2026.1.5-patched.1`). |
| `release.stamp` | Map of file to `jq` filter, applied at build time and never committed. `$version` holds the release version. |
| `release.assets` | Files attached to the GitHub Release, for tools that download release assets |
| `release.commit` | Paths force-added into a commit that is pushed only as the release tag, for git-URL installs |

## Limits

The workflows set up only Node. For a project in another language, `verify` and `build` run
with the toolchains that the GitHub runner image preinstalls, at unpinned versions. The skill
warns about this before it creates or adopts such a fork.

## How changes reach the forks

The forks call the workflows at `@v1`, a tag that moves.

| Change | Where | Reaches the forks |
|---|---|---|
| Fix inside a workflow, same inputs | Commit here, move `v1` | On the next run of every fork |
| New `fork.yml` key with a default | Commit here, move `v1`, note it in `CHANGELOG.md` | The same. A fork opts in by editing its `fork.yml`. |
| Breaking change | New `v2` tag, new templates, `CHANGELOG.md` | When the skill's `upgrade` mode runs in that fork |
| Skill or hook | `skills/fork/`, `scripts/` | Through plugin auto-update, on every machine |

## Security rules for the workflows

- Upstream's own GitHub workflows never run with the fork's secrets. GitHub runs the workflow
  files of the default branch and of every pushed commit, so the trunk holds only the fork's
  `fork-*` workflows: `bin/merge-upstream` removes upstream's whole `.github` from every merge
  and restores only the fork's own files, `bin/strip-upstream-ci` removes it from `sync/<ref>`
  branches, and upstream's default branch is never pushed to the fork.
- `SYNC_TOKEN` lives in each fork's `fork-sync` environment, which only the trunk can use, so
  a workflow on any other branch cannot read it.
- Upstream's workflows still run on `feat/*` branches pushed for upstream PRs, and a workflow
  can raise its own `GITHUB_TOKEN` to write access. So in each fork, rulesets let only admins
  push to the trunk or create tags, and immutable releases lock each release's assets.
  Releases are published with `SYNC_TOKEN`, whose owner is an admin.
- `SYNC_TOKEN` is present only in jobs that run `git` and `gh`. The sync's `merge` job runs
  upstream's install and tests without it, and a separate `push` job holds it. A compromised
  upstream dependency therefore has no token to steal.
- The `actions/checkout` steps in jobs without the token use `persist-credentials: false`.
- Third-party actions are pinned to full commit SHAs, and Dependabot updates the pins.
- `test/check-isolation` tests these rules on every push, and the headers of `sync.yml` and
  `release.yml` explain them to anyone who edits them.
- The release's `build` job runs upstream's build with read access only and hands the files
  over as an artifact. A separate `publish` job holds the token and runs no upstream code,
  because a step can plant a fake `gh` or environment variables for later steps of its job.

## Development

```bash
brew install bats-core shellcheck actionlint yq
bats test/
shellcheck bin/* scripts/*.sh test/check-isolation
actionlint
```

There are no end-to-end tests. After a change to a workflow, push it to `main`, dispatch a
sync and a release in one real fork whose callers point at `@main`, and only then move `v1`.
