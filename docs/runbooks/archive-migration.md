# Archive migration

The archived repository inventory is mapped in
`infra/config/archive-migration.json` and validated by
`infra/scripts/archive/verify-migration.sh`.

## Statuses

- `migrated` — content now lives in a target repository.
- `split` — content moved to multiple targets.
- `pending` — mapping is known but the move is not complete.
- `dropped` — intentionally not migrated; preserved in bundles.
- `cold-storage` — kept only as an archived reference.

## Verify

```bash
HOME=/home/user bash infra/scripts/archive/verify-migration.sh --root . --check-paths
```

`--strict` fails while any entry is still `pending`.
