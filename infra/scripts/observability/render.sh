#!/usr/bin/env bash
# Render the static telemetry page.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
export PYTHONPATH="$ROOT/src"
exec python3 -m observability.render "$@"
