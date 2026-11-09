# Ingestion

## Branches

One rolling branch per domain: `data/<domain>`.

## PR policy

- One open PR per domain.
- Human approval always.
- Squash merge only.
- Cap: 7 days, 500 files, 50 MiB added bytes.
- On cap: stop ingestion and require a merge.
- Never create `data/<domain>-v2` while `data/<domain>` is open.
- After merge: reset or delete the branch.

## Workflows

- `workflow-devops/.github/workflows/ingest.yml` is reusable.
- Each `workflow-*` repository has a caller on a schedule and on demand.
- The app token has `contents: write` on `database` and the affected dashboard.
- The app never approves or merges.
