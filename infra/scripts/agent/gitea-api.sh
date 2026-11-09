#!/usr/bin/env bash
# Guarded Gitea API caller. Read-only for the bot except append/propose paths.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
usage: gitea-api [--as human|bot-event|bot-cron|bot-manual] METHOD PATH [--data JSON|@FILE] [--header VALUE]

Examples:
  gitea-api GET /repos/gardusi-gustavo/private/issues
  gitea-api POST /repos/gardusi-gustavo/private/issues/196/comments --data @comment.json
  gitea-api POST /repos/gardusi-gustavo/private/pulls --data @pr.json

Human may do anything. Bots may only:
  GET any path
  POST /repos/<owner>/<repo>/issues/<n>/comments
  POST /repos/<owner>/<repo>/pulls
  POST|PUT /repos/<owner>/<repo>/issues/<n>/labels
  DELETE /repos/<owner>/<repo>/issues/<n>/labels/<label-id>

PR creation is denied when the repository already has an open pull request, when
the size budget is exceeded, or when the body does not reference an open issue.
USAGE
}

AS="${GITEA_IDENTITY:-}"
if [[ "${1:-}" == "--as" ]]; then
  AS="${2:-}"
  shift 2
fi
if [[ $# -lt 2 ]]; then usage >&2; exit 2; fi
METHOD="$1"
API_PATH="$2"
shift 2

DATA=""
HEADERS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --data|-d)
      [[ $# -ge 2 ]] || { echo "error: --data needs a value" >&2; exit 2; }
      DATA="$2"; shift 2 ;;
    --header|-H)
      [[ $# -ge 2 ]] || { echo "error: --header needs a value" >&2; exit 2; }
      HEADERS+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

ME="$(id -un)"
if [[ "$ME" == "root" || "$ME" == "gitea-automation" ]]; then
  [[ -n "$AS" ]] || { echo "error: set GITEA_IDENTITY or pass --as human|bot-event|bot-cron|bot-manual" >&2; exit 2; }
  IDENT="$AS"
else
  case "$ME" in
    human) ME="human" ;;
    user) ME="human" ;;
  esac
  [[ -z "$AS" || "$AS" == "$ME" ]] || { echo "error: cannot act as $AS" >&2; exit 2; }
  IDENT="$ME"
fi

case "$IDENT" in
  human)
    ENVFILE="${GITEA_HUMAN_ENV:-/home/user/.config/gitea/env}"
    LOCAL_HOME="${GITEA_HUMAN_HOME:-/home/user}" ;;
  bot-event)
    ENVFILE="${GITEA_BOT_EVENT_ENV:-/etc/gitea/automation/bot-event.env}"
    LOCAL_HOME="${GITEA_BOT_HOME:-/srv/agent}" ;;
  bot-cron)
    ENVFILE="${GITEA_BOT_CRON_ENV:-/etc/gitea/automation/bot-cron.env}"
    LOCAL_HOME="${GITEA_BOT_HOME:-/srv/agent}" ;;
  bot-manual)
    ENVFILE="${GITEA_BOT_MANUAL_ENV:-/etc/gitea/automation/bot-manual.env}"
    LOCAL_HOME="${GITEA_BOT_HOME:-/srv/agent}" ;;
  *) echo "error: unknown identity: $IDENT" >&2; exit 2 ;;
esac

