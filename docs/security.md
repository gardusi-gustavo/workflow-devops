# Security

## Reporting

Use GitHub private vulnerability reporting. Do not open a public issue for a
secret exposure.

## Boundaries

- `gardusi-gustavo/*` is public. Public data only.
- `gardusi-gustavo/private` is the only private repository.
- `gardusi-gustavo/private` is the local Gitea private boundary and is never mirrored.
- Secrets live in GitHub Environments or `/etc/opencode/secrets/`.
- Public workflows never receive a personal access token.
- Data PRs are human-reviewed and squash-merged.
