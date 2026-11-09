#!/usr/bin/env bash
# Repo-local preflight for the Gitea agent. The caller must hold the per-repo
# flock; this script only validates state and never acquires or releases it.
set -euo pipefail

REPO=""
ISSUE=""
POLICY="${GITEA_AGENT_POLICY:-/srv/agent/config/policy.json}"
IDENTITY="${GITEA_IDENTITY:-bot-event}"
ENVFILE="${GITEA_ENV_FILE:-}"
RESUME=0

usage() {
  cat <<'USAGE'
usage: validate-agent-run.sh --repo OWNER/REPO [--issue N] [--identity bot-event|bot-cron|bot-manual]
                            [--policy FILE] [--resume]

Checks repo allowlist/denylist, archived state, active issue slots, working
lock, failed count, open agent PRs, issue eligibility, attempts, and PR/branch
duplication. Exit codes:
  0 ok
 10 PR cap reached
 11 failed-issue freeze
 12 repo already has an agent:working issue
 13 issue state or attempt cap
 14 repo is not eligible
 15 issue is not agent:focus/agent:hyperfocus
 16 active issue slot cap reached
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --identity) IDENTITY="${2:-}"; shift 2 ;;
    --policy) POLICY="${2:-}"; shift 2 ;;
    --resume) RESUME=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ "$REPO" =~ ^[^/]+/[^/]+$ ]] || { usage >&2; exit 2; }
[[ -z "$ISSUE" || "$ISSUE" =~ ^[0-9]+$ ]] || { echo "error: --issue must be numeric" >&2; exit 2; }
[[ -s "$POLICY" ]] || { echo "error: missing policy: $POLICY" >&2; exit 2; }

if [[ -z "$ENVFILE" ]]; then
  case "$IDENTITY" in
    bot-event) ENVFILE=/etc/gitea/automation/bot-event.env ;;
    bot-cron) ENVFILE=/etc/gitea/automation/bot-cron.env ;;
    bot-manual) ENVFILE=/etc/gitea/automation/bot-manual.env ;;
    *) echo "error: unknown identity: $IDENTITY" >&2; exit 2 ;;
  esac
