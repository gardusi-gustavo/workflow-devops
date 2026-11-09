#!/usr/bin/env bash
# Manual event-driven agent trigger. One repository lock, one issue at a time.
# The orchestrator owns the Gitea token; OpenCode never sees it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY="${GITEA_AGENT_POLICY:-/srv/agent/config/policy.json}"
REPO=""
ISSUE=""
IDENTITY="${GITEA_IDENTITY:-bot-event}"
MODE="one"
TARGET="${GITEA_AGENT_TARGET:-focus}"
DRY_RUN=0
MODEL="${GITEA_AGENT_MODEL:-deepseek/deepseek-flash}"
MAX_RUNTIME="${GITEA_AGENT_TIMEOUT_MINUTES:-60}"
OPCODE="${OPENCODE_BIN:-/usr/local/lib/opencode/opencode}"
AGENT_HOME="${GITEA_AGENT_HOME:-/srv/agent}"
SELF="${BASH_SOURCE[0]}"

usage() {
  cat <<'USAGE'
usage: agent-trigger.sh --repo OWNER/REPO [--issue N | --next | --all-ready]
                        [--identity bot-event|bot-cron|bot-manual]
                        [--dry-run] [--model PROVIDER/MODEL]
                        [--timeout MINUTES] [--policy FILE]

Examples:
  agent-trigger.sh --repo templates/sh --issue 12
  agent-trigger.sh --repo templates/sh --next --identity bot-event
  agent-trigger.sh --repo templates/sh --all-ready
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --issue) ISSUE="${2:-}"; shift 2 ;;
    --next) MODE="next"; shift ;;
    --all-ready) MODE="all"; shift ;;
    --identity) IDENTITY="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --model) MODEL="${2:-}"; shift 2 ;;
    --timeout) MAX_RUNTIME="${2:-}"; shift 2 ;;
    --policy) POLICY="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ "$REPO" =~ ^[^/]+/[^/]+$ ]] || { usage >&2; exit 2; }
[[ "$IDENTITY" =~ ^bot-(event|cron|manual)$ ]] || { echo "error: identity must be bot-event, bot-cron, or bot-manual" >&2; exit 2; }
[[ "$TARGET" =~ ^(focus|hyperfocus|any)$ ]] || { echo "error: target must be focus, hyperfocus, or any" >&2; exit 2; }
[[ -s "$POLICY" ]] || { echo "error: missing policy: $POLICY" >&2; exit 2; }

ME="$(id -un)"
if [[ "$ME" != "root" && "$ME" != "gitea-automation" ]]; then
  echo "error: run as root or gitea-automation" >&2
  exit 2
fi

ENVFILE="/etc/gitea/automation/$IDENTITY.env"
[[ -r "$ENVFILE" ]] || { echo "error: cannot read $ENVFILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENVFILE"
: "${GITEA_URL:?GITEA_URL missing}"
: "${GITEA_TOKEN:?GITEA_TOKEN missing}"

# Used by agent-lib.sh
# shellcheck disable=SC2034
API="$GITEA_URL/api/v1"
# shellcheck disable=SC2034
API_ERR_LOG="$AGENT_HOME/logs/api-errors.log"
# shellcheck source=agent-lib.sh
source "$SCRIPT_DIR/agent-lib.sh"

if [[ "$MODE" == "all" ]]; then
  case "$TARGET" in
    focus) numbers="$(list_label 'agent:focus' | jq -r '.[].number' | sort -n -u)" ;;
    hyperfocus) numbers="$(list_label 'agent:hyperfocus' | jq -r '.[].number' | sort -n -u)" ;;
    any) numbers="$( { list_label 'agent:focus'; list_label 'agent:hyperfocus'; } | jq -r '.[].number' | sort -n -u )" ;;
  esac
  [[ -n "$numbers" ]] || { echo "no $TARGET agent issues in $REPO"; exit 0; }
  for n in $numbers; do
    "$SELF" --repo "$REPO" --issue "$n" --identity "$IDENTITY" --target "$TARGET" --policy "$POLICY" --model "$MODEL" --timeout "$MAX_RUNTIME" || true
  done
  exit 0
fi

if [[ -z "$ISSUE" ]]; then
  ISSUE="$(select_issue)"
  [[ -n "$ISSUE" ]] || { echo "no agent:focus/agent:hyperfocus issue in $REPO"; exit 0; }
fi
[[ "$ISSUE" =~ ^[0-9]+$ ]] || { echo "error: invalid issue number: $ISSUE" >&2; exit 2; }

LOCK_DIR="$AGENT_HOME/locks"
mkdir -p "$LOCK_DIR"
LOCK="$LOCK_DIR/${REPO//\//__}.lock"
exec 9>"$LOCK"
if ! flock -n 9; then
  echo "busy $REPO: another agent run holds the repository lock"
  exit 0
