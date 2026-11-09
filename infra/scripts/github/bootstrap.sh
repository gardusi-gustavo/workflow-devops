#!/usr/bin/env bash
# Apply per-repository GitHub rulesets and Pages. Dry run by default.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

if (( APPLY )); then
  : "${GH_TOKEN:?GH_TOKEN is required}"
  command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
fi

repos="$(jq -r '.repos[] | select(.group=="gardusi-gustavo" and (.archived // false | not)) | .name' "$ROOT/infra/config/repos.json")"
for name in $repos; do
  full="gardusi-gustavo/$name"
  echo "== $full"
  for ruleset in main database-data tags; do
    file="$ROOT/infra/config/github/rulesets/$ruleset.json"
    [[ -f "$file" ]] || continue
    if (( ! APPLY )); then
      echo "would apply $ruleset"
      continue
    fi
    id="$(gh api "repos/$full/rulesets" --jq ".[] | select(.name==\"$(jq -r .name "$file")\") | .id" 2>/dev/null | head -1 || true)"
    if [[ -n "$id" ]]; then
      gh api -X PUT "repos/$full/rulesets/$id" --input "$file" >/dev/null
    else
      gh api -X POST "repos/$full/rulesets" --input "$file" >/dev/null
    fi
    echo "applied $ruleset"
  done
  case "$name" in
    dashboard-*)
      if (( APPLY )); then
        gh api -X POST "repos/$full/pages" -f build_type=workflow >/dev/null 2>&1 || true
      else
        echo "would enable Pages"
      fi
      ;;
  esac
done

# The private vault has the same main and tag protection, but no Pages and no
# database-data branches.
full="gardusi-gustavo/private"
echo "== $full"
for ruleset in main tags; do
  file="$ROOT/infra/config/github/rulesets/$ruleset.json"
  [[ -f "$file" ]] || continue
  if (( ! APPLY )); then
    echo "would apply $ruleset"
    continue
  fi
  id="$(gh api "repos/$full/rulesets" --jq ".[] | select(.name==\"$(jq -r .name "$file")\") | .id" 2>/dev/null | head -1 || true)"
  if [[ -n "$id" ]]; then
    gh api -X PUT "repos/$full/rulesets/$id" --input "$file" >/dev/null
  else
    gh api -X POST "repos/$full/rulesets" --input "$file" >/dev/null
  fi
  echo "applied $ruleset"
done
