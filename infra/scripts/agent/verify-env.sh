#!/usr/bin/env bash
# Verify the bot-event agent runtime. Run as bot-event.
set -uo pipefail

FAIL=0
ok()   { printf 'ok   %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*"; FAIL=1; }
warn() { printf 'WARN %s\n' "$*"; }

check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else fail "$name"; fi
}
deny() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "$name (allowed)"; else ok "$name (denied)"; fi
}

[[ "$(id -un)" == "gitea-automation" ]] && ok "user is gitea-automation (bot OS user)" || fail "user is $(id -un)"
[[ "$(id -u)" == "1501" ]] && ok "uid is 1501" || fail "uid is $(id -u)"
[[ "$HOME" == "/srv/agent" ]] && ok "HOME is /srv/agent" || fail "HOME is $HOME"
deny "sudo" sudo -n true

USER_GROUPS=" $(id -Gn) "
for g in sudo adm dip docker; do
  [[ "$USER_GROUPS" == *" $g "* ]] && fail "forbidden group: $g" || ok "not in group: $g"
done
[[ "$USER_GROUPS" == *" opencode "* ]] && ok "member of group: opencode" || fail "missing group: opencode"

for c in git python3 curl jq rsync bash opencode; do
  command -v "$c" >/dev/null 2>&1 && ok "command: $c" || fail "command: $c"
done

check "repo write" test -w "$HOME/repos"
check "scratch write" test -w /tmp/opencode
deny "read /srv/backup" test -r /srv/backup
deny "read /srv/observability" test -r /srv/observability

ENVFILE="${ENVFILE:-/etc/gitea/automation/bot-event.env}"
if [[ -f "$ENVFILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENVFILE"
fi
if [[ -n "${GITEA_TOKEN:-}" ]]; then
  check "Gitea API read" curl -fsS -H "Authorization: token $GITEA_TOKEN" "${GITEA_URL:-http://127.0.0.1:3001}/api/v1/repos/gardusi-gustavo/workflow-devops/issues?state=open&limit=1"
  login="$(curl -fsS -H "Authorization: token $GITEA_TOKEN" "${GITEA_URL:-http://127.0.0.1:3001}/api/v1/user" | jq -r '.login // empty')"
  [[ "$login" == "bot-event" ]] && ok "Gitea token identity: bot-event" || fail "Gitea token identity: ${login:-unknown}"
else
  fail "GITEA_TOKEN missing in $ENVFILE"
fi

[[ "$(stat -c '%a' "$ENVFILE" 2>/dev/null)" == "640" ]] && ok "token file mode 640" || fail "token file mode is not 640"
[[ "$(stat -c '%U:%G' "$ENVFILE" 2>/dev/null)" == "root:gitea-automation" ]] && ok "token file owner" || fail "token file owner is not root:gitea-automation"
USER_GROUPS=" $(id -nG user 2>/dev/null) "
[[ "$USER_GROUPS" != *" opencode "* ]] && ok "user not in opencode" || fail "user is in opencode"
[[ "$(stat -c '%U:%G %a' /usr/local/lib/opencode/opencode 2>/dev/null)" == "root:opencode 750" ]] && ok "opencode binary is root:opencode 750" || fail "opencode binary mode changed"
command -v gitea-api >/dev/null 2>&1 && ok "command: gitea-api" || fail "command: gitea-api"
AGENT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
grep -q 'pr-limit' "$AGENT_ROOT/infra/scripts/agent/gitea-api.sh" && ok "PR review lock source" || fail "PR review lock source"
grep -q 'pr-size' "$AGENT_ROOT/infra/scripts/agent/gitea-api.sh" && ok "PR size guard source" || fail "PR size guard source"
command -v pr-limit >/dev/null 2>&1 && ok "command: pr-limit" || warn "command: pr-limit (install after merge)"
command -v pr-size >/dev/null 2>&1 && ok "command: pr-size" || warn "command: pr-size (install after merge)"
if command -v gitea-api >/dev/null 2>&1; then
  grep -q 'pr-limit' /usr/local/bin/gitea-api && ok "installed gitea-api PR lock" || warn "installed gitea-api lacks PR lock; reinstall"
  grep -q 'pr-size' /usr/local/bin/gitea-api && ok "installed gitea-api PR size" || warn "installed gitea-api lacks PR size; reinstall"
fi
if [[ -r "$HOME/.config/git/hooks/pre-push" ]]; then
  grep -q 'pr-limit' "$HOME/.config/git/hooks/pre-push" && ok "installed pre-push PR lock" || warn "installed pre-push lacks PR lock; reinstall"
  grep -q 'pr-size' "$HOME/.config/git/hooks/pre-push" && ok "installed pre-push PR size" || warn "installed pre-push lacks PR size; reinstall"
fi
deny "read human token" test -r /home/user/.config/gitea/env

check "Gitea SSH" timeout 20 git ls-remote ssh://git@gitea.localhost:2225/gardusi-gustavo/workflow-devops.git HEAD

if [[ "${VERIFY_PR:-0}" == "1" ]]; then
  echo "PR creation: use the Gitea API with $GITEA_TOKEN and a scratch branch"
else
  echo "PR creation: skipped (VERIFY_PR=1 enables a manual check)"
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "agent environment: FAILED" >&2
  exit 1
fi
echo "agent environment: ok"
