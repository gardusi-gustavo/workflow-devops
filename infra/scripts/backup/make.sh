#!/usr/bin/env bash
# Create one append-only Gitea dump and prune the targets by age.
set -euo pipefail

TOOLING="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
POLICY="${BACKUP_POLICY:-$TOOLING/infra/config/backup-policy.json}"

[[ -r "$POLICY" ]] || { echo "error: missing $POLICY" >&2; exit 2; }

DEVICE_CONFIG="$(jq -r '.device_config // empty' "$POLICY")"
VAULT_SUBDIR="$(jq -r '.vault_backup_subdir // "0-library/backup/gitea-dumps"' "$POLICY")"
[[ -n "$DEVICE_CONFIG" && -r "$DEVICE_CONFIG" ]] || {
  echo "error: missing device config: ${DEVICE_CONFIG:-unset}" >&2
  exit 2
}
CARD_MOUNT="$(jq -r '.microsd.mount' "$DEVICE_CONFIG")"
[[ -n "$CARD_MOUNT" && "$CARD_MOUNT" != "null" ]] || {
  echo "error: microsd mount missing from $DEVICE_CONFIG" >&2
  exit 2
}
CARD_DUMPS="$CARD_MOUNT/$VAULT_SUBDIR"
lock_file="$(jq -r '.lock_file // "/run/lock/gitea-backup.lock"' "$POLICY")"
mkdir -p "$(dirname "$lock_file")" 2>/dev/null || true
exec 9>"$lock_file"
if ! flock -n 9; then
  echo "backup: another run is active; skipping"
  exit 0
fi
export GITEA_BACKUP_LOCK_HELD=1
export BACKUP_MODE="${BACKUP_MODE:-manual}"
export BACKUP_POLICY="$POLICY"

inventory="skipped"
if [[ -n "${GITEA_TOKEN:-}" ]]; then
  echo "== verify inventory"
  if ! "$TOOLING/infra/scripts/policy/check-inventory.sh" --root "$TOOLING"; then
    export BACKUP_INVENTORY="failed"
    exit 1
  fi
  inventory="ok"
else
  echo "warning: GITEA_TOKEN unset; inventory check skipped" >&2
fi
export BACKUP_INVENTORY="$inventory"

echo "== card dumps: $CARD_DUMPS"
echo "== dump Gitea"
"$TOOLING/infra/scripts/backup/gitea-dump.sh"
"$TOOLING/infra/scripts/backup/prune-card-dumps.sh" --dir "$CARD_DUMPS"

echo "backup complete"
