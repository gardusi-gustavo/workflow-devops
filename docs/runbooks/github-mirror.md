# GitHub mirror runbook

## Preconditions

- `gh` is installed and authenticated for `gardusi-gustavo`.
- `gh auth status` shows the `repo` and `workflow` scopes.
- The pre-publication audit passes with `critical=0`.

## Steps

```bash
export GH_TOKEN=...
infra/scripts/github/pre-publication-audit.sh ~/repos
infra/scripts/github/mirror.sh --apply
infra/scripts/github/bootstrap.sh --apply
```

## After the mirror

1. Enable secret scanning and push protection for every public repository.
2. Create GitHub Environments: `pypi`, `npm`, `crates`, `dockerhub`, `github-pages`, `ingest`.
3. Add required reviewers to release environments.
4. Install the app from `infra/config/github/app.json` on `database` and the dashboards.
5. Run one `/agent` command and one ingestion dry run.
