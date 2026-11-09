# Metrics

**What this is:** the metrics collected directly from the Gitea API.

## Pipeline

```text
collect.sh  -> src/data/observability/metrics/YYYY/MM.jsonl
render.sh   -> docs/observability/status.md
```

Rows are append-only. The latest row per `(day, scope, metric)` wins when the
page is rendered.

## Repository metrics

| Metric | Meaning |
| --- | --- |
| `repo_open_issues` | open issues per repository group |
| `repo_open_prs` | open pull requests per group |
| `repo_size_bytes` | repository size |
| `repo_updated_timestamp` | last repository update |
| `repo_archived` | archived repositories in the group |
| `repo_count` | repositories in the group |

## Service metrics

| Metric | Meaning |
| --- | --- |
| `gitea_repositories` | total repositories |
| `gitea_public_repositories` | public repositories |
| `gitea_private_repositories` | private repositories |
| `gitea_archived_repositories` | archived repositories |

## Privacy

Private repositories are aggregated under `repo:private`. Their names and
individual counts never appear in a public page.

## Commands

```bash
infra/scripts/observability/collect.sh
infra/scripts/observability/render.sh
```

`GITEA_URL` and `GITEA_TOKEN` are required for collection. Rendering needs no
credentials.

## Limitations

- The page is a snapshot, not live telemetry.
- The collector reads repository metadata, not per-job CPU or memory.
- Private repository detail stays in the private aggregate.
