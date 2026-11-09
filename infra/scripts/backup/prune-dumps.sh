#!/usr/bin/env bash
# Delete the oldest Gitea dumps until the directory fits the budget and keeps
# the configured minimum number of dumps.
set -euo pipefail

DIR=""
BUDGET=5000000000
RESERVE=500000000
MIN_KEEP=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) DIR="${2:-}"; shift 2 ;;
    --budget) BUDGET="${2:-}"; shift 2 ;;
    --reserve) RESERVE="${2:-}"; shift 2 ;;
    --min-keep) MIN_KEEP="${2:-}"; shift 2 ;;
    -h|--help) echo "usage: prune-dumps.sh --dir DIR [--budget N] [--reserve N] [--min-keep N]"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$DIR" && -d "$DIR" ]] || { echo "error: --dir is required and must exist" >&2; exit 2; }
[[ "$BUDGET" =~ ^[0-9]+$ && "$RESERVE" =~ ^[0-9]+$ && "$MIN_KEEP" =~ ^[0-9]+$ ]] || {
  echo "error: limits must be numbers" >&2; exit 2;
}
(( MIN_KEEP >= 1 )) || MIN_KEEP=1

shopt -s nullglob
files=("$DIR"/gitea-*.7z)
(( ${#files[@]} > 0 )) || { echo "prune: no dumps in $DIR"; exit 0; }
mapfile -t files < <(printf '%s\n' "${files[@]}" | sort)
newest="${files[${#files[@]}-1]}"
if [[ ! -f "$newest.sha256" ]]; then
  echo "prune: newest archive has no checksum sidecar; refusing to prune: $newest" >&2
  exit 1
fi
if ! (cd "$DIR" && sha256sum -c "$(basename "$newest").sha256" >/dev/null); then
  echo "prune: newest archive checksum failed; refusing to prune: $newest" >&2
  exit 1
fi

total=0
for f in "${files[@]}"; do total=$((total + $(stat -c '%s' "$f"))); done
avail="$(df -B1 --output=avail "$DIR" | tail -1 | tr -d ' ')"
fs_size="$(df -B1 --output=size "$DIR" | tail -1 | tr -d ' ')"
limit=$((BUDGET - RESERVE))
capacity_limit=$((fs_size - RESERVE))
(( capacity_limit < limit )) && limit=$capacity_limit
(( limit > 0 )) || limit=$BUDGET

deleted=0
while (( ${#files[@]} > MIN_KEEP )); do
  if (( total <= limit )) && (( avail >= RESERVE )); then break; fi
  old="${files[0]}"
  size="$(stat -c '%s' "$old")"
  rm -f "$old" "$old.sha256"
  files=("${files[@]:1}")
  total=$((total - size))
  avail=$((avail + size))
  deleted=$((deleted + 1))
  echo "deleted $old ($size bytes)"
done

echo "prune: $DIR dumps=${#files[@]} bytes=$total limit=$limit capacity_limit=$capacity_limit avail=$avail deleted=$deleted"
if (( total > limit )) || (( avail < RESERVE )); then
  echo "error: $DIR still over budget with min-keep=$MIN_KEEP" >&2
  exit 1
fi
