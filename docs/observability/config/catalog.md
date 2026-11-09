# 🗂️ Config catalog

**What this is:** the source of truth for every configuration used by the private
stack. Store references and sanitized settings, never secrets.

| Config | Source of truth | Runtime | Review |
| --- | --- | --- | --- |
| Gitea `app.ini` | host | `/srv/gitea/data/gitea/conf/app.ini` | [reference](http://gitea.localhost:3001/private/wiki/src/branch/main/docs/reference/infra/gitea.md) |
| Runner `config.yml` | host | `/srv/gitea/runner/config.yml` | [reference](http://gitea.localhost:3001/private/wiki/src/branch/main/docs/reference/infra/gitea.md) |
| Repository registry | `dashboards/devops/infra/config/repos.json` | `/srv/backup/tooling/repos.json` | link |
| Backup manifest | host | `/srv/backup/repos.tsv` | link |
| Static telemetry | `src/observability/collect.py` | collector job | review |

## Rules

- Secrets never enter this repository.
- Host-only configs get a sanitized reference, not a raw copy.
- Runtime copies must match the source of truth after a deploy.
- A config change that affects behavior needs a Gitea issue.
- The devops repo owns telemetry collection, the static page, and on-call docs.
- Gitea owns repositories, issues, users, and rules.
