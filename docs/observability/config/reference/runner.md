# Runner configuration reference

**Source:** `/srv/gitea/runner/config.yml` on the host.

## Settings

| Key | Value |
| --- | --- |
| `runner.capacity` | `1` |
| `runner.timeout` | `60m` |
| `runner.labels` | `ubuntu-latest:docker://docker.gitea.com/runner-images:ubuntu-latest` |
| `container.network` | `gitlab-net` |
| `container.options` | `--memory=3g --memory-swap=6g --cpus=2 --cpu-shares=512 --pids-limit=1024 -v /var/run/docker.sock:/var/run/docker.sock` |
| `cache.enabled` | `true` |

## Secret settings

The registration token lives in `/srv/gitea/runner/.runner`, not in Git.

## Change procedure

1. Edit `config.yml`.
2. Restart the runner.
3. Confirm it declares successfully.
4. Run one test workflow.
5. Update this reference if a non-secret setting changed.
