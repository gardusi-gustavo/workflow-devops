#!/usr/bin/env bash
# Shared helpers for agent-trigger.sh. Source this after setting GITEA_URL,
# GITEA_TOKEN, API, API_ERR_LOG, AGENT_HOME, REPO, and TARGET.

api_call() {
  local method="$1" path="$2" data="${3:-}" resp code
  resp="$(mktemp)"
  if [[ -n "$data" ]]; then
    code="$(curl -sS -o "$resp" -w '%{http_code}' -X "$method" -H "Authorization: token $GITEA_TOKEN" -H 'Content-Type: application/json' -d "$data" "$API$path")"
  else
    code="$(curl -sS -o "$resp" -w '%{http_code}' -X "$method" -H "Authorization: token $GITEA_TOKEN" "$API$path")"
  fi
  if (( code >= 300 )); then
    { printf '%s %s HTTP %s\n' "$method" "$path" "$code"; cat "$resp"; printf '\n'; } >> "$API_ERR_LOG" 2>/dev/null || true
    rm -f "$resp"
    return 1
  fi
  cat "$resp"
  rm -f "$resp"
}

api_get() { api_call GET "$1"; }
api_post() { api_call POST "$1" "${2:-}"; }
api_put() { api_call PUT "$1" "${2:-}"; }

run_agent() {
  local dir="$1"; shift
  if [[ "$ME" == "gitea-automation" ]]; then
    ( cd "$dir" && env -u GITEA_TOKEN -u GITEA_ENV_FILE HOME="$AGENT_HOME" PATH=/usr/local/bin:/usr/bin:/bin "$@" )
  else
    runuser -u gitea-automation -- bash -c 'cd "$1"; shift; exec "$@"' _ "$dir" \
      env -u GITEA_TOKEN -u GITEA_ENV_FILE HOME="$AGENT_HOME" PATH=/usr/local/bin:/usr/bin:/bin "$@"
  fi
}

run_in_repo() {
  local dir="$1"; shift
  if [[ "$ME" == "gitea-automation" ]]; then
    ( cd "$dir" && "$@" )
  else
    runuser -u gitea-automation -- bash -c 'cd "$1"; shift; exec "$@"' _ "$dir" "$@"
  fi
}

list_label() {
  api_get "/repos/$REPO/issues?state=open&type=issues&labels=$1&limit=100" || echo '[]'
}

select_issue() {
  local focus hyper n
  focus="$(list_label 'agent:focus')"
  hyper="$(list_label 'agent:hyperfocus')"
  case "$TARGET" in
    focus) n="$(jq -r 'sort_by(.created_at) | .[0].number // empty' <<<"$focus")" ;;
    hyperfocus) n="$(jq -r 'sort_by(.created_at) | .[0].number // empty' <<<"$hyper")" ;;
    any)
      n="$(jq -r 'sort_by(.created_at) | .[0].number // empty' <<<"$focus")"
      [[ -n "$n" ]] || n="$(jq -r 'sort_by(.created_at) | .[0].number // empty' <<<"$hyper")"
      ;;
  esac
  printf '%s' "$n"
}