[[ -r "$ENVFILE" ]] || { echo "error: cannot read $ENVFILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENVFILE"
: "${GITEA_URL:?GITEA_URL missing}"
: "${GITEA_TOKEN:?GITEA_TOKEN missing}"

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/gitea-api"
mkdir -p "$LOG_DIR"
chmod 700 "$LOG_DIR"
LOG="$LOG_DIR/audit.jsonl"
log() {
  local status="$1"
  printf '{"ts":"%s","identity":"%s","method":"%s","path":"%s","status":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$IDENT" "$METHOD" "$API_PATH" "$status" >> "$LOG"
}

LOGIN="$(curl -fsS -H "Authorization: token $GITEA_TOKEN" "$GITEA_URL/api/v1/user" | jq -r '.login // empty')"
if [[ "$LOGIN" != "$IDENT" ]]; then
  log "identity-mismatch"
  echo "error: token identity is '$LOGIN', expected '$IDENT'" >&2
  exit 1
fi

if [[ "$METHOD" == "POST" && "$API_PATH" =~ ^/repos/([^/]+)/([^/]+)/pulls$ ]]; then
  REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  PR_LIMIT_BIN="${PR_LIMIT_BIN:-}"
  if [[ -z "$PR_LIMIT_BIN" ]]; then
    if [[ -x "$SCRIPT_DIR/pr-limit.sh" ]]; then
      PR_LIMIT_BIN="$SCRIPT_DIR/pr-limit.sh"
    elif [[ -x "$SCRIPT_DIR/pr-limit" ]]; then
      PR_LIMIT_BIN="$SCRIPT_DIR/pr-limit"
    elif command -v pr-limit >/dev/null 2>&1; then
      PR_LIMIT_BIN="$(command -v pr-limit)"
    fi
  fi
  if [[ -z "$PR_LIMIT_BIN" || ! -x "$PR_LIMIT_BIN" ]]; then
    log "pr-limit-missing"
    echo "denied: PR review lock is not installed (pr-limit)" >&2
    exit 2
  fi
  if ! "$PR_LIMIT_BIN" check --repo "$REPO" --create >/dev/null; then
    log "pr-limit"
    exit 2
  fi

  PR_SIZE_BIN="${PR_SIZE_BIN:-}"
  if [[ -z "$PR_SIZE_BIN" ]]; then
    if [[ -x "$SCRIPT_DIR/pr-size.sh" ]]; then
      PR_SIZE_BIN="$SCRIPT_DIR/pr-size.sh"
    elif [[ -x "$SCRIPT_DIR/pr-size" ]]; then
      PR_SIZE_BIN="$SCRIPT_DIR/pr-size"
    elif command -v pr-size >/dev/null 2>&1; then
      PR_SIZE_BIN="$(command -v pr-size)"
    fi
  fi
  if [[ -z "$PR_SIZE_BIN" || ! -x "$PR_SIZE_BIN" ]]; then
    log "pr-size-missing"
    echo "denied: PR size guard is not installed (pr-size)" >&2
    exit 2
  fi

  DATA_BODY="$DATA"
  if [[ "$DATA" == @* ]]; then
    DATA_FILE="${DATA#@}"
    [[ -r "$DATA_FILE" ]] || {
      log "pr-size-invalid"
      echo "denied: cannot read PR body file: $DATA_FILE" >&2
      exit 2
    }
    DATA_BODY="$(cat "$DATA_FILE")"
  fi
  HEAD_REF="$(jq -r '.head // empty' <<<"$DATA_BODY" 2>/dev/null || true)"
  BASE_REF="$(jq -r '.base // "main"' <<<"$DATA_BODY" 2>/dev/null || true)"
  if [[ -z "$HEAD_REF" ]]; then
    log "pr-size-invalid"
    echo "denied: PR body has no head branch" >&2
    exit 2
  fi

  LOCAL_REPO="$LOCAL_HOME/repos/$REPO"
  if [[ ! -d "$LOCAL_REPO/.git" ]]; then
    log "pr-size-local-missing"
    echo "denied: cannot verify PR size; local checkout not found: $LOCAL_REPO" >&2
    exit 2
  fi
  BASE_LOCAL="${BASE_REF:-main}"
  [[ "$BASE_LOCAL" == origin/* ]] || BASE_LOCAL="origin/$BASE_LOCAL"
  if ! "$PR_SIZE_BIN" check \
    --repo "$REPO" \
    --head "$HEAD_REF" \
    --base "$BASE_LOCAL" \
    --repo-root "$LOCAL_REPO" \
    --policy "${GITEA_PR_POLICY:-/srv/agent/config/policy.json}" >/dev/null; then
    log "pr-size"
    exit 2
  fi

  PR_BODY="$(jq -r '.body // empty' <<<"$DATA_BODY" 2>/dev/null || true)"
  ISSUE_NUMS="$(grep -oE '#[0-9]+' <<<"$PR_BODY" | tr -d '#' | sort -u || true)"
  LINK_OK=0
  for n in $ISSUE_NUMS; do
    meta="$(curl -fsS -H "Authorization: token $GITEA_TOKEN" \
      "$GITEA_URL/api/v1/repos/$REPO/issues/$n" 2>/dev/null || true)"
    is_pr="$(jq -r '(.pull_request // null) != null' <<<"$meta" 2>/dev/null || echo true)"
    state="$(jq -r '.state // empty' <<<"$meta" 2>/dev/null || true)"
    if [[ "$is_pr" == "false" && "$state" == "open" ]]; then
      LINK_OK=1
      break
    fi
  done
  if (( ! LINK_OK )); then
    log "pr-issue-link"
    echo "denied: PR body must reference at least one open issue (#N)" >&2
    exit 2
  fi
fi

if [[ "$IDENT" == bot-* ]]; then
  allowed=0
  [[ "$METHOD" == "GET" ]] && allowed=1
  [[ "$METHOD" == "POST" && "$API_PATH" =~ ^/repos/[^/]+/[^/]+/issues/[0-9]+/comments$ ]] && allowed=1
  [[ "$METHOD" == "POST" && "$API_PATH" =~ ^/repos/[^/]+/[^/]+/pulls$ ]] && allowed=1
  [[ "$METHOD" == "POST" && "$API_PATH" =~ ^/repos/[^/]+/[^/]+/pulls/[0-9]+/requested_reviewers$ ]] && allowed=1
  # Label-only issue state transitions. Removing all labels must be explicit by id.
  [[ "$METHOD" == "POST" && "$API_PATH" =~ ^/repos/[^/]+/[^/]+/issues/[0-9]+/labels$ ]] && allowed=1
  [[ "$METHOD" == "PUT"  && "$API_PATH" =~ ^/repos/[^/]+/[^/]+/issues/[0-9]+/labels$ ]] && allowed=1
  [[ "$METHOD" == "DELETE" && "$API_PATH" =~ ^/repos/[^/]+/[^/]+/issues/[0-9]+/labels/[0-9]+$ ]] && allowed=1
  if (( ! allowed )); then
    log "denied"
    echo "denied: $IDENT may not $METHOD $API_PATH" >&2
    exit 2
  fi
fi


if [[ "$IDENT" == bot-* && "$METHOD" == "POST" && "$API_PATH" =~ ^/repos/([^/]+)/([^/]+)/(issues|pulls)(/([0-9]+)/comments)?$ ]]; then
  TARGET_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  KIND="${BASH_REMATCH[3]}"
  NUMBER="${BASH_REMATCH[5]:-}"

  payload="$DATA"
  if [[ "$DATA" == @* ]]; then
    data_file="${DATA#@}"
    [[ -r "$data_file" ]] || { log "limit-invalid"; echo "denied: cannot read data file: $data_file" >&2; exit 2; }
    payload="$(cat "$data_file")"
  fi

  if [[ -n "$payload" ]]; then
    title="$(jq -r '.title // empty' <<<"$payload" 2>/dev/null || true)"
    body="$(jq -r '.body // empty' <<<"$payload" 2>/dev/null || true)"
    if (( ${#title} > 200 )); then
      log "limit-title"; echo "denied: title exceeds 200 characters" >&2; exit 2
    fi
    if (( ${#body} > 20000 )); then
      log "limit-body"; echo "denied: body exceeds 20000 characters" >&2; exit 2
    fi

    if [[ "$KIND" == "issues" && -z "$NUMBER" ]]; then
      if [[ ! "$title" =~ ^[123]\.[0-9]+[[:space:]]-[[:space:]] ]]; then
        log "limit-rank"; echo "denied: issue title needs a 1.x/2.x/3.x rank" >&2; exit 2
      fi
      open_count="$(curl -fsS -H "Authorization: token $GITEA_TOKEN" \
        "$GITEA_URL/api/v1/repos/$TARGET_REPO/issues?state=open&type=issues&limit=100" |
        jq '[.[] | select(.pull_request == null)] | length')"
      if (( open_count >= 100 )); then
        log "limit-issues"; echo "denied: 100 open issues already" >&2; exit 2
      fi
    fi

    if [[ "$KIND" == "issues" && -n "$NUMBER" ]]; then
      if (( ${#body} > 8000 )); then
        log "limit-comment"; echo "denied: comment exceeds 8000 characters" >&2; exit 2
      fi
      is_pr="$(curl -fsS -H "Authorization: token $GITEA_TOKEN" \
        "$GITEA_URL/api/v1/repos/$TARGET_REPO/issues/$NUMBER" | jq -r '(.pull_request // null) != null')"
      limit=40
      [[ "$is_pr" == "true" ]] && limit=20
      comment_count="$(curl -fsS -H "Authorization: token $GITEA_TOKEN" \
        "$GITEA_URL/api/v1/repos/$TARGET_REPO/issues/$NUMBER/comments?limit=100" | jq 'length')"
      if (( comment_count >= limit )); then
        log "limit-comments"; echo "denied: $comment_count comments already (max $limit)" >&2; exit 2
      fi
    fi
  fi
fi

TMP="$(mktemp)"
chmod 600 "$TMP"
trap 'rm -f "$TMP"' EXIT

ARGS=(-sS -o "$TMP" -w '%{http_code}' -X "$METHOD"
      -H "Authorization: token $GITEA_TOKEN"
      -H 'Content-Type: application/json'
      -H 'Accept: application/json')
for h in "${HEADERS[@]}"; do ARGS+=(-H "$h"); done
if [[ -n "$DATA" ]]; then ARGS+=(--data-binary "$DATA"); fi

STATUS="$(curl "${ARGS[@]}" "$GITEA_URL/api/v1$API_PATH")" || STATUS="000"
cat "$TMP"
log "$STATUS"
if [[ "$STATUS" == "000" || "$STATUS" -ge 400 ]]; then
  exit 1
fi
