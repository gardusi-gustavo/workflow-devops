#!/usr/bin/env bash
# Public-push gate. Critical findings fail; warnings are reported.
set -euo pipefail
ROOT="${1:-$HOME/repos}"
critical=0
warn=0
report="$(mktemp)"
trap 'rm -f "$report"' EXIT

scan_repo() {
  local repo="$1"
  local name="${repo#"$ROOT"/}"
  git -C "$repo" grep -nIE 'ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]+|AKIA[0-9A-Z]{16}|-----BEGIN (RSA|OPENSSH|EC|PGP) PRIVATE KEY-----|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' -- . ':!*.lock' >/dev/null 2>&1 && {
    echo "CRITICAL secret pattern: $name" >>"$report"; critical=$((critical+1)); }
  git -C "$repo" ls-files | grep -E '(^|/)(\.env|id_rsa|id_ed25519|[^/]*\.(pem|key|p12|pfx))$' >/dev/null 2>&1 && {
    echo "CRITICAL secret file: $name" >>"$report"; critical=$((critical+1)); }
  if [[ "$name" != human/private* && "$name" != *"/private" ]]; then
    git -C "$repo" grep -nIE 'human/private|private/private' \
      -- . ':(exclude)infra/config/repos.json' ':(exclude)infra/config/policy.json' \
      ':(exclude)infra/scripts/github/pre-publication-audit.sh' >/dev/null 2>&1 && {
      echo "WARN private path reference: $name" >>"$report"; warn=$((warn+1)); }
    git -C "$repo" grep -nIE '/home/(user|human)|gitea\.localhost|172\.18\.0\.1' \
      -- . ':(exclude)infra/config/repos.json' ':(exclude)infra/config/policy.json' >/dev/null 2>&1 && {
      echo "WARN local host or path: $name" >>"$report"; warn=$((warn+1)); }
  fi
}

for repo in "$ROOT"/gardusi-gustavo/*; do
  [[ -d "$repo/.git" ]] || continue
  scan_repo "$repo"
done
repo="$ROOT/human/private"
[[ -d "$repo/.git" ]] && scan_repo "$repo"

cat "$report"
echo "critical=$critical warnings=$warn"
(( critical == 0 ))
