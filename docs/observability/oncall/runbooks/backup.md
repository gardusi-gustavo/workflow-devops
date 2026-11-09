# Backup

## What it is

The latest-tag repository archives and Gitea dump on the card. Card paths are
resolved from `gardusi-gustavo/private/infra/config/offline-devices.json`.

## Dashboards

- Grafana `Gitea overview` — backup age

## Alerts

- `GiteaBackupStale`

## Failure modes

- card not mounted
- stale repository archive
- Gitea dump permission error
- backup verification failure

## Recovery

```sh
cd /srv/backup/tooling
./backup/manual.sh repos
./backup/manual.sh gitea
./backup/manual.sh all
```

## Verification

- `verify-card: ok`
- manifest age under 48h
- 21 repository archives
- `latest.zip` opens

## Restore drill

Quarterly: restore Gitea to a temporary path, verify a clone and the web UI, then
remove the temporary copy.

## Escalation

`human`, then `root`.
