#!/usr/bin/env bash
# Migrate open bot-created Gitea issues into docs/issues JSON records.
set -euo pipefail

REPO=""
ROOT="$PWD"
MODE="dry-run"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:?}"; shift 2 ;;
    --root) ROOT="${2:?}"; shift 2 ;;
    --dry-run) MODE="dry-run"; shift ;;
    --apply) MODE="apply"; shift ;;
    --close) MODE="close"; shift ;;
    -h|--help)
      echo "usage: migrate-agent-issues.sh --repo OWNER/REPO [--root PATH] [--dry-run|--apply|--close]"
      exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$REPO" ]] || { echo "error: --repo is required" >&2; exit 2; }
[[ -d "$ROOT" ]] || { echo "error: root not found: $ROOT" >&2; exit 2; }
cd "$ROOT"
DIR="$ROOT/docs/issues"
mkdir -p "$DIR"

tmp_issues="$(mktemp)"
trap 'rm -f "$tmp_issues"' EXIT
page=1
while :; do
  batch="$(gitea-api --as human GET "/repos/$REPO/issues?state=open&type=issues&limit=50&page=$page")"
  jq -c '.[]' <<<"$batch" >> "$tmp_issues"
  count="$(jq 'length' <<<"$batch")"
  (( count < 50 )) && break
  page=$((page + 1))
done
issues="$(jq -s '.' "$tmp_issues")"
bot_count="$(jq '[.[] | select(.user.login == "bot-event")] | length' <<<"$issues")"
echo "repo: $REPO; bot issues: $bot_count; mode: $MODE"

declare -A seen=()
while IFS= read -r rank; do
  [[ -n "$rank" ]] && seen[$rank]=1
done < <(jq -r '.[] | select(.user.login != "bot-event") | .title' <<<"$issues" | sed -nE 's/^([123]\.[0-9]{1,6})[[:space:]]*-.*/\1/p')

normalize_rank() {
  local rank="$1" major frac
  major="${rank%%.*}"
  frac="${rank#*.}"
  while [[ "$frac" == *0 ]]; do frac="${frac%0}"; done
  if [[ -z "$frac" ]]; then
    rank="${major}.01"
  else
    rank="${major}.${frac}"
  fi
  while [[ -n "${seen[$rank]:-}" ]]; do
    frac="${rank#*.}"
    rank="${major}.${frac}1"
  done
  seen[$rank]=1
  RANK_OUT="$rank"
}

slugify() {
  sed -E 's/^[123]\.[0-9]{1,6}[[:space:]]*-[[:space:]]*//' \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
    | cut -c1-60
}

if [[ "$MODE" == "close" ]]; then
  jq -c '.[] | select(.user.login == "bot-event")' <<<"$issues" | while read -r issue; do
    id="$(jq -r '.number' <<<"$issue")"
    file="$(grep -l "\"issue_id\": $id" "$DIR"/*.json 2>/dev/null | head -1 || true)"
    if [[ -z "$file" ]]; then
      echo "skip #$id: no local file"
      continue
    fi
    rel="${file#"$ROOT/"}"
    body="Migrated to local work record: \`$rel\`"
    jq -n --arg body "$body" '{body:$body}' > /tmp/opencode/migrate-comment.json
    gitea-api --as human POST "/repos/$REPO/issues/$id/comments" --data @/tmp/opencode/migrate-comment.json >/dev/null
    gitea-api --as human PATCH "/repos/$REPO/issues/$id" --data '{"state":"closed"}' >/dev/null
    echo "closed #$id -> $rel"
  done
  exit 0
fi

while read -r issue; do
  id="$(jq -r '.number' <<<"$issue")"
  title="$(jq -r '.title' <<<"$issue")"
  original_rank="$(sed -nE 's/^([123]\.[0-9]{1,6})[[:space:]]*-.*/\1/p' <<<"$title")"
  if [[ -z "$original_rank" ]]; then
    echo "skip #$id: title has no valid 1.x/2.x/3.x rank: $title" >&2
    continue
  fi
  normalize_rank "$original_rank"
  rank="$RANK_OUT"
  title="$(sed -E "s/^[123]\.[0-9]{1,6}[[:space:]]*-[[:space:]]*/$rank - /" <<<"$title")"
  major="${rank%%.*}"
  case "$major" in
    3) type="bug" ;;
    2) type="documentation" ;;
    1) type="enhancement" ;;
  esac
  slug="$(slugify <<<"$title")"
  [[ -n "$slug" ]] || slug="issue-$id"
  file="$DIR/$rank-$slug.json"
  if [[ -f "$file" ]]; then
    echo "skip #$id: $file already exists"
    continue
  fi
  echo "issue #$id: $title -> ${file#"$ROOT/"}"
  if [[ "$MODE" == "apply" ]]; then
    body="$(jq -r '.body // ""' <<<"$issue")"
    created="$(jq -r '.created_at // ""' <<<"$issue" | cut -c1-10)"
    labels="$(jq -c '[.labels[].name]' <<<"$issue")"
    comments="$(jq -r '.comments // 0' <<<"$issue")"
    summary="$(jq -r '(.body // "") | split("\n") | map(select(length > 0)) | .[0] // .title' <<<"$issue")"
    original_title="$(jq -r '.title' <<<"$issue")"
    jq -n \
      --arg id "$rank" --arg rank "$rank" --arg type "$type" --arg title "$title" \
      --arg created "$created" --argjson issue_id "$id" \
      --arg url "http://gitea.localhost:3001/$REPO/issues/$id" \
      --arg summary "$summary" --arg body "$body" --argjson labels "$labels" \
      --argjson comments "$comments" --arg original_rank "$original_rank" --arg original_title "$original_title" \
      '{id:$id,rank:$rank,type:$type,title:$title,status:"backlog",source:"agent",author:"bot-event",created:$created,platform:"gitea",platform_issue_id:null,platform_issue_url:null,limits:{max_commits:5,max_file_changes:4},attempts:[],tags:($labels+["migrated"]),legacy:{issue_id:$issue_id,url:$url,author:"bot-event",created_at:$created,labels:$labels,comments_count:$comments,original_rank:$original_rank,original_title:$original_title,body:$body},spec:{summary:$summary,expected_outcome:("Migrated from Gitea issue #\($issue_id); confirm scope before starting."),acceptance_criteria:["Review the legacy body and confirm the acceptance criteria."]}}' > "$file"
    lines="$(wc -l < "$file")"
    if (( lines > 300 )); then
      echo "error: $file exceeds 300 lines ($lines)" >&2
      rm -f "$file"
      exit 1
    fi
    jq empty "$file" >/dev/null
  fi
done < <(jq -c '.[] | select(.user.login == "bot-event")' <<<"$issues")

echo "migration $MODE complete"
