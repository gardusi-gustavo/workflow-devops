#!/usr/bin/env bash
# Fixture tests for capacity-based dump pruning.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PRUNE="$ROOT/infra/scripts/backup/prune-dumps.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass() { echo "ok: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

make_dump() {
  local dir="$1" stamp="$2" size="$3"
  dd if=/dev/zero of="$dir/gitea-$stamp.7z" bs=1 count=0 seek="$size" status=none
  (cd "$dir" && sha256sum "gitea-$stamp.7z" >"gitea-$stamp.7z.sha256")
}

dir="$tmp/dumps"
mkdir -p "$dir"
for i in 1 2 3 4 5; do
  make_dump "$dir" "2026110${i}T000000Z" 1000
done

"$PRUNE" --dir "$dir" --budget 3000 --reserve 0 --min-keep 1 >/dev/null
count="$(find "$dir" -name 'gitea-*.7z' | wc -l)"
[[ "$count" -eq 3 ]] || fail "expected 3 dumps, got $count"
[[ -f "$dir/gitea-20261105T000000Z.7z" ]] || fail "newest dump removed"
[[ ! -f "$dir/gitea-20261101T000000Z.7z" ]] || fail "oldest dump kept"
pass "prunes oldest and keeps the newest"

# min-keep is respected even when the budget is impossible.
dir2="$tmp/small"
mkdir -p "$dir2"
for i in 1 2 3; do make_dump "$dir2" "2026110${i}T000000Z" 1000; done
"$PRUNE" --dir "$dir2" --budget 1 --reserve 0 --min-keep 1 >/dev/null 2>&1 || true
count="$(find "$dir2" -name 'gitea-*.7z' | wc -l)"
[[ "$count" -eq 1 ]] || fail "min-keep not honored: $count"
[[ -f "$dir2/gitea-20261103T000000Z.7z" ]] || fail "newest dump should survive"
pass "honors min-keep when over budget"

echo "prune-dumps tests ok"
