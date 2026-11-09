#!/usr/bin/env bash
# Deterministic issue selector. The title rank is the queue; no model calls.
# 3.x bug (label bug), 2.x documentation, 1.x feature; higher fraction wins.
set -euo pipefail

MODE="select"
REPO=""
FIXTURE=""

usage() {
  cat <<'USAGE'
usage: next-issue.sh --repo OWNER/REPO [--list|--check|--json]
       next-issue.sh --repo OWNER/REPO --fixture FILE [--list|--check|--json]

Selects the highest-ranked open issue whose dependencies are all closed.
Ranked titles: 3.x bug, 2.x documentation, 1.x feature. Higher is first.
Same input, same output. No AI.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; [[ -n "$REPO" ]] || { echo "error: --repo needs a value" >&2; exit 2; }; shift 2 ;;
    --fixture) FIXTURE="${2:-}"; [[ -n "$FIXTURE" ]] || { echo "error: --fixture needs a value" >&2; exit 2; }; shift 2 ;;
    --list) MODE="list"; shift ;;
    --check) MODE="check"; shift ;;
    --json) MODE="json"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$REPO" ]] || { usage >&2; exit 2; }
[[ "$REPO" =~ ^[^/]+/[^/]+$ ]] || { echo "error: --repo must be OWNER/REPO" >&2; exit 2; }

load_env() {
  [[ -n "${GITEA_TOKEN:-}" ]] && return 0
  local envfile
  for envfile in "${GITEA_ENV_FILE:-}" /etc/gitea/automation/bot-event.env \
    /etc/gitea/automation/bot-cron.env /etc/gitea/automation/bot-manual.env \
    "$HOME/.config/gitea/env" /home/user/.config/gitea/env; do
    [[ -n "$envfile" && -r "$envfile" ]] || continue
    # shellcheck disable=SC1090
    source "$envfile"
    return 0
  done
  return 1
}

api_get() {
  load_env || { echo "error: GITEA_TOKEN missing" >&2; exit 1; }
  : "${GITEA_URL:?GITEA_URL missing}"
  curl -fsS -H "Authorization: token $GITEA_TOKEN" "${GITEA_URL%/}/api/v1$1"
}

fetch_issues() {
  if [[ -n "$FIXTURE" ]]; then
    [[ -r "$FIXTURE" ]] || { echo "error: cannot read fixture: $FIXTURE" >&2; exit 2; }
    jq -c 'if type == "object" then (.issues // []) else . end' "$FIXTURE"
  else
    api_get "/repos/$REPO/issues?state=open&type=issues&limit=50"
  fi
}

