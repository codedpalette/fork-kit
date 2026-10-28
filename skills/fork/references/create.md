# Create and adopt

`KIT_DIR` below is the root of the fork-kit plugin: two directories above this skill's base
directory. Claude Code shows that base directory at the top of the loaded skill. The kit's
scripts are in `$KIT_DIR/bin/`.

```bash
KIT_DIR="<this skill's base directory>/../.."
```

## One-off fork

1. Fork without the upstream's other branches, and disable the upstream push URL. `<owner>` is
   `gh api user -q .login`:

   ```bash
   gh repo fork <upstream> --clone --default-branch-only
   cd <name>
   gh repo set-default <owner>/<name>
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
"$KIT_DIR/bin/upstream-release" <upstream> release   # GitHub Releases
"$KIT_DIR/bin/upstream-release" <upstream> tag       # semver tags such as 1.2.3 or v1.2.3
```

Exit code 3 means that the source has no release. A release tag can carry a prefix before its
version, such as `release-1.2.3` or `pkg@1.2.3`. Then `tag-prefix` in `fork.yml` is that
prefix, and the fork's versions leave it out: `1.2.3-patched.1`. Both commands then need the
prefix as a third argument. If both commands find nothing, list upstream's tags with
`git ls-remote --tags --refs https://github.com/<upstream>.git`. If the newest release tags
share a prefix before a plain version (`1.2.3` or `v1.2.3`), run both commands again with
that prefix. If a release tag does not end in a plain version, tell the user that the kit
cannot version this upstream, and stop. If nothing is found, tell the user
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
| Verify command | The commands from upstream's CI workflow for commits or PRs that install, build, lint and test the code, copied verbatim and joined with `&&`. Leave out steps that deploy, publish, upload artifacts, copy files elsewhere, install system packages, or only print reports. Take only `run:` commands, never the workflow file. Without such a workflow, take them from the README or the `package.json` scripts, for example `npm ci && npm test && npm run build` |
| Build command | The build part of the verify command, for example `npm run build` |
| Node version | From `.nvmrc`, `.node-version` or `engines`, else the current LTS. For a range such as `>=22.12.0`, the major version of its lower bound: `22` |
| Install text for `FORK.md` | How the consumer installs the fork's releases, from how the project is consumed |

### 2. Fork and set up the branches

```bash
gh repo fork <upstream> --clone --default-branch-only   # add --org <owner> for an organization
cd <name>
gh repo set-default <owner>/<name>
git remote set-url --push upstream DISABLED
git fetch -q upstream --tags
git switch -c <trunk> --no-track <start>
git rm -r -q --ignore-unmatch .github
git commit -q -m "chore: remove upstream's .github"
git push -u origin <trunk>
gh repo edit <owner>/<name> --default-branch <trunk>
git remote set-head origin --auto
```

`<start>` is the upstream release tag that step 1 detected: `refs/tags/<release>`. Only for
the `tip` source, `<start>` is `upstream/<mirror>`. Never start the trunk from upstream's tip for
another source. A release builds the trunk under the release's version. If the trunk holds
newer upstream code, the release workflow stops.

If the fork already exists, the same `gh repo fork` command clones it. Before you choose and
push the trunk, list the fork's branches with `git ls-remote --heads origin`. If a branch with
the trunk's name exists there, stop and show the user the clash and the list of branches, and
ask for another trunk name. Never force-push it. With `--clone`, gh adds
the `upstream` remote itself, and marks upstream as the clone's default repository for `gh`.
`gh repo set-default` points `gh` at the fork instead. Without it, a bare `gh repo edit` or
`gh pr create` acts on upstream. Still name the fork in every `gh` call that takes a
repository.

The trunk's first commit removes upstream's whole `.github`, the same rule that
`bin/merge-upstream` applies. A new fork can have Actions turned on, so upstream's workflows
must never reach a branch that you push.

`<mirror>` is upstream's default branch, the `mirror` key of `fork.yml`. The fork does not
keep a copy of it, because a push of upstream's branch runs upstream's workflows in the fork.
`feat/*` branches start from the upstream commit that the trunk is based on, as `work.md`
shows.

### 3. Set up the GitHub side

Do this right after step 2, so that the rulesets protect the trunk before anything else is
pushed.

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
 "bypass_actors": [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "exempt"}],
 "rules": [{"type": "deletion"}, {"type": "non_fast_forward"}, {"type": "update"}]}
JSON
gh api -X POST repos/<owner>/<name>/rulesets --input - <<'JSON'
{"name": "trunk: PRs pass the check", "target": "branch", "enforcement": "active",
 "conditions": {"ref_name": {"include": ["refs/heads/<trunk>"], "exclude": []}},
 "bypass_actors": [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}],
 "rules": [{"type": "required_status_checks", "parameters": {
   "strict_required_status_checks_policy": false,
   "required_status_checks": [{"context": "check / verify", "integration_id": 15368}]}}]}
JSON
gh api -X POST repos/<owner>/<name>/rulesets --input - <<'JSON'
{"name": "tags: only admins create, move or delete", "target": "tag", "enforcement": "active",
 "conditions": {"ref_name": {"include": ["~ALL"], "exclude": []}},
 "bypass_actors": [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "exempt"}],
 "rules": [{"type": "creation"}, {"type": "update"}, {"type": "deletion"}]}
JSON
gh api -X PUT repos/<owner>/<name>/immutable-releases
```

Then copy the token into the fork, and wait for the run to finish:

```bash
started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
gh workflow run distribute-secret.yml -R <kit-repo> -f repo=<owner>/<name>
gh run list -R <kit-repo> --workflow distribute-secret.yml -L 5 --json databaseId,createdAt \
  -q "[.[] | select(.createdAt >= \"$started\")][0].databaseId"
