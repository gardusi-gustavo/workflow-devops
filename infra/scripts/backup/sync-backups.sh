#!/usr/bin/env bash
# Copy any missing archives from the primary destination to every mirror.
# Verification happens before the atomic rename; this script never prunes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY="${BACKUP_POLICY:-$SCRIPT_DIR/../../config/backup-policy.json}"
PRIMARY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --primary) PRIMARY="${2:-}"; shift 2 ;;
    --policy) POLICY="${2:-}"; shift 2 ;;
    -h|--help)
      echo "usage: sync-backups.sh [--primary DIR] [--policy FILE]"
      exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -r "$POLICY" ]] || { echo "error: cannot read $POLICY" >&2; exit 2; }
command -v 7z >/dev/null || { echo "error: 7z is required" >&2; exit 2; }
command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 2; }

PRIMARY="${PRIMARY:-$(jq -r '.primary_dir' "$POLICY")}"
# shellcheck source=mirrors.sh
source "$(dirname "${BASH_SOURCE[0]}")/mirrors.sh"
load_mirror_dirs "$POLICY" || { echo "error: no backup mirrors resolved" >&2; exit 2; }
mirrors=("${MIRROR_DIRS[@]}")
password_file="$(jq -r '.password_file // "/srv/backup/secrets/backup.pass"' "$POLICY")"
[[ -d "$PRIMARY" ]] || { echo "error: primary destination missing: $PRIMARY" >&2; exit 1; }
[[ -r "$password_file" ]] || { echo "error: cannot read password file: $password_file" >&2; exit 2; }
PASSWORD="$(<"$password_file")"

shopt -s nullglob
archives=("$PRIMARY"/gitea-*.7z)
(( ${#archives[@]} > 0 )) || { echo "sync: no archives in $PRIMARY"; exit 0; }

copied=0
for mirror in "${mirrors[@]}"; do
  [[ -n "$mirror" ]] || continue
  if [[ ! -d "$mirror" ]]; then
    echo "error: mirror destination missing: $mirror" >&2
    exit 1
  fi
  for archive in "${archives[@]}"; do
    base="$(basename "$archive")"
    target="$mirror/$base"
    target_sidecar="$target.sha256"
    hash="$(sha256sum "$archive" | awk '{print $1}')"

    if [[ -f "$target" ]]; then
      target_hash="$(sha256sum "$target" | awk '{print $1}')"
      if [[ "$hash" == "$target_hash" ]]; then
        if [[ ! -f "$target_sidecar" ]]; then
          tmp_sha="$mirror/.${base}.sha256.tmp"
          printf '%s  %s\n' "$hash" "$base" >"$tmp_sha"
          mv "$tmp_sha" "$target_sidecar"
        fi
        continue
      fi
    fi

    tmp="$mirror/.${base}.tmp"
    tmp_sha="$mirror/.${base}.sha256.tmp"
    rm -f "$tmp" "$tmp_sha"
    timeout 300 cp "$archive" "$tmp"
    hash2="$(sha256sum "$tmp" | awk '{print $1}')"
    if [[ "$hash" != "$hash2" ]]; then
      rm -f "$tmp"
      echo "error: checksum mismatch copying $base to $mirror" >&2
      exit 1
    fi
    if ! timeout 300 7z t -p"$PASSWORD" "$tmp" >/dev/null; then
      rm -f "$tmp"
      echo "error: archive test failed copying $base to $mirror" >&2
      exit 1
    fi
    printf '%s  %s\n' "$hash" "$base" >"$tmp_sha"
    mv "$tmp" "$target"
    mv "$tmp_sha" "$target_sidecar"
    copied=$((copied + 1))
    echo "synced $base -> $mirror"
  done
done

echo "sync: copied=$copied"
