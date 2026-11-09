# Disk

## What it is

Host storage for Gitea, Docker images, Prometheus, Grafana, and backups.

## Dashboards

- Grafana `Gitea overview` — disk free

## Alerts

- `HostDiskLow`

## Failure modes

- Docker image growth
- Prometheus TSDB growth
- Gitea attachments
- microSD full (card state: `gardusi-gustavo/private/docs/offline/sync.md`)
- old CI images

## Recovery

```sh
df -h /
docker system df
docker image prune -f
du -sh /srv/gitea/data /srv/observability /srv/backup
```

Do not prune volumes. Check what is large before deleting.

## Verification

- root free above 15%
- microSD free above 10% (verify with `gardusi-gustavo/private/infra/scripts/manual/microsd-sync.sh --verify`)
- Prometheus target up
- backups still verify

## Escalation

`human`, then `root`.
