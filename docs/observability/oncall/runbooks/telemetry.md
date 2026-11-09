# Static telemetry

## What it is

The Gitea API collector and Markdown renderer.

```text
collect.sh -> src/data/observability/metrics/YYYY/MM.jsonl
render.sh  -> docs/observability/status.md
```

## Failure modes

- missing or expired `GITEA_TOKEN`
- Gitea API unreachable
- a private repository name appears in a public page
- malformed JSONL row

## Recovery

```bash
GITEA_URL=http://127.0.0.1:3001 GITEA_TOKEN=... \
  infra/scripts/observability/collect.sh
infra/scripts/observability/render.sh
```

If collection fails, keep the previous page. Fix the token or API access, then
rerun.

## Verification

- `docs/observability/status.md` shows the current day.
- private repositories appear only as `private`.
- `PYTHONPATH=src python3 -m unittest discover -s src/tests -t src -q` passes.
