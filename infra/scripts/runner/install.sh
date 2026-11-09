#!/usr/bin/env bash
# Install the Gitea runner in gitea-runner's rootless Docker.
# Run as gitea-runner; do not run as root.
set -euo pipefail
export DOCKER_HOST="${DOCKER_HOST:-unix:///run/user/$(id -u)/docker.sock}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
RUNNER_HOME="${RUNNER_HOME:-$HOME/runner}"

[[ "$(id -u)" -ne 0 ]] || { echo "run as gitea-runner, not root" >&2; exit 1; }
[[ "$(id -un)" == "gitea-runner" ]] || { echo "run as gitea-runner" >&2; exit 1; }
docker info >/dev/null
docker info --format '{{json .SecurityOptions}}' | grep -q rootless || {
  echo "error: Docker is not rootless" >&2; exit 1;
}

install -d -m 700 "$RUNNER_HOME"
install -m 600 "$ROOT/infra/runner/compose.yml" "$RUNNER_HOME/compose.yml"
install -m 600 "$ROOT/infra/runner/config.yml" "$RUNNER_HOME/config.yml"

if [[ ! -f "$RUNNER_HOME/data/.runner" ]]; then
  : "${GITEA_RUNNER_REGISTRATION_TOKEN:?set GITEA_RUNNER_REGISTRATION_TOKEN for first registration}"
  cat > "$RUNNER_HOME/.env" <<ENV
GITEA_INSTANCE_URL=${GITEA_INSTANCE_URL:-http://172.18.0.1:3001}
GITEA_RUNNER_NAME=${GITEA_RUNNER_NAME:-local-runner}
GITEA_RUNNER_REGISTRATION_TOKEN=${GITEA_RUNNER_REGISTRATION_TOKEN}
ENV
  chmod 600 "$RUNNER_HOME/.env"
fi

cd "$RUNNER_HOME"
docker compose up -d
docker compose ps
