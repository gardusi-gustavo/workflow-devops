#!/usr/bin/env bash
# Prune card Gitea dumps older than AGE_DAYS when the directory exceeds BUDGET.
set -euo pipefail

DIR=""
BUDGET=$((4608 * 1024 * 1024)) # 4.5 GiB
MIN_KEEP=5
AGE_DAYS=30

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) DIR="${2:-}"; shift 2 ;;
    --budget) BUDGET="${2:-}"; shift 2 ;;
    --min-keep) MIN_KEEP="${2:-}"; shift 2 ;;
    --age-days) AGE_DAYS="${2:-}"; shift 2 ;;
    -h|--help)
      echo "usage: prune-card-dumps.sh --dir DIR [--budget N] [--min-keep N] [--age-days N]"
      exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$DIR" && -d "$DIR" ]] || { echo "error: --dir is required and must exist" >&2; exit 2; }
[[ "$BUDGET" =~ ^[0-9]+$ && "$MIN_KEEP" =~ ^[0-9]+$ && "$AGE_DAYS" =~ ^[0-9]+$ ]] || {
  echo "error: limits must be numbers" >&2
  exit 2
}
(( MIN_KEEP >= 1 )) || MIN_KEEP=1

size="$(du -sb "$DIR" | awk '{print $1}')"
if (( size <= BUDGET )); then
  echo "prune: $DIR under budget ($size <= $BUDGET)"
  exit 0
fi

mapfile -t archives < <(find "$DIR" -maxdepth 1 -type f -name 'gitea-*.7z' \
  -printf '%T@ %p\n' | sort -nr | awk '{print $2}')
i=0
deleted=0
for f in "${archives[@]}"; do
  i=$((i + 1))
  if (( i <= MIN_KEEP )); then
    continue
  fi
  if [[ -n "$(find "$f" -maxdepth 0 -mtime "+$AGE_DAYS" -print -quit 2>/dev/null)" ]]; then
    rm -f "$f" "$f.sha256"
    echo "deleted $f"
    deleted=$((deleted + 1))
  fi
done

size="$(du -sb "$DIR" | awk '{print $1}')"
echo "prune: $DIR dumps=$((${#archives[@]} - deleted)) bytes=$size deleted=$deleted"
if (( size > BUDGET )); then
  echo "warning: $DIR still over budget ($size > $BUDGET); no archives older than ${AGE_DAYS}d to prune" >&2
fi
