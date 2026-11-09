#!/usr/bin/env bash
# Mirror local staging repositories to GitHub. Dry run by default.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

if (( APPLY )); then
  : "${GH_TOKEN:?GH_TOKEN is required}"
  command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
fi

repos="$(jq -r '.repos[] | select(.group=="gardusi-gustavo") | .name' "$ROOT/infra/config/repos.json")"
for name in $repos; do
  local_repo="$HOME/repos/gardusi-gustavo/$name"
  [[ -d "$local_repo/.git" ]] || { echo "skip $name: no local repository"; continue; }
  if ! gh repo view "gardusi-gustavo/$name" >/dev/null 2>&1; then
    echo "would create gardusi-gustavo/$name"
    if (( APPLY )); then
      gh repo create "gardusi-gustavo/$name" --public --source "$local_repo" --remote github --push
    fi
  else
    echo "exists gardusi-gustavo/$name"
    if (( APPLY )); then
      git -C "$local_repo" remote get-url github >/dev/null 2>&1 || \
        git -C "$local_repo" remote add github "https://github.com/gardusi-gustavo/$name.git"
      git -C "$local_repo" push github main
    fi
  fi
done

private_local="${PRIVATE_LOCAL:-$HOME/repos/gardusi-gustavo/private}"
if [[ -d "$private_local/.git" ]]; then
  echo "== private"
  if ! gh repo view "gardusi-gustavo/private" >/dev/null 2>&1; then
    echo "would create gardusi-gustavo/private (private)"
    if (( APPLY )); then
      gh repo create "gardusi-gustavo/private" --private --source "$private_local" --remote github --push
    fi
  else
    echo "exists gardusi-gustavo/private"
    if (( APPLY )); then
      git -C "$private_local" remote get-url github >/dev/null 2>&1 || \
        git -C "$private_local" remote add github "https://github.com/gardusi-gustavo/private.git"
      git -C "$private_local" push github main
    fi
  fi
fi
