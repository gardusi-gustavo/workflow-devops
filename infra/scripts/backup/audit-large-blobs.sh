#!/usr/bin/env bash
# Read-only audit of large repositories, attachments, and Git objects.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY="${BACKUP_POLICY:-$SCRIPT_DIR/../../config/backup-policy.json}"
TOP=10
DEEP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --policy) POLICY="${2:-}"; shift 2 ;;
    --top) TOP="${2:-}"; shift 2 ;;
    --deep) DEEP=1; shift ;;
    -h|--help)
      echo "usage: audit-large-blobs.sh [--policy FILE] [--top N] [--deep]"
      exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

data_dir="$(jq -r '.data_dir // "/srv/gitea/data"' "$POLICY")"
repos_root="$data_dir/git/repositories"
[[ -d "$repos_root" ]] || { echo "error: repository root missing: $repos_root" >&2; exit 2; }

echo "== largest repositories"
mapfile -t repos < <(find "$repos_root" -mindepth 2 -maxdepth 2 -type d -name '*.git' -print0 |
  xargs -0 -r du -sb | sort -nr | head -n "$TOP")
for line in "${repos[@]}"; do
  size="${line%%$'\t'*}"
  path="${line#*$'\t'}"
  printf '%12s  %s\n' "$size" "${path#"$repos_root"/}"
done

if (( DEEP )); then
  echo
  echo "== largest objects in top repository"
  top=""
  if (( ${#repos[@]} > 0 )); then
    top="${repos[0]#*$'\t'}"
  fi
  if [[ -n "$top" ]]; then
    git --git-dir="$top" rev-list --objects --all 2>/dev/null |
      git --git-dir="$top" cat-file --batch-check='%(objectsize) %(rest)' 2>/dev/null |
      sort -nr | head -n 10 || true
  fi
fi

echo
echo "== attachments"
du -sh "$data_dir/gitea/attachments" 2>/dev/null || echo "attachments: missing"

echo
echo "== packages"
du -sh "$data_dir/gitea/packages" 2>/dev/null || echo "packages: missing"

echo
echo "== repo count"
find "$repos_root" -mindepth 2 -maxdepth 2 -type d -name '*.git' | wc -l
