# ⚙️ Gitea Actions

**What this is:** the instance-level Actions configuration and the conventions every
workflow follows.

## 🏃 Runner

There is one instance runner:

```yaml
# /home/user/runner/config.yml
runner:
  capacity: 1
  timeout: 60m
```

- `capacity: 1` means one job at a time across the whole instance.
- Gitea has no global “max parallel workflows” setting; the runner is the cap.
- Adding runners multiplies capacity. Do not add one unless you intend more
  parallelism.
- The runner runs in the rootless Docker of the bot OS account `gitea-automation` (Gitea `bot-event`) with a 1 GB / 1 CPU limit.
  Job containers request 3 GB / 2 CPUs.
- Jobs receive the rootless Docker socket, not the rootful host socket. A
  workflow can build containers without gaining root on the host.

## 🔁 Workflow concurrency

CI workflows cancel superseded runs:

```yaml
concurrency:
  group: ci-${{ github.repository }}-${{ github.ref }}
  cancel-in-progress: true
```

Release, images, and policy workflows do not cancel in progress:

```yaml
concurrency:
  group: release-${{ github.repository }}
  cancel-in-progress: false
```

This keeps the single runner queue short. It does not replace `capacity: 1`.

## ⏱️ Timeouts

| Workflow | Timeout |
| --- | ---: |
| `ci` | 15m |
| `release` | 30m |
| `policy` | 15m |
| `images` | 60m |
| runner | 60m |

The runner timeout must be greater than or equal to the largest workflow timeout.

## 🏷️ Tag protection

`v*` tags are protected. The allowlist is `human` only. Release automation must
use a token owned by an allowlisted user.

## 🔒 Private repositories

Private repository Actions runs are visible in the repository’s **Actions** tab.
The commit status API can return `null` even when the run succeeded; use the run
page or the database when in doubt.

## 🧹 Stale runners

Only the active runner registration should exist. Remove disabled/offline runners
in `Site Administration → Actions → Runners`.

## 🚚 Heavy jobs

`images` is the only long job. If it regularly occupies the runner for more than
30 minutes, register a second runner with a `heavy` label and set
`runs-on: heavy`. Keep the default runner at `capacity: 1`.

## 📊 Usage report

```sh
GITEA_TOKEN=<token> infra/scripts/actions-report.sh --days 30
```

The report reads the registry and the Actions API. It prints runs, success and
failure counts, average and max duration, the slowest runs, and recent failures.
Use `--repo group/name` for one repository.

## 🔗 Related

- Backups: `backup.md`
- Scripts: `scripts.md`
