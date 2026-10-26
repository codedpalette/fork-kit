# Create and adopt

`KIT_DIR` below is the kit repository clone that holds this skill:

```bash
KIT_DIR="$(cd "$(dirname "$(readlink -f ~/.claude/skills/fork/SKILL.md)")/../.." && pwd)"
```

## One-off fork

1. Fork without the upstream's other branches, and disable the upstream push URL:

   ```bash
   gh repo fork <upstream> --clone --remote --default-branch-only
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
  The user cuts releases with the `release` mode.
- Stop. The user forks again after upstream starts to release.

If the project has no `package.json`, warn the user before the questions. The kit sets up
only Node. In another language, `verify` and `build` run with the toolchains that the
GitHub runner image preinstalls, such as Python, Go, Rust or Java. Those versions are not pinned, and each GitHub image update can change them. Ask
whether to continue on those terms.

Then ask the open questions, each with its proposed default:

| Question | Default |
|---|---|
| Trunk branch name | `patched`, or the organization name for an organization fork |
| Sync cadence | Hourly, cron `17 * * * *` |
| Release outputs | `assets` for files that a tool downloads from a GitHub Release, or `commit` for files that a git-URL install reads from the tag. Propose from how the project is consumed. |
| Fields to stamp | Version fields in the files that ship, as `jq` filters on `$version` |
| Release suffix | `patched` |
| Verify command | From `package.json` scripts, for example `npm ci && npm test && npm run build` |
| Node version | From `.nvmrc`, `.node-version` or `engines`, else the current LTS |
| Upstream workflows to disable | List them with `gh workflow list --all -R <fork>`. Propose the ones that publish, deploy, open PRs or comment. |

### 2. Fork and set up the branches

```bash
gh repo fork <upstream> --clone --remote --default-branch-only   # add --org <owner> for an organization
cd <name>
git remote set-url --push upstream DISABLED
git switch -c <trunk> <release ref, or upstream/<mirror> for the tip>
git push -u origin <trunk>
gh repo edit --default-branch <trunk>
git remote set-head origin --auto
```

The mirror is the upstream default branch name, and it already exists in the fork.

### 3. Add the tooling as a setup PR

1. Cut `setup/fork` from the trunk.
2. Render the templates from `templates/` into the fork. Fill in every `{{...}}` value. For
   the `tip` source, remove each line that ends in `# tip:remove`. For other sources, remove
   only the marker comments:
   - `templates/fork.yml` to `.github/fork.yml`
   - `templates/fork-sync.yml` to `.github/workflows/fork-sync.yml`
   - `templates/fork-release.yml` to `.github/workflows/fork-release.yml`
   - `templates/FORK.md` to `FORK.md`
3. Commit `chore: set up fork tooling` with no attribution. Push the branch and open a PR to
   the trunk in the fork (`--repo <owner>/<name>`), never upstream.

### 4. Set up the GitHub side

```bash
gh api -X PUT repos/<owner>/<name>/actions/permissions -F enabled=true -f allowed_actions=all
gh api -X PUT repos/<owner>/<name>/actions/permissions/workflow \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true
gh workflow disable <workflow> -R <owner>/<name>      # once per approved upstream workflow
gh workflow run distribute-secret.yml -R <kit-repo> -f repo=<owner>/<name>
```

The second command lets the sync workflow open its conflict PRs. Make sure that the secret arrived: `gh secret list -R <owner>/<name>` lists `SYNC_TOKEN`.

### 5. Finish

Tell the user to merge the setup PR. After the merge, dispatch the first sync and report the
result:

```bash
gh workflow run fork-sync.yml -R <owner>/<name>
```

## Adopt

Adopt brings an existing fork under `fork.yml`. Keep its branch names: `fork.yml` records the
names that the fork already uses.

1. Read what exists: the branches, the workflows on the trunk, how the fork releases today,
   and the secrets (`gh secret list`).
2. Ask only what the existing setup does not answer. Run the release detection above. For a
   project without `package.json`, give the Node-only warning above.
3. Render the templates on a `setup/fork` branch from the trunk. In the same PR, delete the
   fork's old sync and release workflows that the callers replace.
4. Do step 4 of the persistent fork. The distribute workflow overwrites an old `SYNC_TOKEN`.
5. Disable the upstream push URL and run `git remote set-head origin --auto`.
6. After the user merges the PR, dispatch one sync and one release, and report both.
