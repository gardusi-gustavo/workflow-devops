#!/usr/bin/env bash
# Verify the archive migration manifest against the archived repository inventory.
set -euo pipefail

ROOT="."
STRICT=0
CHECK_PATHS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --strict) STRICT=1; shift ;;
    --check-paths) CHECK_PATHS=1; shift ;;
    -h|--help)
      echo "usage: verify-migration.sh [--root PATH] [--strict] [--check-paths]"
      exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
MANIFEST="$ROOT/infra/config/archive-migration.json"
SCHEMA="$ROOT/infra/config/archive-migration.schema.json"
REPOS="$ROOT/infra/config/repos.json"
[[ -s "$MANIFEST" ]] || { echo "missing $MANIFEST" >&2; exit 1; }
[[ -s "$SCHEMA" ]] || { echo "missing $SCHEMA" >&2; exit 1; }
[[ -s "$REPOS" ]] || { echo "missing $REPOS" >&2; exit 1; }

jq empty "$MANIFEST" >/dev/null || { echo "invalid JSON: $MANIFEST" >&2; exit 1; }
[[ "$(jq -r '.version // empty' "$MANIFEST")" == "1.0" ]] || {
  echo "manifest version must be 1.0" >&2; exit 1; }

errors=0
fail() { echo "ERROR: $*" >&2; errors=$((errors+1)); }

mapfile -t archived < <(jq -r '.repos[] | select(.archived == true) | "\(.group)/\(.name)"' "$REPOS" | sort)
mapfile -t sources < <(jq -r '.entries[].source' "$MANIFEST" | sort)

while IFS=$'\t' read -r source status; do
  [[ -n "$source" ]] || continue
  count="$(printf '%s\n' "${sources[@]}" | grep -Fxc "$source" || true)"
  (( count == 1 )) || fail "manifest source must appear once: $source (count=$count)"
  if [[ "$status" != "deleted" ]] && ! printf '%s\n' "${archived[@]}" | grep -qxF "$source"; then
    fail "manifest source is not an archived repository: $source"
  fi
done < <(jq -r '.entries[] | [.source, .status] | @tsv' "$MANIFEST")

while IFS= read -r source; do
  [[ -n "$source" ]] || continue
  printf '%s\n' "${sources[@]}" | grep -qxF "$source" || fail "archived repository missing from manifest: $source"
done < <(printf '%s\n' "${archived[@]}")

jq -e '.entries | type == "array"' "$MANIFEST" >/dev/null || fail "entries must be an array"
jq -e 'all(.entries[]; has("source") and has("source_head") and has("status") and has("targets") and has("tracked_files") and has("mapping") and has("dropped") and has("pending") and has("reason"))' "$MANIFEST" >/dev/null ||
  fail "every entry needs source, source_head, status, targets, tracked_files, mapping, dropped, pending, reason"
jq -e 'all(.entries[]; .status | IN("migrated","split","deleted","dropped","cold-storage","pending"))' "$MANIFEST" >/dev/null ||
  fail "invalid status"
jq -e 'all(.entries[]; if (.status == "migrated" or .status == "split") then (.targets | length) > 0 else true end)' "$MANIFEST" >/dev/null ||
  fail "migrated/split entries need at least one target"
jq -e 'all(.entries[]; all(.mapping[]?; has("from") and has("target") and has("to")))' "$MANIFEST" >/dev/null ||
  fail "mapping entries need from, target, and to"

target_path() {
  case "$1" in
    gardusi-gustavo/*) printf '%s/repos/gardusi-gustavo/%s' "$HOME" "${1#gardusi-gustavo/}" ;;
    human/private) printf '%s/repos/human/private' "$HOME" ;;
    *) printf '' ;;
  esac
}

if (( CHECK_PATHS )); then
  while IFS=$'\t' read -r source status pending target to; do
    [[ -n "$target" && -n "$to" ]] || continue
    [[ "$to" == "*" ]] && continue
    case "$status" in
      pending|cold-storage|dropped|deleted) continue ;;
    esac
    skip=0
    IFS='|' read -r -a pend <<<"$pending"
    for prefix in "${pend[@]}"; do
      [[ -n "$prefix" && "$to" == "$prefix"* ]] && skip=1
    done
    (( skip )) && continue
    repo="$(target_path "$target")"
    if [[ -z "$repo" || ! -d "$repo" ]]; then
      echo "PENDING target not local: $source -> $target/$to"
      continue
    fi
    if [[ "$to" == */ ]]; then
      [[ -d "$repo/$to" ]] || fail "missing mapped directory: $target/$to (from $source)"
    else
      [[ -e "$repo/$to" ]] || fail "missing mapped path: $target/$to (from $source)"
    fi
  done < <(jq -r '.entries[] | .source as $s | .status as $st | (.pending // [] | join("|")) as $p | .mapping[]? | [$s, $st, $p, .target, .to] | @tsv' "$MANIFEST")
fi

pending="$(jq '[.entries[] | select(.status == "pending")] | length' "$MANIFEST")"
migrated="$(jq '[.entries[] | select(.status == "migrated")] | length' "$MANIFEST")"
split="$(jq '[.entries[] | select(.status == "split")] | length' "$MANIFEST")"
deleted="$(jq '[.entries[] | select(.status == "deleted")] | length' "$MANIFEST")"
dropped="$(jq '[.entries[] | select(.status == "dropped")] | length' "$MANIFEST")"
cold="$(jq '[.entries[] | select(.status == "cold-storage")] | length' "$MANIFEST")"

echo "archive migration: entries=$(jq '.entries | length' "$MANIFEST") migrated=$migrated split=$split deleted=$deleted pending=$pending dropped=$dropped cold-storage=$cold"
(( errors == 0 )) || exit 1
if (( STRICT && pending > 0 )); then
  echo "ERROR: $pending entries are still pending" >&2
  exit 1
fi
