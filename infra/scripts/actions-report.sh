#!/usr/bin/env bash
# Summarize Gitea Actions usage from the API.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REGISTRY="$ROOT/infra/config/repos.json"
GITEA_URL="${GITEA_URL:-http://127.0.0.1:3001}"
GITEA_TOKEN="${GITEA_TOKEN:-}"
DAYS=30
LIMIT=100
ONLY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days) DAYS="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    --repo) ONLY="$2"; shift 2 ;;
    -h|--help)
      echo "usage: actions-report.sh [--days N] [--limit N] [--repo group/name]"
      exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$GITEA_TOKEN" ]] || { echo "error: GITEA_TOKEN is required" >&2; exit 2; }
[[ -s "$REGISTRY" ]] || { echo "error: missing $REGISTRY" >&2; exit 2; }
command -v curl >/dev/null || { echo "error: curl is required" >&2; exit 2; }
command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 2; }

cutoff="$(date -u -d "-${DAYS} days" +%s)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf 'repo\tduration_s\tstatus\ttitle\n' > "$tmp/slow.tsv"
printf 'repo\ttitle\turl\n' > "$tmp/fail.tsv"

while IFS=$'\t' read -r group name; do
  repo="$group/$name"
  if [[ -n "$ONLY" && "$ONLY" != "$repo" ]]; then
    continue
  fi
  body="$tmp/body.json"
  code="$(curl -sS -o "$body" -w '%{http_code}' \
    -H "Authorization: token $GITEA_TOKEN" \
    "$GITEA_URL/api/v1/repos/$repo/actions/tasks?limit=$LIMIT" || true)"
  if [[ "$code" != "200" ]]; then
    echo "warn: $repo: HTTP $code" >&2
    continue
  fi

  jq -r --arg repo "$repo" --argjson cutoff "$cutoff" '
    [.workflow_runs[]?
      | select(.run_started_at != null)
      | select((.created_at | fromdateiso8601) >= $cutoff)
      | { title: .display_title, status, url,
          d: ((.updated_at | fromdateiso8601) - (.run_started_at | fromdateiso8601)),
          created_at }] as $r
    | ($r | length) as $n
    | ($r | map(select(.status == "success")) | length) as $ok
    | ($r | map(select(.status == "failure")) | length) as $fail
    | (if $n > 0 then ($r | map(.d) | add / $n | floor) else 0 end) as $avg
    | (if $n > 0 then ($r | map(.d) | max) else 0 end) as $max
    | [ $repo, $n, $ok, $fail, $avg, $max,
        (if $n > 0 then ($r | map(.created_at) | max) else "-" end) ]
    | @tsv
  ' "$body" >> "$tmp/summary.tsv"

  jq -r --arg repo "$repo" --argjson cutoff "$cutoff" '
    [.workflow_runs[]?
      | select(.run_started_at != null)
      | select((.created_at | fromdateiso8601) >= $cutoff)
      | { title: .display_title, status, url,
          d: ((.updated_at | fromdateiso8601) - (.run_started_at | fromdateiso8601)) }]
    | sort_by(.d) | reverse | .[0:3][]
    | [$repo, .d, .status, .title] | @tsv
  ' "$body" >> "$tmp/slow.tsv"

  jq -r --arg repo "$repo" --argjson cutoff "$cutoff" '
    .workflow_runs[]?
    | select(.status == "failure")
    | select((.created_at | fromdateiso8601) >= $cutoff)
    | [$repo, .display_title, .url] | @tsv
  ' "$body" >> "$tmp/fail.tsv"
done < <(jq -r --arg only "$ONLY" '
  .repos[]
  | select($only == "" or ($only == (.group + "/" + .name)))
  | [.group, .name] | @tsv
' "$REGISTRY")

# Replace the per-repo tee output above with one clean summary.
{
  printf 'repo\truns\tsuccess\tfailure\tavg_s\tmax_s\tlast\n'
  sort -u "$tmp/summary.tsv"
} > "$tmp/summary-clean.tsv"

cat "$tmp/summary-clean.tsv"
echo
echo "slowest runs"
head -1 "$tmp/slow.tsv"
tail -n +2 "$tmp/slow.tsv" | sort -t$'\t' -k2,2nr | head -10
echo
echo "failures"
head -1 "$tmp/fail.tsv"
tail -n +2 "$tmp/fail.tsv" | head -20
