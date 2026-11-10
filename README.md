# workflow-event

Maintenance workflows, repository policy, inventory, GitHub App manifests,
backup orchestration, and operational runbooks.

## Layout

| Path | Holds |
| --- | --- |
| `.github/workflows/` | reusable CI, release, ingest, Pages, agent, and backup workflows |
| `infra/config/` | policy, inventory, rulesets, app manifests, backup policy, bundle order |
| `infra/scripts/` | control-plane orchestration and agent scripts |
| `src/observability/` | observability collection and rendering |
| `docs/` | runbooks, repository policy, security, and operational notes |

## Related packages

- `package-sh` — reusable shell scripts and bundle primitives
- `package-docker` — Dockerfiles and CI/runtime images

## Validation

```bash
bash infra/scripts/ci.sh
```
