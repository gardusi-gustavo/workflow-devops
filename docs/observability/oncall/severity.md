# 🚨 Severity

| Severity | Meaning | Respond | Update | Resolve |
| --- | --- | --- | --- | --- |
| P1 | Gitea, CI, or backups unavailable | 15m | 30m | 4h |
| P2 | degraded CI, missing metrics, stale backup | 1h | 2h | 1d |
| P3 | one repo failing, dashboard gap | 1d | 2d | 1w |
| P4 | cosmetic, follow-up | next week | — | — |

## Examples

- **P1:** Gitea down; runner cannot start jobs; backup older than 7 days.
- **P2:** CI failure rate above 25%; Prometheus target down; Grafana down;
  backup older than 48h.
- **P3:** one repository's CI is red; one dashboard panel is empty.
- **P4:** wording, layout, missing chart.

## Rules

- A P1 gets a timeline in the incident record.
- A P1/P2 gets a postmortem within 5 days.
- Do not lower severity without recording why.
