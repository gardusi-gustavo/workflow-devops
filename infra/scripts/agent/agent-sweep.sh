#!/usr/bin/env bash
# Scheduled bot-cron sweep. Processes hyperfocus work only in repos that have
# no focus or working issue, one issue per repo, bounded by a per-run cap.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY="${GITEA_AGENT_POLICY:-/srv/agent/config/policy.json}"
ENVFILE="${GITEA_ENV_FILE:-/etc/gitea/automation/bot-cron.env}"
MAX_REPOS="${GITEA_AGENT_SWEEP_MAX:-3}"
MODEL="${GITEA_AGENT_MODEL:-deepseek/deepseek-flash}"
TIMEOUT="${GITEA_AGENT_TIMEOUT_MINUTES:-60}"

[[ -s "$POLICY" ]] || { echo "error: missing policy: $POLICY" >&2; exit 2; }
[[ -r "$ENVFILE" ]] || { echo "error: cannot read $ENVFILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENVFILE"
: "${GITEA_URL:?GITEA_URL missing}"
: "${GITEA_TOKEN:?GITEA_TOKEN missing}"

API="$GITEA_URL/api/v1"
api_get() { curl -fsS -H "Authorization: token $GITEA_TOKEN" "$API$1"; }

allowlist="$(jq -r '.agent.repo_allowlist // [] | .[]' "$POLICY")"
denylist="$(jq -r '.agent.repo_denylist // [] | .[]' "$POLICY")"

matches_glob() {
  local value="$1" pattern="$2"
  # shellcheck disable=SC2053
  [[ "$value" == $pattern ]]
}

eligible=0
processed=0
repos="$(api_get "/repos/search?limit=50&mode=source" | jq -r '.data[] | select(.archived==false) | .full_name')"

for repo in $repos; do
  if [[ -n "$denylist" ]]; then
    skip=0
    while IFS= read -r pattern; do
      [[ -n "$pattern" ]] || continue
      if matches_glob "$repo" "$pattern"; then skip=1; break; fi
    done <<<"$denylist"
    (( skip )) && continue
  fi
  if [[ -n "$allowlist" ]]; then
    allowed=0
    while IFS= read -r pattern; do
      [[ -n "$pattern" ]] || continue
      if matches_glob "$repo" "$pattern"; then allowed=1; break; fi
    done <<<"$allowlist"
    (( allowed )) || continue
  fi

  focus="$(api_get "/repos/$repo/issues?state=open&type=issues&labels=agent:focus&limit=100" | jq 'length')"
  working="$(api_get "/repos/$repo/issues?state=open&type=issues&labels=agent:working&limit=100" | jq 'length')"
  hyper="$(api_get "/repos/$repo/issues?state=open&type=issues&labels=agent:hyperfocus&limit=100" | jq 'length')"
  (( hyper > 0 )) || continue
  (( eligible++ ))
  if (( focus > 0 || working > 0 )); then
    echo "skip $repo: focus=$focus working=$working"
    continue
  fi

  echo "sweep $repo: hyperfocus=$hyper"
  "$SCRIPT_DIR/agent-trigger.sh" --repo "$repo" --next --target hyperfocus --identity bot-cron --policy "$POLICY" --model "$MODEL" --timeout "$TIMEOUT" || true
  processed=$((processed + 1))
  (( processed >= MAX_REPOS )) && break
done

echo "sweep done: eligible=$eligible processed=$processed cap=$MAX_REPOS"
