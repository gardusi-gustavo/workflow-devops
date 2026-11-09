#!/usr/bin/env bash
# Read-only audit: fail when a repository has more than one open pull request.
set -euo pipefail

MAX=1
REPOS=()
usage() {
  cat <<'USAGE'
usage: audit-pr-authority.sh [--max N] --repo OWNER/REPO [--repo OWNER/REPO...]

Reports repositories with more than N open pull requests and open PRs that do
not reference an open issue. It never closes or edits anything.
USAGE
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --max)
      [[ $# -ge 2 ]] || { echo "error: --max needs a value" >&2; exit 2; }
      MAX="$2"; shift 2 ;;
    --repo)
      [[ $# -ge 2 ]] || { echo "error: --repo needs a value" >&2; exit 2; }
      REPOS+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done
(( ${#REPOS[@]} > 0 )) || { usage >&2; exit 2; }
[[ "$MAX" =~ ^[0-9]+$ ]] || { echo "error: --max must be a number" >&2; exit 2; }

ENVFILE="${GITEA_ENV_FILE:-/etc/gitea/automation/bot-event.env}"
[[ -r "$ENVFILE" ]] || { echo "error: cannot read $ENVFILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENVFILE"
: "${GITEA_URL:?GITEA_URL missing}"
: "${GITEA_TOKEN:?GITEA_TOKEN missing}"

login="$(curl -fsS -H "Authorization: token $GITEA_TOKEN" "$GITEA_URL/api/v1/user" | jq -r '.login // empty')"
[[ "$login" == "bot-event" ]] || { echo "error: audit expects bot-event token, got '$login'" >&2; exit 1; }

violations=0
for repo in "${REPOS[@]}"; do
  prs="$(curl -fsS -H "Authorization: token $GITEA_TOKEN" \
    "$GITEA_URL/api/v1/repos/$repo/pulls?state=open&limit=100")"
  count="$(jq 'length' <<<"$prs")"
  if (( count > MAX )); then
    violations=1
    echo "$repo: $count open pull requests (max $MAX)"
    jq -r '.[] | "  #\(.number) [\(.user.login)] \(.head.ref): \(.title)"' <<<"$prs"
  fi

  while IFS= read -r number; do
    [[ -n "$number" ]] || continue
    body="$(jq -r --argjson n "$number" '.[] | select(.number == $n) | .body // ""' <<<"$prs")"
    refs="$(grep -oE '#[0-9]+' <<<"$body" | tr -d '#' | sort -u || true)"
    linked=0
    for ref in $refs; do
      meta="$(curl -fsS -H "Authorization: token $GITEA_TOKEN" \
        "$GITEA_URL/api/v1/repos/$repo/issues/$ref" 2>/dev/null || true)"
      is_pr="$(jq -r '(.pull_request // null) != null' <<<"$meta" 2>/dev/null || echo true)"
      state="$(jq -r '.state // empty' <<<"$meta" 2>/dev/null || true)"
      if [[ "$is_pr" == "false" && "$state" == "open" ]]; then
        linked=1
        break
      fi
    done
    if (( ! linked )); then
      violations=1
      echo "$repo: PR #$number does not reference an open issue"
    fi
  done < <(jq -r '.[].number' <<<"$prs")
done

if (( violations )); then
  echo "PR authority: FAILED" >&2
  exit 1
fi
echo "PR authority: ok"
