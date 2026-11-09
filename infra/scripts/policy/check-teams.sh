#!/usr/bin/env bash
# Read-only check: every organization has the expected teams and members.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CONFIG="$ROOT/infra/config/orgs.json"
GITEA_URL="${GITEA_URL:-http://127.0.0.1:3001}"
GITEA_TOKEN="${GITEA_TOKEN:-}"

[[ -s "$CONFIG" ]] || { echo "missing $CONFIG" >&2; exit 1; }
if [[ -z "$GITEA_TOKEN" ]]; then
  echo "teams: SKIP (GITEA_TOKEN missing)" >&2
  exit 2
fi

fail=0
count=0

check_team() {
  local org="$1" team="$2" expected="$3"
  local teams id members actual
  teams="$(curl -fsS -H "Authorization: token $GITEA_TOKEN" "$GITEA_URL/api/v1/orgs/$org/teams")" || {
    echo "org $org: cannot list teams" >&2
    return 1
  }
  if ! jq -e . >/dev/null 2>&1 <<<"$teams"; then
    echo "org $org: teams response is not JSON (missing or renamed)" >&2
    return 1
  fi
  id="$(jq -r --arg t "$team" '.[] | select(.name == $t) | .id' <<<"$teams" | head -1)"
  if [[ -z "$id" ]]; then
    echo "org $org: missing team $team" >&2
    return 1
  fi
  if [[ "$(jq -r --arg t "$team" '.[] | select(.name == $t) | .includes_all_repositories' <<<"$teams")" != "true" ]]; then
    echo "org $org: team $team does not include all repositories" >&2
    fail=1
  fi
  members="$(curl -fsS -H "Authorization: token $GITEA_TOKEN" "$GITEA_URL/api/v1/teams/$id/members")" || {
    echo "org $org: cannot list members for $team" >&2
    return 1
  }
  actual="$(jq -r '.[].login' <<<"$members" | sort | paste -sd, -)"
  if [[ "$actual" != "$expected" ]]; then
    echo "org $org: team $team members expected '$expected' got '$actual'" >&2
    fail=1
  fi
}

while IFS= read -r org; do
  [[ -n "$org" ]] || continue
  count=$((count + 1))
  check_team "$org" Owners "human"
  check_team "$org" reviewers "human"
  check_team "$org" contributors "bot-cron,bot-event,bot-manual"
done < <(jq -r '.orgs[].name' "$CONFIG")

if (( fail )); then
  echo "teams: FAILED" >&2
  exit 1
fi
echo "teams: ok ($count orgs)"
