# Create and adopt

`KIT_DIR` below is the root of the fork-kit plugin: two directories above this skill's base
directory. Claude Code shows that base directory at the top of the loaded skill. The kit's
scripts are in `$KIT_DIR/bin/`.

```bash
KIT_DIR="<this skill's base directory>/../.."
```

## One-off fork

1. Fork without the upstream's other branches, and disable the upstream push URL:

   ```bash
   gh repo fork <upstream> --clone --default-branch-only
   cd <name>
   git remote set-url --push upstream DISABLED
   ```

2. Cut `fix/<name>` from the upstream default branch, make the change, and commit it with no
   attribution.
3. Push the branch to `origin`. Show the user the PR title and body. Open the PR with
   `gh pr create --repo <upstream>` only after the user approves them.

Nothing else: no `fork.yml`, no workflows, no secrets.

## Persistent fork

### 1. Gather the answers

The owner is `gh api user -q .login` unless the user names another owner. Do not ask for it.

Detect how upstream marks a release, in this order, and stop at the first hit:

```bash
"$KIT_DIR/bin/upstream-release" <upstream> release            # GitHub Releases
"$KIT_DIR/bin/upstream-release" <upstream> tag                # semver tags
"$KIT_DIR/bin/upstream-release" <upstream> npm <npm-package>  # npm, if package.json names one
```

Exit code 3 means that the source has no release. If all three find nothing, tell the user
that upstream has no clear release cut. Then ask what to do:

- Follow the upstream tip. Sync merges the tip into the trunk. Nothing releases automatically.
  The user cuts releases with the `release` mode. Without a version file, a release is
  versioned by the date of the newest upstream commit, for example `2026.1.5-patched.1`.
- Stop. The user forks again after upstream starts to release.

If the project has no `package.json`, warn the user before the questions. The kit sets up
only Node. In another language, `verify` and `build` run with the toolchains that the
GitHub runner image preinstalls, such as Python, Go, Rust or Java. Those versions are not pinned, and each GitHub image update can change them. Ask
whether to continue on those terms.

Then ask the open questions, each with its proposed default:

| Question | Default |
|---|---|
| Trunk branch name | `patched`, or the organization name for an organization fork |
| Release outputs | `assets` for files that a tool downloads from a GitHub Release, or `commit` for files that a git-URL install reads from the tag. Propose from how the project is consumed. |
| Fields to stamp | Version fields in the files that ship, as `jq` filters on `$version` |
| Release suffix | `patched` |
| Verify command | From `package.json` scripts, for example `npm ci && npm test && npm run build` |
| Build command | The build part of the verify command, for example `npm run build` |
| Node version | From `.nvmrc`, `.node-version` or `engines`, else the current LTS. For a range such as `>=22.12.0`, the major version of its lower bound: `22` |
| Install text for `FORK.md` | How the consumer installs the fork's releases, from how the project is consumed |

### 2. Fork and set up the branches

```bash
gh repo fork <upstream> --clone --default-branch-only   # add --org <owner> for an organization
cd <name>
git remote set-url --push upstream DISABLED
git fetch -q upstream --tags
git switch -c <trunk> --no-track <start>
git rm -r -q --ignore-unmatch .github
git commit -q -m "chore: remove upstream's .github"
git push -u origin <trunk>
gh repo edit --default-branch <trunk>
git remote set-head origin --auto
```

`<start>` is the upstream release that step 1 detected, as a tag: `refs/tags/<release>`. If
no such tag exists, as for an npm version, use `refs/tags/v<release>`. Only for the `tip`
source, `<start>` is `upstream/<mirror>`. Never start the trunk from upstream's tip for
another source. A release builds the trunk under the release's version. If the trunk holds
newer upstream code, the release workflow stops.

If the fork already exists, the same `gh repo fork` command clones it. With `--clone`, gh adds
the `upstream` remote itself.

The trunk's first commit removes upstream's whole `.github`, the same rule that
`bin/merge-upstream` applies. A new fork can have Actions turned on, so upstream's workflows
must never reach a branch that you push.

Then stop and ask the user to delete the fork's copy of upstream's default branch, because
the agent's permissions block branch deletion. It holds upstream's workflows while Actions
is on. Give the user this command, and wait for the answer:

```bash
git -C <clone path> push origin --delete <mirror>
```

`<mirror>` is upstream's default branch, the `mirror` key of `fork.yml`. The fork does not
keep a copy of it, because a push of upstream's branch runs upstream's workflows in the fork.
`feat/*` branches start from `upstream/<mirror>` instead.

### 3. Add the tooling as a setup PR

1. Cut `setup/fork` from the trunk.
2. Render the templates from `templates/` into the fork. Fill in every `{{...}}` value. For
   the `tip` source, remove each line that ends in `# tip:remove`. For other sources, remove
   only the marker comments:
   - `templates/fork.yml` to `.github/fork.yml`
   - `templates/fork-sync.yml` to `.github/workflows/fork-sync.yml`
   - `templates/fork-release.yml` to `.github/workflows/fork-release.yml`
   - `templates/FORK.md` to `FORK.md`

   Values that need a format:
   - `{{stamp}}`: one line per file, indented by four spaces, with the filter in single
     quotes: `    manifest.json: '.version = $version'`.
   - `{{version_file}}`: `package.json`, also for sources other than `tip`.
   - `{{commit}}` and `{{assets}}`: a comma-separated list, or nothing for an empty list.
   - `{{install}}`: a `## Install` heading, then the install text.
