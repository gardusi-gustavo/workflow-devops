#!/usr/bin/env bash
# Fixture tests for the risk gate. No network or token required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RISK="$ROOT/infra/scripts/ci/validate-risk.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

setup() {
  local name="$1" path="$2" body="$3" labels="$4"
  local repo="$tmp/$name"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name test
  git -C "$repo" commit --allow-empty -q -m base
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  mkdir -p "$repo/$(dirname "$path")"
  printf 'x\n' > "$repo/$path"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m change
  jq -nc --arg b "$body" --arg l "$labels" \
    '{pull_request:{base:{ref:"main"},body:$b,labels:($l|split(",")|map(select(length>0))|map({name:.}))}}' \
    > "$repo/event.json"
  printf '%s' "$repo"
}

expect_ok() {
  local name="$1" repo="$2"
  ( cd "$repo" && GITHUB_BASE_REF=main bash "$RISK" --root . --event event.json >/dev/null ) ||
    fail "$name should pass"
  pass "$name"
}
expect_fail() {
  local name="$1" repo="$2"
  ( cd "$repo" && GITHUB_BASE_REF=main bash "$RISK" --root . --event event.json >/dev/null 2>&1 ) &&
    fail "$name should fail"
  pass "$name"
}

normal="$(setup normal src/a.sh '' '')"
expect_ok "normal path" "$normal"

sensitive="$(setup sensitive auth/login.sh '' '')"
expect_fail "sensitive without label or section" "$sensitive"

sensitive_ok="$(setup sensitive-ok auth/login.sh '## Security
checked' 'security-review')"
expect_ok "sensitive with label and section" "$sensitive_ok"

elevated="$(setup elevated package-lock.json '' '')"
expect_fail "elevated without risk section" "$elevated"

elevated_ok="$(setup elevated-ok package-lock.json '## Risk
generated' '')"
expect_ok "elevated with risk section" "$elevated_ok"

echo "risk tests ok"