fi

# The lock is held from preflight through push/PR creation.
if ! GITEA_IDENTITY="$IDENTITY" GITEA_ENV_FILE="$ENVFILE" GITEA_AGENT_POLICY="$POLICY" \
  bash "$SCRIPT_DIR/validate-agent-run.sh" --repo "$REPO" --issue "$ISSUE" --identity "$IDENTITY" --policy "$POLICY"; then
  exit $?
fi

issue_json="$(api_get "/repos/$REPO/issues/$ISSUE")"
TITLE="$(jq -r '.title' <<<"$issue_json")"
BODY="$(jq -r '.body // ""' <<<"$issue_json")"
LABELS="$(jq -r '[.labels[]?.name] | join(",")' <<<"$issue_json")"

REPO_DIR="$AGENT_HOME/repos/$REPO"
mkdir -p "$(dirname "$REPO_DIR")"
if [[ ! -d "$REPO_DIR/.git" ]]; then
  GIT_ASKPASS="$AGENT_HOME/bin/git-askpass.sh" GITEA_GIT_USER="$IDENTITY" GITEA_TOKEN="$GITEA_TOKEN" \
    git clone --quiet "$GITEA_URL/$REPO.git" "$REPO_DIR"
fi
git -C "$REPO_DIR" fetch origin --prune --quiet
git -C "$REPO_DIR" checkout -B "bot/issue-$ISSUE" origin/main --quiet
git -C "$REPO_DIR" reset --hard origin/main --quiet
git -C "$REPO_DIR" clean -fdx --quiet
git -C "$REPO_DIR" config user.name "$IDENTITY"
git -C "$REPO_DIR" config user.email "$IDENTITY@gitea.localhost"

CONTEXT_DIR="$AGENT_HOME/workspaces"
mkdir -p "$CONTEXT_DIR"
CONTEXT="$CONTEXT_DIR/${REPO//\//__}-issue-$ISSUE.md"
{
  printf '# %s #%s\n\n' "$REPO" "$ISSUE"
  printf 'Title: %s\n\n' "$TITLE"
  printf 'Labels: %s\n\n' "$LABELS"
  printf 'Work only inside this repository. Read AGENTS.md and the relevant docs first.\n'
  printf 'Do not push, tag, merge, approve, or run sudo/ssh/curl. Do not access /home or /etc.\n'
  printf 'Implement the issue, run the repository tests or CI if available, and leave the changes uncommitted.\n\n'
  printf '## Issue body\n\n%s\n' "$BODY"
} > "$CONTEXT"
chown gitea-automation:gitea-automation "$CONTEXT"

STATE_FILE="$AGENT_HOME/state/${REPO//\//__}.json"
attempts=0
lifetime=0
if [[ -r "$STATE_FILE" ]]; then
  attempts="$(jq -r --arg k "$ISSUE" '.[$k].attempts // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
  lifetime="$(jq -r --arg k "$ISSUE" '.[$k].prs // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
