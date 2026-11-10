# 🧯 Recovery

**What this is:** rebuild the stack after a format or total host loss.

## Durable inputs

- Gitea dump and repository archives on the microSD.
- `gardusi-gustavo/workflow-event` in Git, including committed JSONL telemetry rows.
- Secrets are **not** durable; regenerate them.

## 1. Restore Gitea

Follow the backup restore procedure for the Gitea stack. Confirm:

```sh
curl -s http://127.0.0.1:3001/api/v1/version
```

## 2. Restore repositories

Clone from Gitea, or restore the latest repo archives on the microSD.

## 3. Restore telemetry

The JSONL rows are in Git. Rebuild the page:

```sh
infra/scripts/observability/render.sh
```

No metrics server, database, or dashboard container is required.

## 4. Regenerate the token

Create a read-only Gitea token for collection and store it outside Git:

```sh
export GITEA_TOKEN=<read-only token>
```

## 5. Refresh

```sh
GITEA_URL=http://127.0.0.1:3001 GITEA_TOKEN=... \
  infra/scripts/observability/collect.sh
infra/scripts/observability/render.sh
```

## 6. Verify

```sh
head docs/observability/status.md
PYTHONPATH=src python3 -m unittest discover -s src/tests -t src -q
```

The page must show the current day and aggregate private repositories as
`private`.

## Drill

Run this quarterly. Record the date, duration, missing data, and follow-up
issues in a postmortem or a drill note.
