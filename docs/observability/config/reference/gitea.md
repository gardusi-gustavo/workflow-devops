# Gitea configuration reference

**Source:** `/srv/gitea/data/gitea/conf/app.ini` on the host.
**Do not copy secrets into Git.**

## Non-secret settings

| Section | Key | Value |
| --- | --- | --- |
| server | `DOMAIN` | `gitea.localhost` |
| server | `ROOT_URL` | `http://gitea.localhost:3001/` |
| server | `SSH_PORT` | `2225` |
| repository | `DEFAULT_BRANCH` | `main` |
| repository | `MAX_CREATION_LIMIT` | `50` |
| service | `DISABLE_REGISTRATION` | `true` |
| actions | `ENABLED` | `true` |
| actions | `LOG_RETENTION_DAYS` | `30` |
| actions | `ARTIFACT_RETENTION_DAYS` | `14` |
| metrics | `ENABLED` | `true` |
| audit | `RECORD_OUTPUT` | `database` |
| audit | `RETENTION_DAYS` | `90` |

## Secret settings

Redacted: `SECRET_KEY`, `INTERNAL_TOKEN`, `JWT_SECRET`, `metrics.TOKEN`,
database password, and the runner registration token.

## Change procedure

1. Edit `app.ini`.
2. Validate with `docker exec gitea gitea config check` if available.
3. Restart Gitea.
4. Confirm login, clone, Actions, and `/metrics`.
5. Update this reference if a non-secret setting changed.
