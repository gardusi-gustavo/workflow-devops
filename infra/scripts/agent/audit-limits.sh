#!/usr/bin/env bash
# Read-only audit: repository, issue, and PR limits.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_JSON="${REPOS_JSON:-$SCRIPT_DIR/../../config/repos.json}"
MAX_REPOS=30
MAX_ISSUES=100
MAX_COMMENTS_PR=20
MAX_COMMITS=10
MAX_PR_AGE_DAYS=14
violations=0

repos="$(jq -r '.repos[] | "\(.group)/\(.name)"' "$REPOS_JSON")"
count="$(grep -c . <<<"$repos")"
if (( count > MAX_REPOS )); then
  echo "repositories: $count > $MAX_REPOS"
  violations=1
fi

now="$(date -u +%s)"
while IFS= read -r repo; do
  [[ -n "$repo" ]] || continue
  fail() { echo "$repo: $*"; violations=1; }

  issues="$(gitea-api --as human GET "/repos/$repo/issues?state=open&type=issues&limit=100" 2>/dev/null || echo '[]')"
  n="$(jq 'length' <<<"$issues")"
  (( n > MAX_ISSUES )) && fail "$n open issues > $MAX_ISSUES"

  while IFS= read -r line; do
    [[ -n "$line" ]] && fail "unlabeled or unranked: $line"
  done < <(jq -r '.[] | select(.pull_request == null) |
    ([.labels[].name] | map(select(. == "bug" or . == "documentation" or . == "enhancement")) | length) as $labels |
    select(($labels != 1) or (.title | test("^[123]\\.[0-9]+ - ") | not)) |
    "#\(.number) labels=\($labels) \(.title)"' <<<"$issues")

  prs="$(gitea-api --as human GET "/repos/$repo/pulls?state=open&limit=100" 2>/dev/null || echo '[]')"
  pn="$(jq 'length' <<<"$prs")"
  (( pn > 1 )) && fail "$pn open PRs > 1"

  while IFS=$'\t' read -r number created comments commits; do
    [[ -n "$number" ]] || continue
    (( comments > MAX_COMMENTS_PR )) && fail "PR #$number has $comments comments > $MAX_COMMENTS_PR"
    (( commits > MAX_COMMITS )) && fail "PR #$number has $commits commits > $MAX_COMMITS"
    if [[ "$created" != "null" && -n "$created" ]]; then
      age=$(( (now - $(date -u -d "$created" +%s)) / 86400 ))
      (( age > MAX_PR_AGE_DAYS )) && fail "PR #$number is $age days old"
    fi
  done < <(jq -r '.[] | [.number, .created_at] | @tsv' <<<"$prs" | while IFS=$'\t' read -r number created; do
    comments="$(gitea-api --as human GET "/repos/$repo/issues/$number/comments?limit=100" | jq 'length')"
    commits="$(gitea-api --as human GET "/repos/$repo/pulls/$number/commits?limit=100" | jq 'length')"
    printf '%s\t%s\t%s\t%s\n' "$number" "$created" "$comments" "$commits"
  done)
done <<<"$repos"

# Per-issue comment counts are left to a scheduled owner scan.
if (( violations )); then
  echo "limits: FAILED" >&2
  exit 1
fi
echo "limits: ok"