# Prints "number<TAB>state" for each dependency.
fetch_deps() {
  if [[ -n "$FIXTURE" ]]; then
    jq -r --argjson n "$1" '
      (if type == "object" then (.issues // []) else . end) |
      map(select(.number == $n)) | .[0].dependencies // [] |
      .[] | if type == "object" then "\(.number)\t\(.state // "open")" else "\(.)\topen" end
    ' "$FIXTURE"
  else
    api_get "/repos/$REPO/issues/$1/dependencies" | jq -r '.[] | "\(.number)\t\(.state)"'
  fi
}

slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-48
}

issues="$(fetch_issues)"
[[ -n "$issues" ]] || issues='[]'
candidates="$(jq -r '.[] | select((.pull_request // null) == null) |
  [.number, .title, ([.labels[]? | if type == "object" then .name else . end] | join(","))] | @tsv' <<<"$issues")"

errors=0
declare -A seen_rank=()
records=()
while IFS=$'\t' read -r number title labels; do
  [[ -n "$number" ]] || continue
  [[ "$title" =~ ^[0-9]+(\.[0-9]*)?\ -\  ]] || continue
  if [[ ! "$title" =~ ^([0-9]+)\.([0-9]+)\ -\ .+ ]]; then
    echo "ERROR: #$number malformed rank (need '<type>.<priority> - title'): $title" >&2
    errors=$((errors + 1)); continue
  fi
  type="${BASH_REMATCH[1]}"; fraction="${BASH_REMATCH[2]}"
  if [[ "$type" != "1" && "$type" != "2" && "$type" != "3" ]]; then
    echo "ERROR: #$number type must be 1, 2, or 3: $title" >&2
    errors=$((errors + 1)); continue
  fi
  if (( ${#fraction} > 6 )); then
    echo "ERROR: #$number rank has more than 6 decimals: $title" >&2
    errors=$((errors + 1)); continue
  fi
  if [[ "$fraction" != "0" && "$fraction" == *0 ]]; then
    echo "ERROR: #$number trailing zero in rank (3.1, not 3.10): $title" >&2
    errors=$((errors + 1)); continue
  fi
  rank="$type.$fraction"
  if [[ -n "${seen_rank[$rank]:-}" ]]; then
    echo "ERROR: duplicate rank $rank: #${seen_rank[$rank]} and #$number" >&2
    errors=$((errors + 1)); continue
  fi
  seen_rank[$rank]="$number"
  case "$type" in 3) want=bug ;; 2) want=documentation ;; 1) want=enhancement ;; esac
  if [[ ",$labels," != *",$want,"* ]]; then
    echo "ERROR: #$number rank $rank requires label '$want' (labels: ${labels:-none})" >&2
    errors=$((errors + 1)); continue
  fi
  records+=("$rank"$'\t'"$number"$'\t'"$title"$'\t'"${labels:-}")
done <<<"$candidates"

if (( errors > 0 )); then
  echo "ERROR: issue queue has $errors problem(s); fix ranks before selecting" >&2
  exit 1
fi

sorted="$(printf '%s\n' "${records[@]:-}" | sed '/^$/d' | LC_ALL=C sort -r)"
if [[ "$MODE" == "check" ]]; then
  echo "queue ok: $(printf '%s\n' "$sorted" | sed '/^$/d' | wc -l) ranked issue(s) in $REPO"
  exit 0
fi

found=""
queue=()
while IFS=$'\t' read -r rank number title labels; do
  [[ -n "${rank:-}" ]] || continue
  deps="$(fetch_deps "$number")" || { echo "ERROR: cannot read dependencies for #$number" >&2; exit 1; }
  if grep -q $'\topen$' <<<"$deps"; then
    queue+=("BLOCKED"$'\t'"$rank"$'\t'"$number"$'\t'"$title"); continue
  fi
  queue+=("READY"$'\t'"$rank"$'\t'"$number"$'\t'"$title")
  [[ -n "$found" ]] || found="$rank"$'\t'"$number"$'\t'"$title"$'\t'"$labels"
done <<<"$sorted"

if [[ "$MODE" == "list" ]]; then
  (( ${#queue[@]} )) || { echo "no ranked issues in $REPO"; exit 0; }
  printf '%s\n' "${queue[@]}" | while IFS=$'\t' read -r state rank number title; do
    printf '%-8s %-6s #%-5s %s\n' "$state" "$rank" "$number" "$title"
  done
  exit 0
fi

if [[ -z "$found" ]]; then
  if [[ "$MODE" == "json" ]]; then echo '{"issue":null,"reason":"no unblocked ranked issue"}'
  else echo "no unblocked ranked issue in $REPO" >&2; fi
  exit 1
fi

IFS=$'\t' read -r rank number title labels <<<"$found"
branch="issue-$number-$(slug "$title")"
if [[ "$MODE" == "json" ]]; then
  jq -nc --arg repo "$REPO" --arg rank "$rank" --argjson number "$number" \
    --arg title "$title" --arg labels "$labels" --arg branch "$branch" \
    '{repo:$repo,rank:$rank,number:$number,title:$title,labels:($labels|split(",")|map(select(length>0))),branch:$branch}'
  exit 0
fi
printf '#%s  %s\n     labels: %s\n     branch: %s\n' "$number" "$title" "${labels:-none}" "$branch"
