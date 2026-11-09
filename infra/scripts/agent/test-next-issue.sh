#!/usr/bin/env bash
# Fixture tests for the deterministic issue selector. No network or token.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
NEXT="$ROOT/infra/scripts/agent/next-issue.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

fixture() {
  local name="$1"
  printf '%s\n' "$2" > "$tmp/$name.json"
  printf '%s' "$tmp/$name.json"
}

issue() {
  local n="$1" title="$2" label="$3" deps="${4:-[]}"
  jq -nc --argjson n "$n" --arg t "$title" --arg l "$label" --argjson d "$deps" \
    '{number:$n,title:$t,state:"open",labels:[$l],dependencies:$d}'
}

basic="$(fixture basic "$(jq -nc \
  --argjson a "$(issue 1 '3.0 - baseline bug' bug)" \
  --argjson b "$(issue 2 '3.1 - worse bug' bug)" \
  --argjson c "$(issue 3 '2.9 - top doc' documentation)" \
  --argjson d "$(issue 4 '1.5 - feature' enhancement)" \
  '[$a,$b,$c,$d]')")"

expect_pick() {
  local name="$1" file="$2" want="$3"
  local got
  got="$("$NEXT" --repo test/repo --fixture "$file" --json | jq -r '.number')"
  [[ "$got" == "$want" ]] || fail "$name: expected #$want, got #${got:-none}"
  pass "$name"
}

expect_fail() {
  local name="$1" file="$2"
  if "$NEXT" --repo test/repo --fixture "$file" >/dev/null 2>&1; then
    fail "$name: expected failure"
  fi
  pass "$name"
}

expect_pick "picks highest bug" "$basic" 2

fraction="$(fixture fraction "$(jq -nc \
  --argjson a "$(issue 1 '3.2 - a' bug)" \
  --argjson b "$(issue 2 '3.15 - b' bug)" \
  --argjson c "$(issue 3 '3.1 - c' bug)" \
  --argjson d "$(issue 4 '3.09 - d' bug)" \
  '[$a,$b,$c,$d]')")"
expect_pick "reverse decimal order" "$fraction" 1

blocked="$(fixture blocked "$(jq -nc \
  --argjson a "$(issue 1 '3.2 - blocked' bug '[{"number":9,"state":"open"}]')" \
  --argjson b "$(issue 2 '3.1 - ready' bug '[{"number":9,"state":"closed"}]')" \
  '[$a,$b]')")"
expect_pick "skips open dependency" "$blocked" 2

allblocked="$(fixture allblocked "$(jq -nc \
  --argjson a "$(issue 1 '3.2 - blocked' bug '[{"number":9,"state":"open"}]')" \
  '[$a]')")"
expect_fail "fails when all ranked issues are blocked" "$allblocked"

trailing="$(fixture trailing "$(jq -nc \
  --argjson a "$(issue 1 '3.10 - bad rank' bug)" \
  '[$a]')")"
expect_fail "rejects trailing zero" "$trailing"

duplicate="$(fixture duplicate "$(jq -nc \
  --argjson a "$(issue 1 '3.1 - one' bug)" \
  --argjson b "$(issue 2 '3.1 - two' bug)" \
  '[$a,$b]')")"
expect_fail "rejects duplicate rank" "$duplicate"

mismatch="$(fixture mismatch "$(jq -nc \
  --argjson a "$(issue 1 '3.1 - bug label missing' documentation)" \
  '[$a]')")"
expect_fail "rejects label/type mismatch" "$mismatch"

badtype="$(fixture badtype "$(jq -nc \
  --argjson a "$(issue 1 '4.0 - out of range' bug)" \
  '[$a]')")"
expect_fail "rejects type outside 1/2/3" "$badtype"

unranked="$(fixture unranked "$(jq -nc \
  --argjson a "$(issue 1 'just a title' bug)" \
  '[$a]')")"
expect_fail "ignores unranked issues" "$unranked"

if ! "$NEXT" --repo test/repo --fixture "$basic" --check >/dev/null; then
  fail "check should pass on a valid queue"
fi
pass "check passes on a valid queue"

order="$("$NEXT" --repo test/repo --fixture "$basic" --list | awk '{print $2}' | paste -sd, -)"
[[ "$order" == "3.1,3.0,2.9,1.5" ]] || fail "list order: $order"
pass "list prints reverse-ranked queue"

echo "next-issue tests ok"
