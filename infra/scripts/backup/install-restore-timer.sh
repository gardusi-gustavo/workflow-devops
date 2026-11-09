#!/usr/bin/env bash
# Install or remove the monthly Gitea restore-test systemd timer.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
UNIT_DIR="/etc/systemd/system"
SERVICE="gitea-restore-test.service"
TIMER="gitea-restore-test.timer"

[[ "$(id -u)" == "0" ]] || { echo "error: run as root" >&2; exit 2; }

if [[ "${1:-}" == "--remove" ]]; then
  systemctl disable --now "$TIMER" 2>/dev/null || true
  rm -f "$UNIT_DIR/$SERVICE" "$UNIT_DIR/$TIMER"
  systemctl daemon-reload
  echo "removed $SERVICE and $TIMER"
  exit 0
fi

cat >"$UNIT_DIR/$SERVICE" <<EOF
[Unit]
Description=Monthly Gitea restore test
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
EnvironmentFile=-/home/user/.config/gitea/env
Environment=BACKUP_OWNER=user
ExecStart=$ROOT/infra/scripts/backup/restore-test.sh
Nice=10
IOSchedulingClass=best-effort
TimeoutStartSec=3600
EOF

cat >"$UNIT_DIR/$TIMER" <<'EOF'
[Unit]
Description=Monthly Gitea restore test

[Timer]
OnCalendar=*-*-01 12:00:00
Persistent=true
RandomizedDelaySec=1h
AccuracySec=1m

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now "$TIMER"
systemctl --no-pager --lines=0 status "$TIMER" || true
echo "installed $SERVICE and $TIMER"
