#!/usr/bin/env bash
# Report backup target health and the newest runtime status records.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY="${BACKUP_POLICY:-$SCRIPT_DIR/../../config/backup-policy.json}"
JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --policy) POLICY="${2:-}"; shift 2 ;;
    --json) JSON=1; shift ;;
    -h|--help)
      echo "usage: backup-status.sh [--policy FILE] [--json]"
      exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -r "$POLICY" ]] || { echo "error: cannot read $POLICY" >&2; exit 2; }
primary="$(jq -r '.primary_dir' "$POLICY")"
# shellcheck source=mirrors.sh
source "$(dirname "${BASH_SOURCE[0]}")/mirrors.sh"
load_mirror_dirs "$POLICY" || { echo "error: no backup mirrors resolved" >&2; exit 2; }
mirrors=("${MIRROR_DIRS[@]}")
status_dir="$(jq -r '.status_dir // "/srv/backup/status"' "$POLICY")"

report_dir() {
  local label="$1" dir="$2" count=0 size=0 newest="" avail=0
  if [[ -d "$dir" ]]; then
    count="$(find "$dir" -maxdepth 1 -name 'gitea-*.7z' | wc -l | tr -d ' ')"
    size="$(du -sb "$dir" | awk '{print $1}')"
    avail="$(df -B1 --output=avail "$dir" | tail -1 | tr -d ' ')"
    newest="$(find "$dir" -maxdepth 1 -name 'gitea-*.7z' -printf '%f\n' | sort | tail -1)"
  fi
  jq -n --arg label "$label" --arg dir "$dir" --argjson count "$count" \
    --argjson bytes "$size" --argjson avail "$avail" --arg newest "$newest" \
    '{label:$label,dir:$dir,count:$count,bytes:$bytes,avail:$avail,newest:$newest}'
}

primary_json="$(report_dir primary "$primary")"
mirrors_json="[]"
if (( ${#mirrors[@]} > 0 )); then
  lines="$(mktemp)"
  for dir in "${mirrors[@]}"; do
    [[ -n "$dir" ]] || continue
    report_dir mirror "$dir" >>"$lines"
  done
  mirrors_json="$(jq -s '.' "$lines")"
  rm -f "$lines"
fi

timer="unknown"
if command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet gitea-backup.timer 2>/dev/null; then
    timer="active"
  else
    timer="inactive"
  fi
fi

read_json() {
  local file="$1"
  if [[ -s "$file" ]]; then
    cat "$file"
  else
    echo 'null'
  fi
}

backup_json="$(read_json "$status_dir/backup-latest.json")"
verify_json="$(read_json "$status_dir/verify-latest.json")"
restore_json="$(read_json "$status_dir/restore-latest.json")"

result_json="$(jq -n \
  --argjson primary "$primary_json" \
  --argjson mirrors "$mirrors_json" \
  --arg timer "$timer" \
  --argjson backup "$backup_json" \
  --argjson verify "$verify_json" \
  --argjson restore "$restore_json" \
  '{primary:$primary,mirrors:$mirrors,timer:$timer,last_backup:$backup,last_verify:$verify,last_restore:$restore}')"

if (( JSON )); then
  printf '%s\n' "$result_json"
else
  jq -r '.primary | "primary: \(.count) archives, \(.bytes) bytes, \(.avail) bytes free, newest \(.newest // "none")"' <<<"$result_json"
  jq -r '.mirrors[] | "mirror:  \(.dir) \(.count) archives, \(.bytes) bytes, \(.avail) bytes free, newest \(.newest // "none")"' <<<"$result_json"
  jq -r '"timer:   \(.timer)"' <<<"$result_json"
  jq -r 'if .last_backup then "backup:  \(.last_backup.result) \(.last_backup.archive) at \(.last_backup.finished_at)" else "backup:  no status" end' <<<"$result_json"
  jq -r 'if .last_backup.size_warning then "warning: archive \(.last_backup.size_bytes) bytes vs baseline \(.last_backup.size_baseline_bytes) bytes" else empty end' <<<"$result_json"
  jq -r 'if .last_verify then "verify:  \(.last_verify.result) \(.last_verify.archive) age \(.last_verify.age_hours)h" else "verify:  no status" end' <<<"$result_json"
  jq -r 'if .last_restore then "restore: \(.last_restore.result) \(.last_restore.archive) at \(.last_restore.tested_at)" else "restore: no status" end' <<<"$result_json"
fi