gh run watch <run id> -R <kit-repo> --exit-status
```

The new run takes a few seconds to appear. Until `gh run list` prints a run id, wait and run
it again. Never watch an older run: it can be an earlier failure.

The kit's `SYNC_TOKEN` token reaches only the repositories on its list, and GitHub has no API
to change that list. If the distribute run fails with a permissions error, the fork is not on
the list. Then stop and tell the user, in these words:

> Add `<owner>/<name>` to the kit's token: open
> <https://github.com/settings/personal-access-tokens>, open the token stored as `SYNC_TOKEN`
> in `<kit-repo>`, choose "Only select repositories", add `<owner>/<name>`, and save. Tell me
> when it is done.

After the user's answer, run the distribute workflow again. If the run fails for another
reason, show the user the error from `gh run view <run id> --log-failed -R <kit-repo>`, and stop.

When the run succeeds, make sure that the secret arrived:
`gh secret list -R <owner>/<name> --env fork-sync` lists `SYNC_TOKEN`.

The first two commands create the `fork-sync` environment, which only the trunk can use. The
token lives there, so no workflow on another branch can read it. The fourth command lets the
sync workflow open its conflict PRs.

The first and third rulesets, and immutable releases, stop upstream's workflows that run on a pushed
`feat/*` branch. Such a workflow can raise its own `GITHUB_TOKEN` to write access, but only
admins can push to the trunk or create tags, and the token's owner is an admin. Immutable
releases lock each published release's assets and tag. A deleted release's tag name can
never be used again.

The first and third rulesets exempt admins (`bypass_mode: exempt`): the rules do not apply to
them at all, so the user merges and the sync pushes with no bypass prompt. The check ruleset
uses `always` instead: admins can still bypass it, but GitHub asks first, so a PR with a
failing check does not merge by accident.

Rulesets on a private repository need a paid GitHub plan. If the fork is private and the
account has no such plan, tell the user that this protection is missing.

Last, delete every upstream branch on the fork except the trunk: the copy of upstream's
`<mirror>`, and any other upstream branch that an existing fork carries. Each holds upstream's
workflows while Actions is on. This step comes last so that a blocked deletion does not hold
up the setup. List the branches with their tips:

```bash
gh api repos/<owner>/<name>/branches --paginate --jq '.[] | "\(.name) \(.commit.sha)"'
```

Delete a branch only if both checks pass. Its tip is in upstream:
`git merge-base --is-ancestor <sha> upstream/<mirror>`, or `git ls-remote --heads upstream
<branch>` prints the same commit. And no PR uses it: `gh pr list -R <owner>/<name> --head
<branch>` and `gh pr list -R <upstream> --head <owner>:<branch>` print nothing. Any other
branch can hold the user's own work: leave it, and tell the user. Delete each branch with its
own command:

```bash
git push origin --delete <branch>
```

If your permissions block the command, give the user the commands with `git -C <clone path>`.
Go on with step 4 while you wait, because step 4 does not depend on the deletion.

### 4. Add the tooling as a setup PR

1. Cut `setup/fork` from the trunk.
2. Write the answers from step 1 to a JSON file outside the clone, then render the
   templates with the kit's script. It writes `.github/fork.yml`, the three
   `.github/workflows/fork-*.yml` callers and `FORK.md`, and checks the result:

   ```bash
   "$KIT_DIR/bin/render-templates" <values.json> .
   ```

   The script's header lists the keys, with an example. `stamp` is a map of file to `jq`
   filter, `assets` and `commit` are lists, and `install` is the install text without a
   heading. Never fill in the templates by hand.
3. Commit `chore: set up fork tooling` with no attribution. Push the branch and open a PR to
   the trunk in the fork (`--repo <owner>/<name>`), never upstream.

The second ruleset from step 3 lets a PR into the trunk merge only after its `check / verify`
job passes. The admins are exempt from the first ruleset, so the user merges a green PR as
usual. Only a PR with a failing check shows the bypass checkbox. The sync's own pushes pass,
because the token acts as its owner, an admin.

Feature work, such as the user's first patches, waits until the setup PR is merged. Before
that, `origin/HEAD` has no `fork.yml`.

### 5. Finish

After the user merged the setup PR, delete the `setup/fork` branch:
`git push origin --delete setup/fork`. If your permissions block the command, ask the user to
use the "Delete branch" button on the merged PR. Make sure that the deletions of step 3 are
done: `gh api repos/<owner>/<name>/branches --jq '.[].name'` lists only the trunk and the
user's own branches. Then dispatch the first sync and the first release, one after the other,
and report both:

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
3. Do step 3 of the persistent fork, except the distribute run and the branch deletion.
   Upstream's workflows can still be on the trunk, and they must not get a token that the
   trunk can read. An adopted fork can hold the user's own branches, so never delete
   branches wholesale.
4. Render the templates on a `setup/fork` branch from the trunk, with `bin/render-templates` as in
   step 4 of the persistent fork. In the same PR, delete the
   fork's old sync and release workflows that the callers replace, and remove upstream's whole
   `.github`: every file in it except `.github/fork.yml` and `.github/workflows/fork-*`.
5. If the fork keeps a copy of upstream's default branch, delete that branch only, with its
   own `git push origin --delete <mirror>`. Hand the command to the user if it is blocked.
6. Disable the upstream push URL and run `git remote set-head origin --auto`.
7. After the user merges the PR, run the distribute workflow as step 3 describes. It also
   moves an old repository-level `SYNC_TOKEN` into the environment. Then dispatch one sync
   and one release, and report both.
