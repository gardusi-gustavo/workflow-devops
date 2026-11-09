#!/usr/bin/env bash
# Smoke tests for the pr-size wrapper. Fixture tests live in test-pr-size-check.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SIZE="$ROOT/infra/scripts/agent/pr-size.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

fixture() {
  local name="$1" arr="$2" commits="${3:-3}"
  jq -nc --argjson a "$arr" --argjson c "$commits" '{files:$a, commits:$c}' > "$tmp/$name.json"
  printf '%s' "$tmp/$name.json"
}

ok="$(fixture ok '[{"path":"src/a.sh","added":100,"deleted":20,"size":2000}]')"
lock="$(fixture lock '[{"path":"package-lock.json","added":"-","deleted":"-","size":900000}]')"
large="$(fixture large '[{"path":"src/a.sh","added":501,"deleted":0,"size":20000}]')"

"$SIZE" check --repo test/repo --fixture "$ok" >/dev/null || fail "within budget should allow"
pass "within budget"
"$SIZE" check --repo test/repo --fixture "$lock" >/dev/null || fail "lockfile should allow"
pass "lockfile is generated"
"$SIZE" check --repo test/repo --fixture "$large" >/dev/null 2>&1 && fail "large PR should deny"
pass "over budget denies"

echo "pr-size tests ok"
