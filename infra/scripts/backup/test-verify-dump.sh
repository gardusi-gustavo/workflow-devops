#!/usr/bin/env bash
# Fixture tests for extracted dump verification.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
VERIFY="$ROOT/infra/scripts/backup/verify-dump-contents.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

build() {
  local dir="$1"
  mkdir -p "$dir/repos/test/repo.git" "$dir/data"
  : > "$dir/gitea-db.sql"
  : > "$dir/app.ini"
  python3 - "$dir/data/gitea.db" <<'PY'
import sqlite3
import sys
db = sqlite3.connect(sys.argv[1])
for table in ("repository", "issue", "pull_request", "user", "comment", "attachment"):
    db.execute(f'create table "{table}" (id integer)')
    db.execute(f'insert into "{table}" values (1)')
db.commit()
PY
}

build "$tmp/good"
out="$(bash "$VERIFY" --root "$tmp/good" --json)"
[[ "$(jq -r '.repositories' <<<"$out")" == "1" ]] || fail "repository count"
[[ "$(jq -r '.git_repositories' <<<"$out")" == "1" ]] || fail "git repository count"
[[ "$(jq -r '.issues' <<<"$out")" == "1" ]] || fail "issue count"
[[ "$(jq -r '.pulls' <<<"$out")" == "1" ]] || fail "pull count"
[[ "$(jq -r '.users' <<<"$out")" == "1" ]] || fail "user count"
pass "verifies a complete dump"

mkdir -p "$tmp/bad/data"
: > "$tmp/bad/data/gitea.db"
: > "$tmp/bad/gitea-db.sql"
: > "$tmp/bad/app.ini"
if bash "$VERIFY" --root "$tmp/bad" >/dev/null 2>&1; then fail "empty repos should fail"; fi
pass "rejects a dump without repositories"

echo "verify-dump tests ok"
