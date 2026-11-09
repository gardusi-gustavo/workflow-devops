#!/usr/bin/env bash
# Install or remove the daily Gitea backup systemd timer.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
UNIT_DIR="/etc/systemd/system"
SERVICE="gitea-backup.service"
TIMER="gitea-backup.timer"

[[ "$(id -u)" == "0" ]] || { echo "error: run as root" >&2; exit 2; }

if [[ "${1:-}" == "--remove" ]]; then
  systemctl disable --now "$TIMER" 2>/dev/null || true
  rm -f "$UNIT_DIR/$SERVICE" "$UNIT_DIR/$TIMER"
  systemctl daemon-reload
  echo "removed $SERVICE and $TIMER"
  exit 0
fi

cat > "$UNIT_DIR/$SERVICE" <<EOF
[Unit]
Description=Gitea dump backup
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
EnvironmentFile=-/home/user/.config/gitea/env
Environment=BACKUP_OWNER=user
Environment=BACKUP_MODE=scheduled
ExecStart=$ROOT/infra/scripts/backup/make.sh
Nice=10
IOSchedulingClass=best-effort
TimeoutStartSec=3600
EOF

cat > "$UNIT_DIR/$TIMER" <<'EOF'
[Unit]
Description=Daily Gitea dump backup

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
RandomizedDelaySec=3h
AccuracySec=1m

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now "$TIMER"
systemctl --no-pager --lines=0 status "$TIMER" || true
echo "installed $SERVICE and $TIMER"
