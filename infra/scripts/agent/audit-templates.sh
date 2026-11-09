#!/usr/bin/env bash
# Read-only audit: consumer template files must match the canonical source.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_JSON="${REPOS_JSON:-$SCRIPT_DIR/../../config/repos.json}"
TEMPLATE_ROOT="${TEMPLATE_ROOT:-/home/user/repos/infrastructure/templates}"
REPOS_ROOT="${REPOS_ROOT:-/home/user/repos}"

[[ -r "$REPOS_JSON" ]] || { echo "error: missing $REPOS_JSON" >&2; exit 2; }
[[ -d "$TEMPLATE_ROOT" ]] || { echo "error: missing $TEMPLATE_ROOT" >&2; exit 2; }

files=(
  .gitea/pull_request_template.md
  infra/scripts/ci/check-size.sh
  infra/scripts/ci/entrypoint.sh
  infra/scripts/ci/validate-repo.sh
  infra/scripts/ci/validate-files.sh
  infra/scripts/ci/validate-labels.sh
  infra/scripts/ci/validate-pr-size.sh
  infra/scripts/ci/pr-size-check.sh
  infra/scripts/ci/validate-risk.sh
  infra/scripts/ci/validate-md-links.sh
  infra/scripts/ci/validate-pr-count.sh
  infra/scripts/ci/validate-coverage.sh
  infra/scripts/check-layout.sh
)

source_version="$(tr -d '[:space:]' < "$TEMPLATE_ROOT/template.version")"
violations=0
fail() { echo "$*"; violations=$((violations + 1)); }

while IFS= read -r repo; do
  [[ -n "$repo" ]] || continue
  [[ "$repo" == "infrastructure/templates" ]] && continue
  [[ "$repo" == "packages/docker-repository-toolkit" ]] && continue
  dir="$REPOS_ROOT/$repo"
  if [[ ! -d "$dir" ]]; then
    fail "$repo: missing local checkout"
    continue
  fi
  version="$(jq -r '.template.version // 0' "$dir/infra/config/repo.json" 2>/dev/null || echo 0)"
  [[ "$version" == "$source_version" ]] || fail "$repo: template.version $version != $source_version"
  for f in "${files[@]}"; do
    src="$TEMPLATE_ROOT/$f"
    dst="$dir/$f"
    [[ -f "$src" ]] || { fail "$repo: canonical file missing: $f"; continue; }
    if [[ ! -f "$dst" ]]; then
      fail "$repo: missing $f"
    elif [[ "$(sha256sum "$src" | awk '{print $1}')" != "$(sha256sum "$dst" | awk '{print $1}')" ]]; then
      fail "$repo: drift in $f"
    fi
  done
done < <(jq -r '.repos[] | "\(.group)/\(.name)"' "$REPOS_JSON")

if (( violations > 0 )); then
  echo "template drift: $violations finding(s)" >&2
  exit 1
fi
echo "template drift: ok"
