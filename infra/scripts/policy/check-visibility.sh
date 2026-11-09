#!/usr/bin/env bash
# Read-only check: only organizations marked private in orgs.json may have
# private repositories.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CONFIG="$ROOT/infra/config/orgs.json"
GITEA_URL="${GITEA_URL:-http://127.0.0.1:3001}"
GITEA_TOKEN="${GITEA_TOKEN:?GITEA_TOKEN is required}"

[[ -s "$CONFIG" ]] || { echo "missing $CONFIG" >&2; exit 1; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

jq -r '.orgs[] | [.name, .visibility] | @tsv' "$CONFIG" >"$tmpdir/orgs.tsv"

fail=0
repos=0

while IFS=$'\t' read -r org visibility; do
  [[ -n "$org" ]] || continue
  page=1
  limit=50

  while :; do
    if ! json="$(curl -fsS -H "Authorization: token $GITEA_TOKEN" \
      "$GITEA_URL/api/v1/orgs/$org/repos?limit=$limit&page=$page")"; then
      echo "cannot list repos for org: $org" >&2
      fail=1
      break
    fi

    while IFS=$'\t' read -r full_name private; do
      [[ -n "$full_name" ]] || continue
      repos=$((repos + 1))
      if [[ "$visibility" == "private" && "$private" != "true" ]]; then
        echo "repo $full_name: expected private" >&2
        fail=1
      fi
      if [[ "$visibility" != "private" && "$private" == "true" ]]; then
        echo "repo $full_name: must not be private" >&2
        fail=1
      fi
    done < <(jq -r '.[] | [.full_name, (.private | tostring)] | @tsv' <<<"$json")

    count="$(jq 'length' <<<"$json")"
    (( count < limit )) && break
    page=$((page + 1))
  done
done <"$tmpdir/orgs.tsv"

if (( fail )); then
  echo "repo visibility: FAILED" >&2
  exit 1
fi

echo "repo visibility: ok ($repos repos)"
