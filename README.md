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
| The `fork` skill | `skill/fork/` | Classifies a fork request, creates and adopts forks, guides daily work |
| Detection hook | `skill/fork/hooks/detect-fork.sh` | Tells a fresh agent session to load the skill inside a fork |
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

## Set up on a new machine

The token and the workflows live on GitHub, so a new machine needs only the skill and the hook.

1. Install `git`, `gh`, `jq` and `yq`, then run `gh auth login`.
2. Clone this repository and link the skill into Claude Code:

   ```bash
   git clone https://github.com/codedpalette/fork-kit.git ~/Projects/fork-kit
   mkdir -p ~/.claude/skills
   ln -s ~/Projects/fork-kit/skill/fork ~/.claude/skills/fork
   ```

3. Register the detection hook in `~/.claude/settings.json`. Merge this into the existing
   `hooks` object:

   ```json
   {
     "hooks": {
       "SessionStart": [
         {
           "hooks": [
             { "type": "command", "command": "$HOME/.claude/skills/fork/hooks/detect-fork.sh" }
           ]
         }
       ]
     }
   }
   ```

4. Make sure that it works. In a clone of any fork made with the kit, start a new Claude Code
   session and ask "what kind of repository is this?". The answer names the fork's trunk.

A `git pull` in `~/Projects/fork-kit` updates the skill on that machine.

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

4. Do the steps of "Set up on a new machine", with your copy's URL.

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
| `release.version-file` | File whose `.version` is the base, only for `source: tip` |
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
| Skill behavior | `skill/fork/` | On the next `git pull` of the kit on each machine |

## Security rules for the workflows

- `SYNC_TOKEN` is present only in jobs that run `git` and `gh`. The sync's `merge` job runs
  upstream's install and tests without it, and a separate `push` job holds it. A compromised
  upstream dependency therefore has no token to steal.
- The `actions/checkout` steps in jobs without the token use `persist-credentials: false`.
- Third-party actions are pinned to full commit SHAs, and Dependabot updates the pins.
- Releases use the job's own `GITHUB_TOKEN`, which expires with the job and reaches only that
  fork.

## Development

```bash
brew install bats-core shellcheck actionlint yq
bats test/
shellcheck bin/* skill/fork/hooks/*.sh
actionlint
```

The end-to-end tests run against the sandbox repositories `codedpalette/forker-demo-upstream`
and `codedpalette/forker-demo`.
