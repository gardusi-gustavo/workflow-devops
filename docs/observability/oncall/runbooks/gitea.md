# Gitea

## What it is

The source of truth for repositories, issues, pull requests, users, organizations,
branch protection, and tag protection.

## Dashboards

- Grafana `Gitea overview`
- Gitea `/metrics`

## Alerts

- `GiteaDown`
- `GiteaTagDrift`
- `HostDiskLow`

## Failure modes

- container stopped or OOM
- SQLite lock or disk full
- certificate or reverse proxy
- accidentally deleted repository

## Recovery

```sh
docker restart gitea
docker logs --tail 100 gitea
curl -s http://127.0.0.1:3001/api/v1/version
```

If the database is lost, restore the latest Gitea dump. Do not start a second
Gitea against the same data directory.

## Verification

- login works
- repository list loads
- clone over SSH and HTTPS works
- Actions can fetch a task

## Escalation

`human`, then `root`.
