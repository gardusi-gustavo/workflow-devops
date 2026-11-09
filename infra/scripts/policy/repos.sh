#!/usr/bin/env bash
# Apply the canonical repository policy to every repository, regardless of owner.
# Dry run by default. Use --apply to change anything.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CONFIG="$ROOT/infra/config/policy.json"
GITEA_URL="${GITEA_URL:-http://127.0.0.1:3001}"
GITEA_TOKEN="${GITEA_TOKEN:?GITEA_TOKEN is required}"

APPLY=0
PRUNE=0

usage() {
  cat <<'EOF'
usage: repos.sh [--apply] [--prune-orgs]

  --apply       apply the policy (default: dry run)
  --prune-orgs  delete organizations with no repos and no packages
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1; shift ;;
    --prune-orgs) PRUNE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -f "$CONFIG" ]] || { echo "missing $CONFIG" >&2; exit 1; }

repo_payload="$(jq -c '.repository' "$CONFIG")"
branch_payload="$(jq -c '.branch_protection' "$CONFIG")"
branch_name="$(jq -r '.branch_protection.branch_name' "$CONFIG")"
no_ci_repos="$(jq -r '.no_ci_repos // [] | .[]' "$CONFIG")"
tag_payload="$(jq -c '.tag_protection' "$CONFIG")"
tag_patch="$(jq -c '.tag_protection | del(.name_pattern)' "$CONFIG")"
tag_pattern="$(jq -r '.tag_protection.name_pattern' "$CONFIG")"
resp="$(mktemp)"
trap 'rm -f "$resp"' EXIT

api() {
  local method="$1" path="$2" data="${3:-}"
  if [[ -n "$data" ]]; then
    curl -sS -X "$method" -H "Authorization: token $GITEA_TOKEN" \
      -H 'Content-Type: application/json' -d "$data" "$GITEA_URL/api/v1$path"
  else
    curl -sS -X "$method" -H "Authorization: token $GITEA_TOKEN" "$GITEA_URL/api/v1$path"
  fi
}

api_code() {
  local method="$1" path="$2" data="${3:-}"
  if [[ -n "$data" ]]; then
    curl -sS -o "$resp" -w '%{http_code}' -X "$method" \
      -H "Authorization: token $GITEA_TOKEN" -H 'Content-Type: application/json' \
      -d "$data" "$GITEA_URL/api/v1$path"
  else
    curl -sS -o "$resp" -w '%{http_code}' -X "$method" \
      -H "Authorization: token $GITEA_TOKEN" "$GITEA_URL/api/v1$path"
  fi
}

list_repos() {
  local page=1 limit=50 out
  while :; do
    out="$(api GET "/repos/search?limit=$limit&page=$page&mode=source")"
    jq -r '.data[].full_name' <<<"$out"
    [[ "$(jq '.data | length' <<<"$out")" -lt "$limit" ]] && break
    page=$((page + 1))
  done
}

fail=0
count=0

while IFS= read -r repo; do
  [[ -n "$repo" ]] || continue
  count=$((count + 1))
  archived="$(api GET "/repos/$repo" | jq -r '.archived // false')"
  if [[ "$archived" == "true" ]]; then
    echo "skip $repo: archived"
    continue
  fi
  if (( ! APPLY )); then
    echo "would apply $repo"
    continue
  fi

  repo_branch_payload="$branch_payload"
  if [[ -n "$no_ci_repos" ]] && grep -qxF "$repo" <<<"$no_ci_repos"; then
    repo_branch_payload="$(jq -c '.enable_status_check=false' <<<"$branch_payload")"
  fi
  rcode="$(api_code PATCH "/repos/$repo" "$repo_payload")"
  pcode="$(api_code PATCH "/repos/$repo/branch_protections/$branch_name" "$repo_branch_payload")"
  if [[ "$pcode" == "404" ]]; then
    pcode="$(api_code POST "/repos/$repo/branch_protections" "$repo_branch_payload")"
  fi

  tags="$(api GET "/repos/$repo/tag_protections")"
  tid="$(jq -r --arg p "$tag_pattern" '.[] | select(.name_pattern == $p) | .id' <<<"$tags" | head -1)"
  if [[ -n "$tid" && "$tid" != "null" ]]; then
    tcode="$(api_code PATCH "/repos/$repo/tag_protections/$tid" "$tag_patch")"
  else
    tcode="$(api_code POST "/repos/$repo/tag_protections" "$tag_payload")"
  fi

  if [[ ! "$rcode" =~ ^(200|201|204)$ || ! "$pcode" =~ ^(200|201|204)$ || ! "$tcode" =~ ^(200|201|204)$ ]]; then
    echo "FAIL $repo repo=$rcode protection=$pcode tag=$tcode" >&2
    cat "$resp" >&2 || true
    fail=1
  else
    echo "applied $repo repo=$rcode protection=$pcode tag=$tcode"
  fi
done < <(list_repos)

echo "repositories: $count"

if (( PRUNE )); then
  page=1
  limit=50
  while :; do
    out="$(api GET "/admin/orgs?limit=$limit&page=$page")"
    while IFS= read -r org; do
      [[ -n "$org" ]] || continue

      repos="$(api GET "/orgs/$org/repos?limit=1")"
      if [[ "$(jq 'length' <<<"$repos")" != "0" ]]; then
        echo "keep $org: repos"
        continue
      fi

      packages="$(api GET "/packages/$org?limit=1")"
      if [[ "$(jq 'length' <<<"$packages")" != "0" ]]; then
        echo "skip $org: packages"
        continue
      fi

      hooks="$(api GET "/orgs/$org/hooks?limit=1")"
      if [[ "$(jq 'length' <<<"$hooks")" != "0" ]]; then
        echo "skip $org: hooks"
        continue
      fi

      runners="$(api GET "/orgs/$org/actions/runners?limit=1" | jq 'if type == "array" then length else ((.runners // []) | length) end')"
      if [[ "$runners" != "0" ]]; then
        echo "skip $org: runners"
        continue
      fi

      if (( ! APPLY )); then
        echo "would delete $org"
        continue
      fi

      vars="$(api GET "/orgs/$org/actions/variables" | jq -r '.[].name' 2>/dev/null || true)"
      while IFS= read -r var; do
        [[ -n "$var" ]] || continue
        api DELETE "/orgs/$org/actions/variables/$var" >/dev/null || true
      done <<<"$vars"

      code="$(api_code DELETE "/orgs/$org")"
      if [[ "$code" == "204" || "$code" == "200" ]]; then
        echo "deleted $org"
      else
        echo "FAIL delete $org: HTTP $code" >&2
        cat "$resp" >&2 || true
        fail=1
      fi
    done < <(jq -r '.[] | (.username // .name)' <<<"$out")

    [[ "$(jq 'length' <<<"$out")" -lt "$limit" ]] && break
    page=$((page + 1))
  done
fi

exit "$fail"
