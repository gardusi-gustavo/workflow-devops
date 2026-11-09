#!/usr/bin/env bash
# Create one encrypted Gitea dump, publish it to every required destination,
# verify the copies, then prune oldest-first.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY="${BACKUP_POLICY:-$SCRIPT_DIR/../../config/backup-policy.json}"
CONTAINER="${GITEA_CONTAINER:-gitea}"
VERIFY="$SCRIPT_DIR/verify-dump-contents.sh"
PRUNE="$SCRIPT_DIR/prune-dumps.sh"
SYNC="$SCRIPT_DIR/sync-backups.sh"

[[ -r "$POLICY" ]] || { echo "error: cannot read $POLICY" >&2; exit 2; }
command -v docker >/dev/null || { echo "error: docker is required" >&2; exit 2; }
command -v 7z >/dev/null || { echo "error: 7z is required" >&2; exit 2; }
command -v unzip >/dev/null || { echo "error: unzip is required" >&2; exit 2; }
command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 2; }
command -v flock >/dev/null || { echo "error: flock is required" >&2; exit 2; }

primary="$(jq -r '.primary_dir' "$POLICY")"
# shellcheck source=mirrors.sh
source "$(dirname "${BASH_SOURCE[0]}")/mirrors.sh"
load_mirror_dirs "$POLICY" || { echo "error: no backup mirrors resolved" >&2; exit 2; }
mirrors=("${MIRROR_DIRS[@]}")
max_bytes="$(jq -r '.retention.max_bytes // 5368709120' "$POLICY")"
reserve="$(jq -r '.retention.reserve_bytes // 536870912' "$POLICY")"
min_keep="$(jq -r '.retention.minimum_valid_archives // 5' "$POLICY")"
prune_order="$(jq -r '.retention.prune // "oldest_first"' "$POLICY")"
password_file="$(jq -r '.password_file // "/srv/backup/secrets/backup.pass"' "$POLICY")"
name_template="$(jq -r '.name_template // "gitea-%Y%m%dT%H%M%SZ"' "$POLICY")"
data_dir="$(jq -r '.data_dir // "/srv/gitea/data"' "$POLICY")"
uid="$(jq -r '.gitea_uid // 1003' "$POLICY")"
gid="$(jq -r '.gitea_gid // 1003' "$POLICY")"
quiesce="${BACKUP_QUIESCE:-$(jq -r '.quiesce // true' "$POLICY")}"
mirror_mode="$(jq -r '.mirror_mode // "required"' "$POLICY")"
status_dir="$(jq -r '.status_dir // "/srv/backup/status"' "$POLICY")"
mode="${BACKUP_MODE:-manual}"
inventory="${BACKUP_INVENTORY:-skipped}"

[[ "$prune_order" == "oldest_first" || "$prune_order" == "oldest-first" ]] || {
  echo "error: unsupported prune order: $prune_order" >&2
  exit 2
}
if ! [[ "$min_keep" =~ ^[0-9]+$ ]] || (( min_keep < 1 )); then
  echo "error: minimum_valid_archives must be at least 1" >&2
  exit 2
fi
[[ -r "$password_file" ]] || { echo "error: cannot read password file: $password_file" >&2; exit 2; }
PASSWORD="$(<"$password_file")"
[[ -n "$PASSWORD" ]] || { echo "error: empty password file" >&2; exit 2; }

stamp="$(date -u +"$name_template")"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
work="$(mktemp -d "${TMPDIR:-/tmp}/gitea-backup.XXXXXX")"
dump_zip="$work/dump.zip"
staging="$work/staging"
archive="$work/$stamp.7z"
sidecar="$work/$stamp.7z.sha256"
dest_status="$work/destinations.jsonl"
status_file="$status_dir/backup-latest.json"
stopped=0
sha256=""
archive_size=0
baseline_bytes=0
size_warning=false
result="failed"
critical=0
prune_result="skipped"

mkdir -p "$status_dir"
: >"$dest_status"

