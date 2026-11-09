#!/usr/bin/env bash
# Read-only audit: branch protection and merge policy must match the canonical
# guardrails in every repository.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_JSON="${REPOS_JSON:-$SCRIPT_DIR/../../config/repos.json}"
violations=0

while IFS= read -r repo; do
  [[ -n "$repo" ]] || continue
  bp="$(gitea-api --as human GET "/repos/$repo/branch_protections/main" 2>/dev/null || true)"
  rp="$(gitea-api --as human GET "/repos/$repo" 2>/dev/null || true)"
  if [[ -z "$bp" || "$bp" == *'"message"'* ]]; then
    echo "$repo: missing main branch protection"
    violations=1
    continue
  fi
  fail() { echo "$repo: $*"; violations=1; }

  [[ "$(jq -r '.required_approvals' <<<"$bp")" == "1" ]] || fail "required_approvals != 1"
  [[ "$(jq -r '(.approvals_whitelist_teams // []) | index("reviewers") != null' <<<"$bp")" == "true" ]] || fail "approvals whitelist missing reviewers"
  [[ "$(jq -r '(.approvals_whitelist_username // []) | length' <<<"$bp")" == "0" ]] || fail "approvals username whitelist is not empty"
  [[ "$(jq -r '(.merge_whitelist_teams // []) | index("reviewers") != null' <<<"$bp")" == "true" ]] || fail "merge whitelist missing reviewers"
  [[ "$(jq -r '(.merge_whitelist_usernames // []) | length' <<<"$bp")" == "0" ]] || fail "merge username whitelist is not empty"
  [[ "$(jq -r '.enable_push' <<<"$bp")" == "false" ]] || fail "direct push is enabled"
  [[ "$(jq -r '.enable_force_push' <<<"$bp")" == "false" ]] || fail "force push is enabled"
  [[ "$(jq -r '.block_admin_merge_override' <<<"$bp")" == "true" ]] || fail "admin merge override is not blocked"
  [[ "$(jq -r '(.status_check_contexts // []) | index("ci / ci (pull_request)") != null' <<<"$bp")" == "true" ]] || fail "ci status check missing"
  [[ "$(jq -r '.allow_squash_merge' <<<"$rp")" == "true" ]] || fail "squash merge disabled"
  [[ "$(jq -r '.allow_rebase' <<<"$rp")" == "false" ]] || fail "rebase merge enabled"
done < <(jq -r '.repos[] | "\(.group)/\(.name)"' "$REPOS_JSON")

if (( violations )); then
  echo "guardrails: FAILED" >&2
  exit 1
fi
echo "guardrails: ok"
