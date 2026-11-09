# Runbook

**What this is:** how to refresh and recover the static telemetry page.

## Refresh

```bash
GITEA_URL=http://127.0.0.1:3001 GITEA_TOKEN=... \
  infra/scripts/observability/collect.sh
infra/scripts/observability/render.sh
```

Then commit the JSONL rows and `docs/observability/status.md` through a pull
request.

## Recovery

The JSONL files are the durable record. Rebuild the page from them:

```bash
infra/scripts/observability/render.sh --input src/data/observability/metrics
```

No database or metrics server is required.

## Failure

- If collection fails, the previous page remains valid.
- If a token is missing, collection fails closed; rendering still works.
- Private data must remain aggregated under `repo:private`.