3. Commit `chore: set up fork tooling` with no attribution. Push the branch and open a PR to
   the trunk in the fork (`--repo <owner>/<name>`), never upstream.

Feature work, such as the user's first patches, waits until the setup PR is merged. Before
that, `origin/HEAD` has no `fork.yml`. Open patch PRs after the merge, and tell the user to
merge them only after step 4: a push to the trunk starts a release, and the release fails
without the token.

### 4. Set up the GitHub side

Do this only after the user merged the setup PR, because step 5 runs the workflows that the
setup PR adds.

```bash
gh api -X PUT repos/<owner>/<name>/environments/fork-sync \
  --input - <<<'{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}'
gh api -X POST repos/<owner>/<name>/environments/fork-sync/deployment-branch-policies \
  -f name=<trunk> -f type=branch
gh api -X PUT repos/<owner>/<name>/actions/permissions -F enabled=true -f allowed_actions=all
gh api -X PUT repos/<owner>/<name>/actions/permissions/workflow \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true
gh api -X POST repos/<owner>/<name>/rulesets --input - <<'JSON'
{"name": "trunk: only admins push", "target": "branch", "enforcement": "active",
 "conditions": {"ref_name": {"include": ["refs/heads/<trunk>"], "exclude": []}},
 "bypass_actors": [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}],
 "rules": [{"type": "deletion"}, {"type": "non_fast_forward"}, {"type": "update"}]}
JSON
gh api -X POST repos/<owner>/<name>/rulesets --input - <<'JSON'
{"name": "tags: only admins create, move or delete", "target": "tag", "enforcement": "active",
 "conditions": {"ref_name": {"include": ["~ALL"], "exclude": []}},
 "bypass_actors": [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}],
 "rules": [{"type": "creation"}, {"type": "update"}, {"type": "deletion"}]}
JSON
gh api -X PUT repos/<owner>/<name>/immutable-releases
```

Then the token. The kit's `SYNC_TOKEN` token reaches only the repositories on its list, and
GitHub has no API to change that list. So stop and tell the user, in these words:

> Add `<owner>/<name>` to the kit's token: open
> <https://github.com/settings/personal-access-tokens>, open the token stored as `SYNC_TOKEN`
> in `<kit-repo>`, choose "Only select repositories", add `<owner>/<name>`, and save. Tell me
> when it is done.

Wait for the user's answer, then copy the token into the fork:

```bash
gh workflow run distribute-secret.yml -R <kit-repo> -f repo=<owner>/<name>
```

If the distribute run fails with a permissions error, the fork is not on the token's list
yet. Repeat the instruction above.

The first two commands create the `fork-sync` environment, which only the trunk can use. The
token lives there, so no workflow on another branch can read it. The fourth command lets the
sync workflow open its conflict PRs.

The two rulesets and immutable releases stop upstream's workflows that run on a pushed
`feat/*` branch. Such a workflow can raise its own `GITHUB_TOKEN` to write access, but only
admins can push to the trunk or create tags, and the token's owner is an admin. Immutable
releases lock each published release's assets and tag. A deleted release's tag name can
never be used again.

Rulesets on a private repository need a paid GitHub plan. If the fork is private and the
account has no such plan, tell the user that this protection is missing. Make sure that the secret arrived:
`gh secret list -R <owner>/<name> --env fork-sync` lists `SYNC_TOKEN`.

### 5. Finish

Dispatch the first sync and the first release, one after the other, and report both:

```bash
gh workflow run fork-sync.yml -R <owner>/<name>
gh workflow run fork-release.yml -R <owner>/<name>
```

If the trunk already holds the newest upstream release, the sync merges nothing. Then the
first release comes from the dispatch. If the user's patch PRs are waiting, skip the release
dispatch, because merging them starts the release.

## Adopt

Adopt brings an existing fork under `fork.yml`. Keep its branch names: `fork.yml` records the
names that the fork already uses.

1. Read what exists: the branches, the workflows on the trunk, how the fork releases today,
   and the secrets (`gh secret list`).
2. Ask only what the existing setup does not answer. Run the release detection above. For a
   project without `package.json`, give the Node-only warning above.
3. Render the templates on a `setup/fork` branch from the trunk. In the same PR, delete the
   fork's old sync and release workflows that the callers replace, and remove upstream's whole
   `.github`: every file in it except `.github/fork.yml` and `.github/workflows/fork-*`.
4. After the user merges the PR, delete the fork's copy of upstream's default branch
   (`git push origin --delete <mirror>`), then do step 4 of the persistent fork, including
   the instruction to add the fork to the kit's token. The
   distribute workflow moves an old repository-level `SYNC_TOKEN` into the environment.
5. Disable the upstream push URL and run `git remote set-head origin --auto`.
6. After the user merges the PR, dispatch one sync and one release, and report both.
