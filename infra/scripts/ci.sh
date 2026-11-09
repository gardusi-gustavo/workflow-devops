#!/usr/bin/env bash
# Validate the workflow-devops control plane.
set -euo pipefail
ROOT="${CI_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"
cd "$ROOT"

"$ROOT/infra/scripts/ci/validate-repo.sh" --root "$ROOT"
"$ROOT/infra/scripts/ci/check-size.sh" --root "$ROOT"

while IFS= read -r f; do bash -n "$f"; done < <(git ls-files '*.sh')
while IFS= read -r f; do python3 -m py_compile "$f"; done < <(git ls-files '*.py')
while IFS= read -r f; do jq empty "$f" >/dev/null; done < <(git ls-files 'infra/config/*.json' 'infra/config/**/*.json')

"$ROOT/infra/scripts/agent/test-pr-limit.sh"
"$ROOT/infra/scripts/agent/test-pr-size.sh"
"$ROOT/infra/scripts/agent/test-pr-size-check.sh"
"$ROOT/infra/scripts/agent/test-risk.sh"
"$ROOT/infra/scripts/agent/test-next-issue.sh"
"$ROOT/infra/scripts/backup/test-prune-dumps.sh"
"$ROOT/infra/scripts/backup/test-verify-dump.sh"
"$ROOT/infra/scripts/archive/verify-migration.sh" --root "$ROOT"
PYTHONPATH="$ROOT/src" python3 -m unittest discover -s "$ROOT/src/tests" -t "$ROOT/src" -q
echo "workflow-devops checks ok"
