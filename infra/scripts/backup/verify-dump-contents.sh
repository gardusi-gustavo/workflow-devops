#!/usr/bin/env bash
# Validate an extracted Gitea dump tree before it is archived.
set -euo pipefail

ROOT=""
ZIP=""
JSON=0
FSCK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --zip) ZIP="${2:-}"; shift 2 ;;
    --json) JSON=1; shift ;;
    --fsck) FSCK=1; shift ;;
    -h|--help) echo "usage: verify-dump-contents.sh --root DIR|--zip FILE [--json] [--fsck]"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

tmp=""
cleanup() { if [[ -n "$tmp" ]]; then rm -rf "$tmp"; fi; return 0; }
trap cleanup EXIT
if [[ -n "$ZIP" ]]; then
  [[ -r "$ZIP" ]] || { echo "error: cannot read dump: $ZIP" >&2; exit 2; }
  tmp="$(mktemp -d)"
  unzip -tqq "$ZIP" >/dev/null || { echo "error: invalid zip: $ZIP" >&2; exit 1; }
  unzip -qq "$ZIP" -d "$tmp"
  ROOT="$tmp"
fi
[[ -n "$ROOT" && -d "$ROOT" ]] || { echo "error: --root or --zip is required" >&2; exit 2; }

fail() { echo "error: $*" >&2; exit 1; }
[[ -d "$ROOT/repos" ]] || fail "dump has no repos/ directory"
[[ -f "$ROOT/data/gitea.db" ]] || fail "dump has no data/gitea.db"
[[ -f "$ROOT/gitea-db.sql" ]] || fail "dump has no gitea-db.sql"
[[ -f "$ROOT/app.ini" || -f "$ROOT/data/conf/app.ini" ]] || fail "dump has no app.ini"

git_repos="$(find "$ROOT/repos" -mindepth 2 -maxdepth 2 -type d -name '*.git' | wc -l)"
(( git_repos > 0 )) || fail "dump has no repositories"

counts='{"repositories":0,"issues":0,"pulls":0,"users":0,"comments":0,"attachments":0}'
if command -v python3 >/dev/null 2>&1; then
  counts="$(python3 - "$ROOT/data/gitea.db" <<'PY'
import json
import sqlite3
import sys

db = sqlite3.connect(sys.argv[1])
check = db.execute("pragma integrity_check").fetchone()[0]
if check != "ok":
    raise SystemExit(f"sqlite integrity check failed: {check}")
out = {}
for key, table in (
    ("repositories", "repository"),
    ("issues", "issue"),
    ("pulls", "pull_request"),
    ("users", "user"),
    ("comments", "comment"),
    ("attachments", "attachment"),
):
    try:
        out[key] = db.execute(f'select count(*) from "{table}"').fetchone()[0]
    except sqlite3.Error:
        out[key] = -1
print(json.dumps(out))
PY
)"
else
  echo "warning: python3 missing; skipping database counts and integrity check" >&2
fi

if (( FSCK )); then
  while IFS= read -r repo; do
    [[ -n "$repo" ]] || continue
    git --git-dir="$repo" fsck --connectivity-only --no-progress >/dev/null 2>&1 ||
      fail "git fsck failed: $repo"
  done < <(find "$ROOT/repos" -mindepth 2 -maxdepth 2 -type d -name '*.git')
fi

if (( JSON )); then
  jq -nc --argjson dirs "$git_repos" --argjson c "$counts" \
    '{repositories:$c.repositories, git_repositories:$dirs, issues:$c.issues,
      pulls:$c.pulls, users:$c.users, comments:$c.comments, attachments:$c.attachments}'
else
  printf 'repositories: %s (git dirs: %s)\n' "$(jq -r '.repositories' <<<"$counts")" "$git_repos"
  jq -r '"issues: \(.issues)\npulls: \(.pulls)\nusers: \(.users)\ncomments: \(.comments)\nattachments: \(.attachments)"' <<<"$counts"
fi