mapfile -t prior_sizes < <(find "$primary" -maxdepth 1 -name 'gitea-*.7z' -printf '%s\n' 2>/dev/null | sort -n | tail -5)
if (( ${#prior_sizes[@]} > 0 )); then
  baseline_bytes="$(printf '%s\n' "${prior_sizes[@]}" | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}')"
fi

record_dest() {
  local name="$1" dir="$2" status="$3" hash="$4"
  jq -n --arg name "$name" --arg dir "$dir" --arg status "$status" --arg sha256 "$hash" \
    '{name:$name,dir:$dir,status:$status,sha256:$sha256}' >>"$dest_status"
}

write_status() {
  local destinations="[]"
  if [[ -s "$dest_status" ]]; then
    destinations="$(jq -s '.' "$dest_status")"
  fi
  jq -n \
    --arg started_at "$started_at" \
    --arg finished_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg mode "$mode" \
    --arg archive "$(basename "$archive")" \
    --arg sha256 "$sha256" \
    --argjson size_bytes "${archive_size:-0}" \
    --argjson size_baseline_bytes "${baseline_bytes:-0}" \
    --argjson size_warning "$([ "$size_warning" = true ] && echo true || echo false)" \
    --argjson destinations "$destinations" \
    --arg inventory "$inventory" \
    --arg result "$result" \
    --argjson critical "$([ "$critical" = 1 ] && echo true || echo false)" \
    --arg prune "$prune_result" \
    '{started_at:$started_at,finished_at:$finished_at,mode:$mode,archive:$archive,sha256:$sha256,size_bytes:$size_bytes,size_baseline_bytes:$size_baseline_bytes,size_warning:$size_warning,destinations:$destinations,inventory:$inventory,result:$result,critical:$critical,prune:$prune}' \
    >"$status_file"
  chown "${BACKUP_OWNER:-user}:${BACKUP_OWNER:-user}" "$status_file" 2>/dev/null || true
}

cleanup() {
  if (( stopped )); then
    docker start "$CONTAINER" >/dev/null 2>&1 || echo "warning: failed to restart $CONTAINER" >&2
  fi
  rm -rf "$work"
}
trap cleanup EXIT INT TERM

preflight() {
  local dir="$1" label="$2" required="$3" avail estimate=157286400
  if [[ ! -d "$dir" ]]; then
    if [[ "$required" == "true" ]]; then
      echo "error: $label destination is missing: $dir" >&2
      return 1
    fi
    echo "warning: $label destination is missing: $dir" >&2
    return 0
  fi
  avail="$(df -B1 --output=avail "$dir" | tail -1 | tr -d ' ')"
  if (( avail < reserve + estimate )); then
    echo "error: $label has $avail bytes free; need reserve $reserve plus estimate $estimate" >&2
    return 1
  fi
  return 0
}

publish_one() {
  local name="$1" dir="$2" required="$3"
  local tmp="$dir/.${stamp}.7z.tmp"
  local tmp_sha="$dir/.${stamp}.7z.sha256.tmp"
  local hash2

  if [[ ! -d "$dir" ]]; then
    record_dest "$name" "$dir" "missing" ""
    return 1
  fi
  if ! mkdir -p "$dir" 2>/dev/null; then
    record_dest "$name" "$dir" "unwritable" ""
    return 1
  fi
  rm -f "$tmp" "$tmp_sha"
  if ! timeout 300 cp "$archive" "$tmp" || ! timeout 60 cp "$sidecar" "$tmp_sha"; then
    rm -f "$tmp" "$tmp_sha"
    record_dest "$name" "$dir" "copy_failed" ""
    return 1
  fi
  hash2="$(sha256sum "$tmp" | awk '{print $1}')"
  if [[ "$hash2" != "$sha256" ]]; then
    rm -f "$tmp" "$tmp_sha"
    record_dest "$name" "$dir" "checksum_failed" ""
    return 1
  fi
  if ! timeout 300 7z t -p"$PASSWORD" "$tmp" >/dev/null; then
    rm -f "$tmp" "$tmp_sha"
    record_dest "$name" "$dir" "integrity_failed" ""
    return 1
  fi
  mv "$tmp" "$dir/$stamp.7z"
  mv "$tmp_sha" "$dir/$stamp.7z.sha256"
  chown "${BACKUP_OWNER:-user}:${BACKUP_OWNER:-user}" "$dir/$stamp.7z" "$dir/$stamp.7z.sha256" 2>/dev/null || true
  timeout 120 sync "$dir/$stamp.7z" "$dir/$stamp.7z.sha256" 2>/dev/null || true
  record_dest "$name" "$dir" "ok" "$sha256"
  return 0
}

prune_one() {
  local dir="$1" min="$2"
  if ! "$PRUNE" --dir "$dir" --budget "$max_bytes" --reserve "$reserve" --min-keep "$min"; then
    return 1
  fi
  return 0
}

echo "== preflight"
preflight "$primary" primary true || { result="failed"; write_status; exit 1; }
if (( ${#mirrors[@]} > 0 )); then
  for dir in "${mirrors[@]}"; do
    [[ -n "$dir" ]] || continue
    preflight "$dir" mirror false || true
  done
fi

echo "== dump Gitea"
if [[ "$quiesce" == "true" ]]; then
  image="$(docker inspect "$CONTAINER" --format '{{.Config.Image}}')"
  docker stop "$CONTAINER" >/dev/null
  stopped=1
  chown "$uid:$gid" "$work"
  docker run --rm -u "$uid:$gid" \
    -v "$data_dir:/data" -v "$work:/out" \
    --entrypoint gitea "$image" dump \
    --config /data/gitea/conf/app.ini --file /out/dump.zip \
    --type zip --skip-log --skip-index
  docker start "$CONTAINER" >/dev/null
  stopped=0
else
  docker exec -u git "$CONTAINER" gitea dump \
    --file "/tmp/$stamp.zip" --type zip --skip-log --skip-index
  docker cp "$CONTAINER:/tmp/$stamp.zip" "$dump_zip" >/dev/null
  docker exec -u git "$CONTAINER" rm -f "/tmp/$stamp.zip" >/dev/null 2>&1 || true
fi

[[ -f "$dump_zip" ]] || { echo "error: dump was not created" >&2; write_status; exit 1; }
mkdir -p "$staging"
unzip -q "$dump_zip" -d "$staging"

echo "== validate"
counts="$(bash "$VERIFY" --root "$staging" --json --fsck)"
version="$(docker exec -u git "$CONTAINER" gitea --version 2>/dev/null | head -1 | awk '{print $3}' || echo unknown)"
cat >"$staging/manifest.txt" <<EOF
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
gitea_version=$version
counts=$counts
command=gitea dump --type zip --skip-log --skip-index
EOF

echo "== create $stamp.7z"
(
  cd "$staging"
  7z a -t7z -mhe=on -mx=0 -ms=off -p"$PASSWORD" "$archive" . >/dev/null
)
7z t -p"$PASSWORD" "$archive" >/dev/null
sha256="$(sha256sum "$archive" | awk '{print $1}')"
printf '%s  %s\n' "$sha256" "$(basename "$archive")" >"$sidecar"
archive_size="$(stat -c '%s' "$archive")"
if (( baseline_bytes > 0 && archive_size > baseline_bytes * 2 )); then size_warning=true; fi
if (( archive_size > 536870912 )); then size_warning=true; fi
echo "archive: $archive sha256=$sha256 size=$archive_size baseline=$baseline_bytes warning=$size_warning"

echo "== publish copies"
primary_ok=0
mirror_failed=0
if publish_one primary "$primary" true; then primary_ok=1; fi

if (( primary_ok == 0 )); then
  result="failed"
  write_status
  echo "error: primary publish failed" >&2
  exit 1
fi

for dir in "${mirrors[@]}"; do
  [[ -n "$dir" ]] || continue
  if ! publish_one mirror "$dir" true; then
    mirror_failed=1
    echo "warning: mirror publish failed: $dir" >&2
  fi
done

if (( mirror_failed )); then
  if [[ "$mode" == "scheduled" || "$mirror_mode" == "required" ]]; then
    result="failed"
    prune_result="skipped"
    write_status
    echo "error: required mirror publish failed; no pruning performed" >&2
    exit 1
  fi
  result="degraded"
  prune_result="skipped"
  write_status
  echo "warning: manual backup degraded; no pruning performed" >&2
  exit 0
fi

if [[ -x "$SYNC" ]]; then
  echo "== reconcile missing archives"
  if ! "$SYNC" --primary "$primary" --policy "$POLICY"; then
    result="failed"
    prune_result="skipped"
    write_status
    echo "error: backup reconciliation failed; no pruning performed" >&2
    exit 1
  fi
fi

echo "== prune"
prune_failed=0
for dir in "$primary" "${mirrors[@]}"; do
  [[ -n "$dir" ]] || continue
  if ! prune_one "$dir" "$min_keep"; then
    echo "warning: $dir still over budget with minimum $min_keep; pruning to newest archive" >&2
    critical=1
    if ! prune_one "$dir" 1; then
      prune_failed=1
    fi
  fi
done

if (( prune_failed )); then
  result="failed"
  prune_result="failed"
elif (( critical )); then
  result="success"
  prune_result="critical"
else
  result="success"
  prune_result="ok"
fi

write_status
echo "backup: $primary/$stamp.7z result=$result"
if (( prune_failed )) || { (( critical )) && [[ "$mode" == "scheduled" ]]; }; then
  exit 1
fi
