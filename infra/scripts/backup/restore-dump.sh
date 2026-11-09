#!/usr/bin/env bash
# Prepare a restore tree from one encrypted Gitea archive.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY="${BACKUP_POLICY:-$SCRIPT_DIR/../../config/backup-policy.json}"
VERIFY="$SCRIPT_DIR/verify-dump-contents.sh"

DUMP=""
OUT=""
PASS_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dump) DUMP="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --password-file) PASS_FILE="${2:-}"; shift 2 ;;
    -h|--help) echo "usage: restore-dump.sh --dump FILE --out DIR [--password-file FILE]"; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -r "$DUMP" ]] || { echo "error: cannot read dump: $DUMP" >&2; exit 2; }
[[ -n "$OUT" ]] || { echo "error: --out is required" >&2; exit 2; }
[[ -r "$VERIFY" ]] || { echo "error: missing $VERIFY" >&2; exit 2; }
if [[ -z "$PASS_FILE" && -r "$POLICY" ]]; then
  PASS_FILE="$(jq -r '.password_file // empty' "$POLICY")"
fi
[[ -r "$PASS_FILE" ]] || { echo "error: password file required" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/restore"
7z x -y -p"$(<"$PASS_FILE")" "$DUMP" -o"$tmp/restore" >/dev/null
bash "$VERIFY" --root "$tmp/restore" >/dev/null

mkdir -p "$OUT/data/gitea" "$OUT/data/git/repositories"
cp -a "$tmp/restore/data/." "$OUT/data/gitea/"
if [[ -f "$tmp/restore/app.ini" ]]; then
  mkdir -p "$OUT/data/gitea/conf"
  cp "$tmp/restore/app.ini" "$OUT/data/gitea/conf/app.ini"
fi
cp -a "$tmp/restore/repos/." "$OUT/data/git/repositories/"

version="unknown"
if [[ -r "$tmp/restore/manifest.txt" ]]; then
  version="$(sed -n 's/^gitea_version=//p' "$tmp/restore/manifest.txt" | head -1)"
  if [[ "$version" == gitea* ]]; then
    version="$(awk '{print $3}' <<<"$version")"
  fi
fi

echo "restore tree: $OUT"
echo "repositories: $(find "$OUT/data/git/repositories" -mindepth 2 -maxdepth 2 -type d -name '*.git' | wc -l)"
echo
echo "start a temporary instance with:"
echo "  docker run -d --name gitea-restore -p 3002:3000 \\"
echo "    -v \"$OUT/data:/data\" gitea/gitea:$version"
echo
echo "production can stay running; use a separate port and data directory."