fi
attempts=$((attempts + 1))
tmp_state="$(mktemp)"
jq --arg k "$ISSUE" --argjson a "$attempts" '
  .[$k] = ((.[$k] // {}) + {attempts:$a, updated:(now|todate)})
' "$STATE_FILE" 2>/dev/null > "$tmp_state" || jq -n --arg k "$ISSUE" --argjson a "$attempts" '{($k):{attempts:$a, prs:0, updated:(now|todate)}}' > "$tmp_state"
mv "$tmp_state" "$STATE_FILE"
chown gitea-automation:gitea-automation "$STATE_FILE"

# Claim the issue visibly.
api_post "/repos/$REPO/issues/$ISSUE/labels" '{"labels":["agent:working"]}' >/dev/null || true

LOG="$AGENT_HOME/logs/${REPO//\//__}-issue-$ISSUE-$(date -u +%Y%m%dT%H%M%SZ).log"
PROMPT="Implement $REPO issue #$ISSUE: $TITLE. Work only inside the current repository. Read AGENTS.md first. Do not push, tag, merge, or access /home or /etc. Run the relevant tests. Leave changes uncommitted and print a concise summary with changed files."

set +e
run_agent "$REPO_DIR" timeout "${MAX_RUNTIME}m" "$OPCODE" --standalone run \
  --agent bot --format json --model "$MODEL" \
  --title "$REPO #$ISSUE" --file "$CONTEXT" "$PROMPT" >"$LOG" 2>&1
rc=$?
set -e

finish_fail() {
  local reason="$1"
  if (( attempts >= 2 )); then
    api_post "/repos/$REPO/issues/$ISSUE/labels" '{"labels":["agent:failed"]}' >/dev/null || true
  fi
  local keep
  keep="$(api_get "/repos/$REPO/issues/$ISSUE" | jq -c '[.labels[]?.name | select(. != "agent:working")]')"
  api_put "/repos/$REPO/issues/$ISSUE/labels" "$(jq -nc --argjson l "$keep" '{labels:$l}')" >/dev/null || true
  api_post "/repos/$REPO/issues/$ISSUE/comments" "$(jq -nc --arg b "Agent run failed (attempt $attempts): $reason" '{body:$b}')" >/dev/null || true
  echo "failed $REPO #$ISSUE: $reason" >&2
  exit 1
}

if (( rc != 0 )); then
  finish_fail "opencode exit $rc; see $LOG"
fi

if [[ -z "$(git -C "$REPO_DIR" status --porcelain)" ]]; then
  finish_fail "no changes produced; see $LOG"
fi

git -C "$REPO_DIR" add -A
git -C "$REPO_DIR" commit -q -m "Fixes #$ISSUE: $TITLE" || finish_fail "commit failed"

if [[ -x "$SCRIPT_DIR/pr-size.sh" ]]; then
  if ! "$SCRIPT_DIR/pr-size.sh" check --repo "$REPO" --branch "bot/issue-$ISSUE" --head HEAD --base origin/main --repo-root "$REPO_DIR" --policy "$POLICY" >/dev/null 2>&1; then
    finish_fail "diff budget exceeded"
  fi
fi

if [[ -x "$REPO_DIR/infra/scripts/ci.sh" ]]; then
  if ! ( cd "$REPO_DIR" && timeout "${MAX_RUNTIME}m" bash infra/scripts/ci.sh ) >>"$LOG" 2>&1; then
    finish_fail "repository CI failed; see $LOG"
  fi
fi

if (( DRY_RUN )); then
  git -C "$REPO_DIR" diff --stat origin/main...HEAD
  echo "dry-run $REPO #$ISSUE: changes validated locally; not pushed"
  keep="$(api_get "/repos/$REPO/issues/$ISSUE" | jq -c '[.labels[]?.name | select(. != "agent:working")]')"
  api_put "/repos/$REPO/issues/$ISSUE/labels" "$(jq -nc --argjson l "$keep" '{labels:$l}')" >/dev/null || true
  api_post "/repos/$REPO/issues/$ISSUE/comments" '{"body":"Agent dry-run completed; no branch or PR was created."}' >/dev/null || true
  exit 0
fi

GIT_ASKPASS="$AGENT_HOME/bin/git-askpass.sh" GITEA_GIT_USER="$IDENTITY" GITEA_TOKEN="$GITEA_TOKEN" \
  git -C "$REPO_DIR" push -u origin "bot/issue-$ISSUE" >/dev/null 2>&1 || finish_fail "push failed"

pr_payload="$(jq -nc --arg h "bot/issue-$ISSUE" --arg t "Fix #$ISSUE: $TITLE" --arg b "Closes #$ISSUE

Automated by \`$IDENTITY\`." '{head:$h,base:"main",title:$t,body:$b}')"
export GITEA_IDENTITY="$IDENTITY"
pr_json="$("$SCRIPT_DIR/gitea-api.sh" POST "/repos/$REPO/pulls" --data "$pr_payload")" || finish_fail "PR creation failed"
PR_NUMBER="$(jq -r '.number // empty' <<<"$pr_json")"
[[ -n "$PR_NUMBER" ]] || finish_fail "PR response had no number"

"$SCRIPT_DIR/gitea-api.sh" POST "/repos/$REPO/pulls/$PR_NUMBER/requested_reviewers" --data '{"reviewers":["human"]}' >/dev/null 2>&1 || true
"$SCRIPT_DIR/gitea-api.sh" POST "/repos/$REPO/issues/$PR_NUMBER/labels" --data '{"labels":["agent"]}' >/dev/null 2>&1 || true

# Remove the working claim while preserving the rest of the issue labels.
current_labels="$(api_get "/repos/$REPO/issues/$ISSUE" | jq -c '[.labels[]?.name | select(. != "agent:working")]')"
api_put "/repos/$REPO/issues/$ISSUE/labels" "$(jq -nc --argjson l "$current_labels" '{labels:$l}')" >/dev/null || true
api_post "/repos/$REPO/issues/$ISSUE/comments" "$(jq -nc --arg b "Opened PR #$PR_NUMBER for review by \`human\`." '{body:$b}')" >/dev/null || true

lifetime=$((lifetime + 1))
tmp_state="$(mktemp)"
jq --arg k "$ISSUE" --argjson a "$attempts" --argjson l "$lifetime" '
  .[$k] = ((.[$k] // {}) + {attempts:$a, prs:$l, updated:(now|todate)})
' "$STATE_FILE" > "$tmp_state"
mv "$tmp_state" "$STATE_FILE"
chown gitea-automation:gitea-automation "$STATE_FILE"

echo "opened $REPO #$PR_NUMBER for issue #$ISSUE as $IDENTITY"
