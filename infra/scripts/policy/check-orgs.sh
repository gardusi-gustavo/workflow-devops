#!/usr/bin/env bash
# Read-only check: Gitea organizations match infra/config/orgs.json.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CONFIG="$ROOT/infra/config/orgs.json"
GITEA_URL="${GITEA_URL:-http://127.0.0.1:3001}"
GITEA_TOKEN="${GITEA_TOKEN:?GITEA_TOKEN is required}"

[[ -s "$CONFIG" ]] || { echo "missing $CONFIG" >&2; exit 1; }

fail=0
count=0

# shellcheck disable=SC2034  # used through indirect expansion below
while IFS=$'\t' read -r name full_name description visibility; do
  [[ -n "$name" ]] || continue
  count=$((count + 1))

  if ! actual="$(curl -fsS -H "Authorization: token $GITEA_TOKEN" "$GITEA_URL/api/v1/orgs/$name")"; then
    echo "missing org: $name" >&2
    fail=1
    continue
  fi
  if ! jq -e . >/dev/null 2>&1 <<<"$actual"; then
    echo "org $name: response is not JSON (missing or renamed)" >&2
    fail=1
    continue
  fi

  for field in full_name description visibility; do
    expected="${!field}"
    got="$(jq -r --arg field "$field" '.[$field] // ""' <<<"$actual")"
    if [[ "$got" != "$expected" ]]; then
      echo "org $name: $field expected '$expected' got '$got'" >&2
      fail=1
    fi
  done
done < <(jq -r '.orgs[] | [.name, .full_name, .description, .visibility] | @tsv' "$CONFIG")

if (( fail )); then
  echo "org metadata: FAILED" >&2
  exit 1
fi

echo "org metadata: ok ($count orgs)"
