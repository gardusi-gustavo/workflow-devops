#!/usr/bin/env bash
# Read-only audit: fail when bot-event performed destructive issue actions.
set -euo pipefail

DAYS=30
REPOS=()
usage() {
  cat <<'USAGE'
usage: audit-issue-authority.sh [--days N] --repo OWNER/REPO [--repo OWNER/REPO...]

Scans issue creation and timelines. Reports issues created by bot-event, plus
close, reopen, label, milestone, assignee, delete, title/body edit, lock, pin, or
project events performed by bot-event.
USAGE
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)
      [[ $# -ge 2 ]] || { echo "error: --days needs a value" >&2; exit 2; }
      DAYS="$2"; shift 2 ;;
    --repo)
      [[ $# -ge 2 ]] || { echo "error: --repo needs a value" >&2; exit 2; }
      REPOS+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done
(( ${#REPOS[@]} > 0 )) || { usage >&2; exit 2; }

ENVFILE="${GITEA_ENV_FILE:-/etc/gitea/automation/bot-event.env}"
[[ -r "$ENVFILE" ]] || { echo "error: cannot read $ENVFILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENVFILE"
: "${GITEA_URL:?GITEA_URL missing}"
: "${GITEA_TOKEN:?GITEA_TOKEN missing}"

login="$(curl -fsS -H "Authorization: token $GITEA_TOKEN" "$GITEA_URL/api/v1/user" | jq -r '.login // empty')"
[[ "$login" == "bot-event" ]] || { echo "error: audit expects bot-event token, got '$login'" >&2; exit 1; }

if [[ -n "${GITEA_TOKEN_CREATED:-}" ]]; then
  age=$(( ( $(date -u +%s) - $(date -u -d "$GITEA_TOKEN_CREATED" +%s) ) / 86400 ))
  if (( age > 90 )); then
    echo "WARN token age is ${age} days; rotate it" >&2
  fi
fi

since="$(date -u -d "-${DAYS} days" +%Y-%m-%dT%H:%M:%SZ)"
violations=0
for repo in "${REPOS[@]}"; do
  issues="$(curl -fsS -H "Authorization: token $GITEA_TOKEN" \
    "$GITEA_URL/api/v1/repos/$repo/issues?state=all&since=$since&limit=50")"

  created="$(jq -r --arg repo "$repo" --arg since "$since" '
    (. // [])[] | select(.pull_request == null) |
    select(.user.login == "bot-event") |
    select(.created_at >= $since) |
    "\($repo)#\(.number) created at \(.created_at)"' <<<"$issues")"
  if [[ -n "$created" ]]; then
    printf '%s\n' "$created"
    violations=1
  fi

  while IFS= read -r number; do
    [[ -n "$number" ]] || continue
    timeline="$(curl -fsS -H "Authorization: token $GITEA_TOKEN" \
      "$GITEA_URL/api/v1/repos/$repo/issues/$number/timeline?limit=100")"
    found="$(jq -r --arg repo "$repo" --arg n "$number" '
      (. // [])[] | select(.user.login == "bot-event") |
      select(.type == "close" or .type == "reopen" or .type == "label" or
             .type == "milestone" or .type == "assignee" or .type == "unassign" or
             .type == "delete" or .type == "change_title" or .type == "change_body" or
             .type == "lock" or .type == "unlock" or .type == "pin" or
             .type == "unpin" or .type == "project" or .type == "deadline") |
      "\($repo)#\($n) \(.type) at \(.created_at)"' <<<"$timeline")"
    if [[ -n "$found" ]]; then
      printf '%s\n' "$found"
      violations=1
    fi
  done < <(jq -r '(. // [])[].number' <<<"$issues")
done

if (( violations )); then
  echo "issue authority: FAILED" >&2
  exit 1
fi
echo "issue authority: ok"
