# fork-kit

Shared machinery for keeping GitHub forks of open-source projects in sync, and a Claude Code
skill that drives it.

A fork made with this kit has two kinds of branch: a mirror that always equals upstream, and a
trunk that holds upstream plus our patches. Changes for upstream branch from the mirror, so
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

Status: the skill, the hook, the version scripts and the secret distribution are in place. The reusable sync and release workflows come next. Until then, forks
cannot call them yet.

## Is it safe to keep this repository public?

Yes. Nothing secret is in the files. `SYNC_TOKEN` lives in this repository's Actions secrets,
which only collaborators with write access can use:

- GitHub does not pass secrets to workflows that run for pull requests from forks of this
  repository. No workflow here uses `pull_request_target`, the trigger that passes them.
- `distribute-secret.yml` runs only on `workflow_dispatch`, which needs write access to this
  repository. It refuses any target outside the owner's account.
- Every fork calls the workflows at `@v1`. Only accounts with write access can move that tag.
  Keep yourself the only one with write access.

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
   - Repository access: All repositories
   - Repository permissions: Contents, Workflows and Secrets set to read and write. Nothing else.
3. Store it in your copy of the kit. Paste the token at the prompt, not on the command line,
   so that it stays out of your shell history:

   ```bash
   gh secret set SYNC_TOKEN -R <your login>/fork-kit
   ```

4. Do the steps of "Set up on a machine", with `<your login>/fork-kit` as the marketplace.
   The skill finds your copy of the kit through your GitHub login.

The token needs Workflows write because a sync pushes upstream's changes to
`.github/workflows/`, which the built-in `GITHUB_TOKEN` cannot push. It needs Secrets write
only for the distribution workflow.

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
| `kit` | Major version of the kit workflows that the fork calls, for example `v1` |
| `kit-repo` | The kit repository, for example `codedpalette/fork-kit` |
| `upstream` | `owner/name` of the upstream repository |
| `mirror` | Upstream's default branch, mirrored as is |
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

- `SYNC_TOKEN` is present only in jobs that run `git` and `gh`. The sync's `merge` job runs
  upstream's install and tests without it, and a separate `push` job holds it. A compromised
  upstream dependency therefore has no token to steal.
- The `actions/checkout` steps in jobs without the token use `persist-credentials: false`.
- Third-party actions are pinned to full commit SHAs, and Dependabot updates the pins.
- `test/check-isolation` tests these rules on every push, and the headers of `sync.yml` and
  `release.yml` explain them to anyone who edits them.
- Releases use the job's own `GITHUB_TOKEN`, which expires with the job and reaches only that
  fork. Its `build` job runs upstream's build with read access only and hands the files over
  as an artifact. A separate `publish` job holds write access and runs no upstream code,
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
