# 🎯 SLOs

| Service | SLI | Target | Window |
| --- | --- | --- | --- |
| Gitea | availability (`up{job="gitea"}`) | 99.5% | 30d |
| CI | success rate | 95% | 7d |
| Runner | queue depth | <= 3 for 10m | rolling |
| Backups | age | < 48h | rolling |
| Metrics | scrape success | 99% | 30d |
| Prometheus | rule evaluation success | 99% | 30d |

## Error budget

- Gitea: ~3.6 hours unavailable per 30 days.
- CI: 5 failures per 100 runs.
- Backups: one missed daily refresh is within budget; seven days is P1.

## Review

Review monthly. If the budget is exhausted, freeze non-essential changes until
the cause is fixed.

## Alerts

| Alert | SLO |
| --- | --- |
| `GiteaDown` | availability |
| `GiteaActionsFailureRate` | CI success |
| `GiteaActionsQueueStuck` | queue depth |
| `GiteaBackupStale` | backup freshness |
| `GiteaExporterDown` | metrics coverage |
| `HostDiskLow` | capacity |

Every alert has an owner in this document. Add a runbook link before adding a
new alert.