fi
[[ -r "$ENVFILE" ]] || { echo "error: cannot read $ENVFILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENVFILE"
: "${GITEA_URL:?GITEA_URL missing}"
: "${GITEA_TOKEN:?GITEA_TOKEN missing}"

api_get() {
  curl -fsS -H "Authorization: token $GITEA_TOKEN" "$GITEA_URL/api/v1$1"
}

deny() {
  local code="$1" msg="$2"
  echo "deny $REPO${ISSUE:+ #$ISSUE}: $msg" >&2
  exit "$code"
}

matches_glob() {
  local value="$1" pattern="$2"
  # shellcheck disable=SC2053
  [[ "$value" == $pattern ]]
}

repo_json="$(api_get "/repos/$REPO")" || deny 14 "repository not readable"
archived="$(jq -r '.archived // false' <<<"$repo_json")"
[[ "$archived" == "false" ]] || deny 14 "repository is archived"

allowlist="$(jq -r '.agent.repo_allowlist // [] | .[]' "$POLICY" 2>/dev/null || true)"
denylist="$(jq -r '.agent.repo_denylist // [] | .[]' "$POLICY" 2>/dev/null || true)"

if [[ -n "$denylist" ]]; then
  while IFS= read -r pattern; do
    [[ -n "$pattern" ]] || continue
    if matches_glob "$REPO" "$pattern"; then
      deny 14 "repository matches denylist pattern: $pattern"
    fi
  done <<<"$denylist"
fi

if [[ -n "$allowlist" ]]; then
  allowed=0
  while IFS= read -r pattern; do
    [[ -n "$pattern" ]] || continue
    if matches_glob "$REPO" "$pattern"; then allowed=1; break; fi
  done <<<"$allowlist"
  (( allowed )) || deny 14 "repository is not in agent.repo_allowlist"
fi

max_prs="$(jq -r '.pull_requests.max_open_per_repo // 3' "$POLICY")"
max_active="$(jq -r '.agent.max_active_issues // 3' "$POLICY")"
max_working="$(jq -r '.agent.max_working_issues // 1' "$POLICY")"
max_failed="$(jq -r '.agent.max_failed_issues // 2' "$POLICY")"
max_attempts="$(jq -r '.agent.max_attempts_per_issue // 2' "$POLICY")"
max_open_prs_issue="$(jq -r '.agent.max_open_prs_per_issue // 1' "$POLICY")"
lifetime_prs="$(jq -r '.agent.lifetime_prs_per_issue // 2' "$POLICY")"

open_prs="$(api_get "/repos/$REPO/pulls?state=open&limit=100")" || deny 10 "cannot read open PRs"
open_pr_count="$(jq 'length' <<<"$open_prs")"
(( open_pr_count < max_prs )) || deny 10 "open PR cap reached ($open_pr_count/$max_prs)"

working="$(api_get "/repos/$REPO/issues?state=open&type=issues&labels=agent:working&limit=100")" || deny 12 "cannot read working issues"
working_count="$(jq 'length' <<<"$working")"
if (( working_count > 0 )); then
  if (( ! RESUME )) || [[ -z "$ISSUE" ]] || ! jq -e --argjson n "$ISSUE" '.[] | select(.number == $n)' >/dev/null <<<"$working"; then
    deny 12 "repository already has an agent:working issue"
  fi
fi
(( working_count <= max_working )) || deny 12 "working issue cap exceeded ($working_count/$max_working)"

failed="$(api_get "/repos/$REPO/issues?state=open&type=issues&labels=agent:failed&limit=100")" || deny 11 "cannot read failed issues"
failed_count="$(jq 'length' <<<"$failed")"
(( failed_count < max_failed )) || deny 11 "failed-issue freeze ($failed_count/$max_failed); human triage required"

max_focus="$(jq -r '.agent.focus_slots // 1' "$POLICY")"
max_hyper="$(jq -r '.agent.hyperfocus_slots // 2' "$POLICY")"
focus_issues="$(api_get "/repos/$REPO/issues?state=open&type=issues&labels=agent:focus&limit=100")" || deny 16 "cannot read focus issues"
hyper_issues="$(api_get "/repos/$REPO/issues?state=open&type=issues&labels=agent:hyperfocus&limit=100")" || deny 16 "cannot read hyperfocus issues"
focus_count="$(jq 'length' <<<"$focus_issues")"
hyper_count="$(jq 'length' <<<"$hyper_issues")"
active_count=$(( focus_count + hyper_count ))
(( focus_count <= max_focus )) || deny 16 "focus slot cap exceeded ($focus_count/$max_focus)"
(( hyper_count <= max_hyper )) || deny 16 "hyperfocus slot cap exceeded ($hyper_count/$max_hyper)"
(( active_count <= max_active )) || deny 16 "active issue slot cap exceeded ($active_count/$max_active)"

if [[ -z "$ISSUE" ]]; then
  echo "ok $REPO: repo preflight passed"
  exit 0
fi

issue_json="$(api_get "/repos/$REPO/issues/$ISSUE")" || deny 13 "issue not readable"
[[ "$(jq -r '.pull_request // null' <<<"$issue_json")" == "null" ]] || deny 13 "target is a pull request, not an issue"
[[ "$(jq -r '.state' <<<"$issue_json")" == "open" ]] || deny 13 "issue is not open"

labels="$(jq -r '[.labels[]?.name] | join(",")' <<<"$issue_json")"
if [[ ",$labels," == *",agent:blocked,"* ]]; then
  deny 15 "issue has agent:blocked"
fi
if [[ ",$labels," != *",agent:focus,"* && ",$labels," != *",agent:hyperfocus,"* ]]; then
  deny 15 "issue needs agent:focus or agent:hyperfocus"
fi

issue_prs="$(jq --argjson n "$ISSUE" --arg branch "bot/issue-$ISSUE" '[.[] | select((.head.ref == $branch) or ((.body // "") | test("#" + ($n|tostring) + "\\b")))] | length' <<<"$open_prs")"
(( issue_prs < max_open_prs_issue )) || deny 13 "issue already has an open PR ($issue_prs/$max_open_prs_issue)"

state_dir="${GITEA_AGENT_STATE:-/srv/agent/state}"
state_file="$state_dir/${REPO//\//__}.json"
attempts=0
lifetime=0
if [[ -r "$state_file" ]]; then
  attempts="$(jq -r --arg k "$ISSUE" '.[$k].attempts // 0' "$state_file" 2>/dev/null || echo 0)"
  lifetime="$(jq -r --arg k "$ISSUE" '.[$k].prs // 0' "$state_file" 2>/dev/null || echo 0)"
fi
[[ "$attempts" =~ ^[0-9]+$ ]] || attempts=0
[[ "$lifetime" =~ ^[0-9]+$ ]] || lifetime=0
(( attempts < max_attempts )) || deny 13 "attempt cap reached ($attempts/$max_attempts)"
(( lifetime < lifetime_prs )) || deny 13 "lifetime PR cap reached ($lifetime/$lifetime_prs)"

echo "ok $REPO #$ISSUE: preflight passed (active=$active_count/$max_active working=$working_count/$max_working failed=$failed_count/$max_failed prs=$open_pr_count/$max_prs attempts=$attempts/$max_attempts)"
