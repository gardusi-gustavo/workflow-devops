#!/usr/bin/env bash
# Collect Gitea repository health into JSONL.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/src"
exec python3 -m observability.collect "$@"
