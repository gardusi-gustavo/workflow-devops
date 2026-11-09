#!/usr/bin/env bash
# PR creator workflow: lock -> next issue -> branch -> context -> ship.
# Deterministic selection and guards. The AI writes code; this script decides
# what to work on and whether the next step is allowed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEXT_ISSUE="${NEXT_ISSUE_BIN:-$SCRIPT_DIR/next-issue.sh}"
PR_LIMIT="${PR_LIMIT_BIN:-$SCRIPT_DIR/pr-limit.sh}"

MODE="dry-run"
REPO=""
PATH_OVERRIDE=""

usage() {
  cat <<'USAGE'
usage: next-work.sh --repo OWNER/REPO [--path PATH] [--dry-run|--start|--ship]

  --dry-run  print the next issue and branch (default)
  --start    verify the lane, create the branch, write the context file
  --ship     verify the lane, run repo CI, push, open one PR with Closes #N

Context file: ${NEXT_WORK_CONTEXT_DIR:-$HOME/work/<owner>-<repo>}/issue-<n>.md
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; [[ -n "$REPO" ]] || { echo "error: --repo needs a value" >&2; exit 2; }; shift 2 ;;
    --path) PATH_OVERRIDE="${2:-}"; [[ -n "$PATH_OVERRIDE" ]] || { echo "error: --path needs a value" >&2; exit 2; }; shift 2 ;;
    --dry-run) MODE="dry-run"; shift ;;
    --start) MODE="start"; shift ;;
    --ship) MODE="ship"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$REPO" ]] || { usage >&2; exit 2; }
[[ "$REPO" =~ ^[^/]+/[^/]+$ ]] || { echo "error: --repo must be OWNER/REPO" >&2; exit 2; }

REPO_PATH="${PATH_OVERRIDE:-$HOME/repos/$REPO}"
[[ -d "$REPO_PATH/.git" ]] || { echo "error: not a git clone: $REPO_PATH" >&2; exit 2; }

lane_status() {
  if "$PR_LIMIT" status --repo "$REPO" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

require_clear_lane() {
  if ! lane_status; then
    echo "stop: $REPO already has an open pull request." >&2
    echo "Review, merge, or close it before opening another." >&2
    exit 1
  fi
}

top="$("$NEXT_ISSUE" --repo "$REPO" --json)"
number="$(jq -r '.number // empty' <<<"$top")"
[[ -n "$number" ]] || { echo "stop: no unblocked ranked issue in $REPO" >&2; exit 1; }
rank="$(jq -r '.rank' <<<"$top")"
title="$(jq -r '.title' <<<"$top")"
branch="$(jq -r '.branch' <<<"$top")"

if [[ "$MODE" == "dry-run" ]]; then
  printf 'repo:   %s\n' "$REPO"
  printf 'issue:  #%s %s\n' "$number" "$title"
  printf 'rank:   %s\n' "$rank"
  printf 'branch: %s\n' "$branch"
  printf 'path:   %s\n' "$REPO_PATH"
  if ! lane_status; then
    echo "lane:   occupied (start/ship will stop)"
  else
    echo "lane:   clear"
  fi
  exit 0
fi

require_clear_lane

if [[ "$MODE" == "start" ]]; then
  git -C "$REPO_PATH" fetch origin --quiet
  if git -C "$REPO_PATH" show-ref --verify --quiet "refs/heads/$branch"; then
    echo "stop: branch already exists: $branch" >&2
    exit 1
  fi
  git -C "$REPO_PATH" switch -c "$branch" origin/main >/dev/null
  context_dir="${NEXT_WORK_CONTEXT_DIR:-$HOME/work/${REPO%%/*}-${REPO##*/}}"
  mkdir -p "$context_dir"
  context_file="$context_dir/issue-$number.md"
  body="$(gitea-api GET "/repos/$REPO/issues/$number" | jq -r '.body // ""')"
  {
    printf '# Issue #%s — %s\n\n' "$number" "$title"
    printf -- '- Repo: `%s`\n' "$REPO"
    printf -- '- Rank: `%s`\n' "$rank"
    printf -- '- Branch: `%s`\n' "$branch"
    printf -- '- Path: `%s`\n\n' "$REPO_PATH"
    printf '## Issue body\n\n'
    printf '```text\n'
    printf '%s\n' "$body"
    printf '```\n\n'
    printf '## Guardrails\n\n'
    printf -- '- Read `AGENTS.md` and `docs/repository/issues.md` before editing.\n'
    printf -- '- One open PR per repo; this branch is the only lane.\n'
    printf -- '- Diff budget: 12 files / 500 lines / 250 per file / 1 binary / 12 commits.\n'
    printf -- '- Do not approve or merge. Hand the PR to `human`.\n'
  } > "$context_file"
  echo "started $branch"
  echo "context: $context_file"
  exit 0
fi

# --ship
current="$(git -C "$REPO_PATH" branch --show-current)"
[[ "$current" == "$branch" ]] || {
  echo "stop: expected branch $branch, found ${current:-detached HEAD}" >&2
  exit 1
}
if [[ -n "$(git -C "$REPO_PATH" status --porcelain)" ]]; then
  echo "stop: working tree is dirty; commit or stash first" >&2
  exit 1
fi
if [[ -x "$REPO_PATH/infra/scripts/ci.sh" ]]; then
  ( cd "$REPO_PATH" && bash infra/scripts/ci.sh )
fi
git -C "$REPO_PATH" push -u origin "$branch" >/dev/null
body="$(printf 'Closes #%s\n\nRank: `%s`\n' "$number" "$rank")"
gitea-api POST "/repos/$REPO/pulls" --data "$(jq -nc --arg h "$branch" --arg t "$title" --arg b "$body" '{head:$h,base:"main",title:$t,body:$b}')" >/dev/null
echo "shipped $branch -> PR for #$number"
