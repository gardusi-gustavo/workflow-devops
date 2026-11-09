#!/usr/bin/env bash
# Restore the newest archive into a temporary Gitea instance and record the result.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY="${BACKUP_POLICY:-$SCRIPT_DIR/../../config/backup-policy.json}"
RESTORE="$SCRIPT_DIR/restore-dump.sh"
PORT="${RESTORE_PORT:-3002}"
IMAGE="${GITEA_RESTORE_IMAGE:-gitea/gitea:28.2.0}"
OUT=""
KEEP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --policy) POLICY="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --image) IMAGE="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    -h|--help)
      echo "usage: restore-test.sh [--policy FILE] [--port PORT] [--image IMAGE] [--out DIR] [--keep]"
      exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -r "$POLICY" ]] || { echo "error: cannot read $POLICY" >&2; exit 2; }
command -v docker >/dev/null || { echo "error: docker is required" >&2; exit 2; }
command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 2; }
command -v curl >/dev/null || { echo "error: curl is required" >&2; exit 2; }
command -v python3 >/dev/null || { echo "error: python3 is required" >&2; exit 2; }

primary="$(jq -r '.primary_dir' "$POLICY")"
status_dir="$(jq -r '.status_dir // "/srv/backup/status"' "$POLICY")"
lock_file="$(jq -r '.lock_file // "/run/lock/gitea-backup.lock"' "$POLICY")"
mkdir -p "$status_dir" "$(dirname "$lock_file")" 2>/dev/null || true

exec 9>"$lock_file"
if ! flock -w 3600 9; then
  echo "error: backup lock is held; restore test skipped" >&2
  exit 1
fi

shopt -s nullglob
archives=("$primary"/gitea-*.7z)
(( ${#archives[@]} > 0 )) || { echo "error: no archives in $primary" >&2; exit 1; }
archive="$(printf '%s\n' "${archives[@]}" | sort | tail -1)"
archive_base="$(basename "$archive")"

if [[ -z "$OUT" ]]; then
  OUT="$(mktemp -d "${TMPDIR:-/tmp}/gitea-restore-test.XXXXXX")"
  created=1
else
  created=0
  rm -rf "$OUT"
  mkdir -p "$OUT"
fi
container="gitea-restore-test-$$"
failures="$OUT/failures.txt"
: >"$failures"
result="failed"
version="unknown"
repo_count=0
issue_count=0
pr_count=0
user_count=0
attachment_count=0
integrity="unknown"
git_ok="false"
ui_status="000"

cleanup() {
  docker rm -f "$container" >/dev/null 2>&1 || true
  if (( ! KEEP && created )); then
    rm -rf "$OUT"
  fi
}
trap cleanup EXIT

fail() {
  echo "$1" >>"$failures"
  echo "restore-test: $1" >&2
}

write_status() {
  local failures_json="[]"
  [[ -s "$failures" ]] && failures_json="$(jq -R -s 'split("\n") | map(select(length > 0))' "$failures")"
  jq -n \
    --arg archive "$archive_base" \
    --arg tested_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg gitea_version "$version" \
    --argjson repositories "${repo_count:-0}" \
    --argjson issues "${issue_count:-0}" \
    --argjson pulls "${pr_count:-0}" \
    --argjson users "${user_count:-0}" \
    --argjson attachments "${attachment_count:-0}" \
    --arg integrity "$integrity" \
    --arg git "$git_ok" \
    --arg ui "$ui_status" \
    --argjson failures "$failures_json" \
    --arg result "$result" \
    '{archive:$archive,tested_at:$tested_at,gitea_version:$gitea_version,repositories:$repositories,issues:$issues,pulls:$pulls,users:$users,attachments:$attachments,integrity:$integrity,git:$git,ui_status:$ui,result:$result,failures:$failures}' \
    >"$status_dir/restore-latest.json.tmp"
  mv "$status_dir/restore-latest.json.tmp" "$status_dir/restore-latest.json"
  chown "${BACKUP_OWNER:-user}:${BACKUP_OWNER:-user}" "$status_dir/restore-latest.json" 2>/dev/null || true
}

echo "== restore $archive_base"
if ! bash "$RESTORE" --dump "$archive" --out "$OUT" >/dev/null; then
  fail "restore-dump failed"
  write_status
  exit 1
fi
chown -R 1000:1000 "$OUT/data"

docker rm -f "$container" >/dev/null 2>&1 || true
if ! docker run -d --name "$container" -p "$PORT:3000" \
  -e GITEA__server__ROOT_URL="http://127.0.0.1:$PORT/" \
  -e GITEA__server__DOMAIN=127.0.0.1 \
  -e GITEA__server__HTTP_PORT=3000 \
  -e GITEA__server__START_SSH_SERVER=false \
  -v "$OUT/data:/data" "$IMAGE" >/dev/null; then
  fail "temporary Gitea failed to start"
  write_status
  exit 1
fi

ready=0
for _ in $(seq 1 60); do
  if version="$(curl -fsS "http://127.0.0.1:$PORT/api/v1/version" 2>/dev/null | jq -r '.version // empty' 2>/dev/null)" && [[ -n "$version" ]]; then
    ready=1
    break
  fi
  sleep 1
done
if (( ! ready )); then
  fail "temporary Gitea API did not become ready"
  write_status
  exit 1
fi

ui_status="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/" 2>/dev/null || echo 000)"
[[ "$ui_status" == "200" ]] || fail "UI returned $ui_status"

counts="$(python3 - "$OUT/data/gitea/gitea.db" <<'PY'
import json, sqlite3, sys
db = sqlite3.connect(sys.argv[1])
def count(table):
    return db.execute(f'select count(*) from "{table}"').fetchone()[0]
print(json.dumps({
  "repositories": count("repository"),
  "issues": count("issue"),
  "pulls": count("pull_request"),
  "users": count("user"),
  "attachments": count("attachment"),
  "integrity": db.execute("pragma integrity_check").fetchone()[0],
}))
PY
)"
repo_count="$(jq -r '.repositories // 0' <<<"$counts")"
issue_count="$(jq -r '.issues // 0' <<<"$counts")"
pr_count="$(jq -r '.pulls // 0' <<<"$counts")"
user_count="$(jq -r '.users // 0' <<<"$counts")"
attachment_count="$(jq -r '.attachments // 0' <<<"$counts")"
integrity="$(jq -r '.integrity // "unknown"' <<<"$counts")"

[[ "$integrity" == "ok" ]] || fail "SQLite integrity is $integrity"
(( repo_count > 0 )) || fail "restored database has no repositories"

if GIT_TERMINAL_PROMPT=0 git ls-remote "http://127.0.0.1:$PORT/dashboards/devops.git" >/dev/null 2>&1; then
  git_ok="true"
else
  fail "git ls-remote failed"
fi

if [[ ! -s "$failures" ]]; then
  result="pass"
fi
write_status

jq -r '"archive: \(.archive)\nresult: \(.result)\nrepos: \(.repositories) issues: \(.issues) pulls: \(.pulls) users: \(.users) attachments: \(.attachments)\nintegrity: \(.integrity) git: \(.git) ui: \(.ui_status)"' "$status_dir/restore-latest.json"
jq -r '.failures[]? | "failure: \(.)"' "$status_dir/restore-latest.json"

[[ "$result" == "pass" ]]
