#!/usr/bin/env bash
# Fixture tests for the review-lane check. No network or token required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LIMIT="$ROOT/infra/scripts/agent/pr-limit.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

fixture() {
  local name="$1"
  local json="$2"
  printf '%s\n' "$json" > "$tmp/$name.json"
  printf '%s' "$tmp/$name.json"
}

empty="$(fixture empty '[]')"
one_bot="$(fixture one-bot '[{"number":1,"user":{"login":"bot-event"},"head":{"ref":"feat/a"},"title":"A","draft":false}]')"
one_human="$(fixture one-human '[{"number":2,"user":{"login":"human"},"head":{"ref":"feat/b"},"title":"B","draft":false}]')"
two="$(fixture two '[{"number":1,"user":{"login":"bot-event"},"head":{"ref":"feat/a"},"title":"A","draft":false},{"number":2,"user":{"login":"human"},"head":{"ref":"feat/b"},"title":"B","draft":false}]')"
three="$(fixture three '[{"number":1,"user":{"login":"bot-event"},"head":{"ref":"feat/a"},"title":"A","draft":false},{"number":2,"user":{"login":"bot-cron"},"head":{"ref":"feat/b"},"title":"B","draft":false},{"number":3,"user":{"login":"bot-manual"},"head":{"ref":"feat/c"},"title":"C","draft":false}]')"
draft="$(fixture draft '[{"number":3,"user":{"login":"bot-event"},"head":{"ref":"feat/draft"},"title":"Draft","draft":true}]')"

allow() {
  local name="$1"; shift
  "$LIMIT" "$@" >/dev/null 2>&1 || fail "$name should allow"
  pass "$name"
}

deny() {
  local name="$1"; shift
  "$LIMIT" "$@" >/dev/null 2>&1 && fail "$name should deny"
  pass "$name"
}

allow "status empty" status --repo test/repo --fixture "$empty"
deny "status occupied" status --repo test/repo --fixture "$one_bot"

allow "create empty" check --repo test/repo --create --fixture "$empty"
allow "create one bot PR (cap 3)" check --repo test/repo --create --fixture "$one_bot"
allow "create one human PR (cap 3)" check --repo test/repo --create --fixture "$one_human"
allow "create with two PRs (cap 3)" check --repo test/repo --create --fixture "$two"
deny "create with three PRs" check --repo test/repo --create --fixture "$three"
allow "create with one draft (cap 3)" check --repo test/repo --create --fixture "$draft"

allow "update bot PR head" check --repo test/repo --branch feat/a --fixture "$one_bot"
deny "update human PR head" check --repo test/repo --branch feat/b --fixture "$one_human"
allow "new branch while one PR open" check --repo test/repo --branch feat/new --fixture "$one_bot"
deny "new branch with three PRs" check --repo test/repo --branch feat/new --fixture "$three"
allow "new branch when clear" check --repo test/repo --branch feat/new --fixture "$empty"

echo "pr-limit tests ok"
