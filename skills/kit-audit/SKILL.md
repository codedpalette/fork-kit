---
name: kit-audit
description: Use when working in the fork-kit repository itself (the kit, not a fork made with it), before you plan a change to its workflows, scripts, skills or hooks, and again before you open a PR or ask the user to merge one.
---

# Kit security audit

The kit's `main` reaches every fork through the moving major tag, and every machine through
plugin auto-update. A merged mistake runs in each fork's job that holds `SYNC_TOKEN`. No
person tests a change in a real fork first, so this audit is the gate.

Run it twice:

1. Plan gate: before you write code, list what the plan changes in jobs, tokens,
   permissions, triggers and pushed refs. Check that list against the rules below and show
   the result with the plan.
2. Merge gate: before `gh pr create`, and before you ask the user to merge, run the tests
   and the review below. A broken rule blocks the PR.

## Rules

The README's "Security rules for the workflows" and the headers of `sync.yml` and
`release.yml` are the source. Read them, then check each changed line against these:

| Area | Rule |
|---|---|
| Secrets | Only the trusted job of a workflow names `SYNC_TOKEN`. No `secrets: inherit`. |
| Upstream code | Install, build, verify or any upstream script runs only in a job without secrets and with read permissions. |
| Credentials | Jobs without the token set `persist-credentials: false`. The token reaches git through the credential helper, never a URL, an argument or a log line. |
| Upstream CI | Upstream's `.github` never lands on the trunk or a pushed branch. Upstream's default branch is never pushed. |
| Untrusted text | Tag names, branch names, PR titles and release names reach a script through `env:`, never as `${{ }}` inside `run:`. |
| Triggers | No `pull_request_target`, `workflow_run` or `issue_comment` with write access or secrets. |
| Permissions | Each job gets the least it needs. Call out any new write permission, environment or ruleset bypass. |
| Actions | Third-party actions are pinned to a full commit SHA. |
| Kit ref | The kit is checked out by tag or commit only, never by a branch name. |
| Kit tags | Only `kit-release.yml`, on `main`, writes `v*` tags. No other kit workflow gets `contents: write`. |
| Skill and hooks | They run on every machine: no download and run, no command built from repository content, no secret in output. |
| Docs | A changed rule changes the README section and the workflow header in the same PR. |

If the change needs to break a rule, stop and ask the user. Do not loosen
`test/check-isolation` to make it pass.

## Merge gate

```bash
bats test/ && shellcheck bin/* scripts/*.sh test/check-isolation && actionlint
git diff main...HEAD
```

Then dispatch a fresh subagent with the diff, the rules table and the README's security
section, not your own conclusions. Ask it to report each broken rule with `file:line` and a
concrete attack. Check each finding yourself, fix the real ones and run the gate again. Put
the result in the PR description, under a "Security audit" heading: the rules the change
touches and the verdict for each.
