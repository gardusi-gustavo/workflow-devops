#!/usr/bin/env bash
# Render the backup manifest from infra/config/repos.json.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-/srv/backup/repos.tsv}"
cd "$ROOT"

[[ -s infra/config/repos.json ]] || { echo "missing infra/config/repos.json" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp)"
{
  printf '# group\tname\tgit-path\n'
  jq -r '.repos[] | [.group, .name, .git_path] | @tsv' infra/config/repos.json
} > "$tmp"
mv "$tmp" "$OUT"
echo "wrote $OUT"
