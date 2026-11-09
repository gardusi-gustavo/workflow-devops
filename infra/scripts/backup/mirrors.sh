#!/usr/bin/env bash
# Resolve backup mirror directories from the gardusi-gustavo/private device config.
# The private repo owns card mounts, labels, UUIDs, and the backup subpath.
set -euo pipefail

resolve_mirror_dirs() {
  local policy="$1"
  local config sub
  config="$(jq -r '.device_config // empty' "$policy")"
  sub="$(jq -r '.vault_backup_subdir // "0-library/backup/gitea-dumps"' "$policy")"
  if [[ -z "$config" || ! -r "$config" ]]; then
    echo "error: missing device config: ${config:-unset}" >&2
    return 1
  fi
  jq -r --arg sub "$sub" \
    'to_entries[]
     | select(.value.role == "card" or .value.role == "backup")
     | "\(.value.mount)/\($sub)"' "$config"
}

load_mirror_dirs() {
  local policy="$1" line out
  out="$(resolve_mirror_dirs "$policy")" || return 1
  MIRROR_DIRS=()
  while IFS= read -r line; do
    if [[ -n "$line" ]]; then
      MIRROR_DIRS+=("$line")
    fi
  done <<<"$out"
  (( ${#MIRROR_DIRS[@]} > 0 ))
}
