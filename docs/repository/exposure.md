# Visibility and exposure

> **Current exposure:** Gitea runs on localhost only. There is no public DNS,
> TLS, or internet exposure. Repository visibility is an organizational
> boundary, not an internet security boundary yet.

## Rules

- `private/*` is the only private namespace.
- Every other organization is public by default.
- Only the `private` organization may contain repositories with the private
  flag.
- A public repository is still a local repository. Do not treat it as safe to
  publish until the public export is reviewed.
- Private repositories and private data must never be mirrored, exported, or
  linked from a public page.

## Future export

When the instance is exposed, publish only the reviewed public set. The current
public organizations are:

```text
browser        retiring
dashboards
games

knowledge
packages
```

Do not export `private/*`.

## Checks

```bash
GITEA_URL=http://127.0.0.1:3001 GITEA_TOKEN=... \
  infra/scripts/policy/check-orgs.sh

GITEA_URL=http://127.0.0.1:3001 GITEA_TOKEN=... \
  infra/scripts/policy/check-visibility.sh
```

`check-orgs.sh` compares the live organization names, descriptions, and
visibility with `infra/config/orgs.json`. `check-visibility.sh` fails when a
repository outside the private organization has the private flag, or when a
repository inside it does not.

## Related

- `docs/repository/policy.md`
- `docs/repository/backup.md`
- `docs/repository/disaster-recovery-test.md`
