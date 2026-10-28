# Fork of {{upstream}}

This repository is a fork of [{{upstream}}](https://github.com/{{upstream}}). It carries its own
patches and publishes its own releases. The fork skill and the workflows of
[{{kit_repo}}](https://github.com/{{kit_repo}}) manage it.

## Branches

| Branch | Role |
|---|---|
| `{{trunk}}` | Default branch: upstream plus our patches. Releases come from here. |
| `feat/<name>` | A change for upstream. Cut it from upstream's `{{mirror}}` (`git fetch upstream`, then `upstream/{{mirror}}`), so that the upstream PR holds only that change. |
| `fork/<name>` | A change that stays in this fork. Cut it from `{{trunk}}`. |
| `sync/<ref>` | A parked upstream merge that conflicts, without upstream's CI. Resolve it, then merge it into `{{trunk}}`. |

The fork keeps no copy of upstream's `{{mirror}}`, and `{{trunk}}` holds none of upstream's
`.github` files, because GitHub runs upstream's workflows here with this fork's secrets.

## Releases

Fork releases are tagged `<upstream version>-{{suffix}}.<N>`, for example `1.2.3-{{suffix}}.2`.
Upstream's own tags never carry the `-{{suffix}}.` part. N starts at 1 for each new upstream
version.

{{install}}

## Configuration

`.github/fork.yml` holds the configuration. Edit it on `{{trunk}}` only.
