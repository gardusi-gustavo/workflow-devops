# Runner

## What it is

The single Gitea Actions runner. `capacity: 1` means one job at a time.

## Dashboards

- Grafana `Gitea overview` — queue depth
- Prometheus target `gitea-exporter`

## Alerts

- `GiteaActionsQueueStuck`
- `GiteaExporterDown`

## Failure modes

- runner container stopped
- Docker socket unavailable
- job container out of memory
- stale runner registration
- `gitlab-net` network missing

## Recovery

```sh
docker logs --tail 100 gitea-runner
docker restart gitea-runner
docker network inspect gitlab-net
```

Check the Actions run page for the specific job log.

## Verification

- runner shows online in `Site Administration → Actions → Runners`
- a test workflow starts
- queue depth returns to zero

## Escalation

`human`, then `root`.
