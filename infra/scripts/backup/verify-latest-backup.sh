#!/usr/bin/env bash
# Verify the newest primary archive and every mirror copy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY="${BACKUP_POLICY:-$SCRIPT_DIR/../../config/backup-policy.json}"
JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --policy) POLICY="${2:-}"; shift 2 ;;
    --json) JSON=1; shift ;;
    -h|--help)
      echo "usage: verify-latest-backup.sh [--policy FILE] [--json]"
      exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -r "$POLICY" ]] || { echo "error: cannot read $POLICY" >&2; exit 2; }
command -v 7z >/dev/null || { echo "error: 7z is required" >&2; exit 2; }
command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 2; }

primary="$(jq -r '.primary_dir' "$POLICY")"
# shellcheck source=mirrors.sh
source "$(dirname "${BASH_SOURCE[0]}")/mirrors.sh"
load_mirror_dirs "$POLICY" || { echo "error: no backup mirrors resolved" >&2; exit 2; }
mirrors=("${MIRROR_DIRS[@]}")
password_file="$(jq -r '.password_file // "/srv/backup/secrets/backup.pass"' "$POLICY")"
status_dir="$(jq -r '.status_dir // "/srv/backup/status"' "$POLICY")"
max_age_hours="$(jq -r '.max_age_hours // 27' "$POLICY")"
PASSWORD="$(<"$password_file")"
[[ -n "$PASSWORD" ]] || { echo "error: empty password file" >&2; exit 2; }

shopt -s nullglob
archives=("$primary"/gitea-*.7z)
(( ${#archives[@]} > 0 )) || { echo "error: no archives in $primary" >&2; exit 1; }
archive="$(printf '%s\n' "${archives[@]}" | sort | tail -1)"
base="$(basename "$archive")"
sha256="$(sha256sum "$archive" | awk '{print $1}')"
age_seconds=$(( $(date +%s) - $(stat -c %Y "$archive") ))
age_hours=$(( age_seconds / 3600 ))
failures="$status_dir/.verify-failures.$$"
: >"$failures"

fail() {
  echo "$1" >>"$failures"
  echo "verify: $1" >&2
}

if [[ ! -f "$archive.sha256" ]]; then
  fail "primary sidecar missing: $archive.sha256"
elif ! (cd "$primary" && sha256sum -c "$base.sha256" >/dev/null); then
  fail "primary checksum failed: $base"
fi
if ! 7z t -p"$PASSWORD" "$archive" >/dev/null; then
  fail "primary archive integrity failed: $base"
fi
if (( age_hours > max_age_hours )); then
  fail "primary archive is ${age_hours}h old; limit ${max_age_hours}h"
fi

destinations="$status_dir/.verify-destinations.$$"
: >"$destinations"
for mirror in "${mirrors[@]}"; do
  [[ -n "$mirror" ]] || continue
  target="$mirror/$base"
  status="ok"
  if [[ ! -f "$target" ]]; then
    status="missing"
    fail "mirror copy missing: $target"
  elif [[ "$(sha256sum "$target" | awk '{print $1}')" != "$sha256" ]]; then
    status="checksum_failed"
    fail "mirror checksum failed: $target"
  elif [[ ! -f "$target.sha256" ]]; then
    status="sidecar_missing"
    fail "mirror sidecar missing: $target.sha256"
  elif ! (cd "$mirror" && sha256sum -c "$base.sha256" >/dev/null); then
    status="sidecar_failed"
    fail "mirror sidecar check failed: $target"
  elif ! 7z t -p"$PASSWORD" "$target" >/dev/null; then
    status="integrity_failed"
    fail "mirror archive integrity failed: $target"
  fi
  jq -n --arg dir "$mirror" --arg status "$status" \
    '{dir:$dir,status:$status}' >>"$destinations"
done

if [[ -s "$failures" ]]; then
  result="failed"
else
  result="pass"
fi

jq -n \
  --arg archive "$base" \
  --arg tested_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg sha256 "$sha256" \
  --argjson age_hours "$age_hours" \
  --argjson max_age_hours "$max_age_hours" \
  --argjson destinations "$(jq -s '.' "$destinations")" \
  --argjson failures "$(jq -R -s 'split("\n") | map(select(length > 0))' "$failures")" \
  --arg result "$result" \
  '{archive:$archive,tested_at:$tested_at,sha256:$sha256,age_hours:$age_hours,max_age_hours:$max_age_hours,destinations:$destinations,failures:$failures,result:$result}' \
  >"$status_dir/verify-latest.json.tmp"
mv "$status_dir/verify-latest.json.tmp" "$status_dir/verify-latest.json"
chown "${BACKUP_OWNER:-user}:${BACKUP_OWNER:-user}" "$status_dir/verify-latest.json" 2>/dev/null || true
rm -f "$failures" "$destinations"

if (( JSON )); then
  cat "$status_dir/verify-latest.json"
else
  jq -r '"archive: \(.archive)\nage: \(.age_hours)h / \(.max_age_hours)h\nresult: \(.result)"' "$status_dir/verify-latest.json"
  jq -r '.destinations[] | "mirror: \(.dir) \(.status)"' "$status_dir/verify-latest.json"
  jq -r '.failures[]? | "failure: \(.)"' "$status_dir/verify-latest.json"
fi

[[ "$result" == "pass" ]]
