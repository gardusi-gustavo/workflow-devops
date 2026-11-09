#!/usr/bin/env bash
# Read-only check: infra/config/repos.json must match the Gitea repositories.
set -euo pipefail

ROOT="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    -h|--help) echo "usage: check-inventory.sh [--root PATH]"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done
cd "$ROOT"

CONFIG="infra/config/repos.json"
POLICY="infra/config/policy.json"
[[ -s "$CONFIG" ]] || { echo "missing $CONFIG" >&2; exit 1; }
[[ -s "$POLICY" ]] || { echo "missing $POLICY" >&2; exit 1; }
hard_cap="$(jq -r '.repositories.hard_cap // 50' "$POLICY")"
: "${GITEA_TOKEN:?GITEA_TOKEN is required}"
GITEA_URL="${GITEA_URL:-http://127.0.0.1:3001}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

expected="$tmpdir/expected"
actual="$tmpdir/actual"
jq -r '.repos[] | "\(.group)/\(.name)"' "$CONFIG" | sort > "$expected"

page=1
limit=50
while :; do
  json="$(curl -fsS -H "Authorization: token $GITEA_TOKEN" \
    "$GITEA_URL/api/v1/repos/search?limit=$limit&page=$page&mode=source")"
  jq -r '.data[].full_name' <<<"$json" >> "$actual"
  count="$(jq '.data | length' <<<"$json")"
  (( count < limit )) && break
  page=$((page + 1))
done
sort -u -o "$actual" "$actual"

missing="$(comm -23 "$expected" "$actual" || true)"
extra="$(comm -13 "$expected" "$actual" || true)"

if [[ -n "$missing" || -n "$extra" ]]; then
  [[ -n "$missing" ]] && { echo "missing from repos.json:" >&2; echo "$missing" >&2; }
  [[ -n "$extra" ]] && { echo "not in repos.json:" >&2; echo "$extra" >&2; }
  echo "repo inventory: FAILED" >&2
  exit 1
fi

count="$(wc -l < "$expected")"
if (( count > hard_cap )); then
  echo "repo inventory: FAILED ($count > hard cap $hard_cap)" >&2
  exit 1
fi
echo "repo inventory: ok ($count repos; hard cap $hard_cap)"
