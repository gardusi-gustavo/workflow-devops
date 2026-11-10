# 💾 Backup

**What this is:** one encrypted `.7z` per run, copied to every required
destination and verified before any pruning.

Per-repository Git history now has a portable bundle path: see
[`bundles.md`](bundles.md). Bundles do not replace metadata, issues, PRs,
attachments, or forge settings; the full dump remains the cold fallback until a
metadata export is verified.

## Artifact

```text
gitea-<UTC-stamp>.7z
gitea-<UTC-stamp>.7z.sha256
```

The archive contains the complete Gitea state. The sidecar contains the SHA256
of the archive and is copied to every destination.

Inside the archive:

```text
manifest.txt
repos/<org>/<repo>.git
data/gitea.db
data/attachments
data/avatars
data/packages
data/conf/app.ini
app.ini
gitea-db.sql
```

`manifest.txt` records creation time, Gitea version, table counts, and the dump
command.

## Policy

`infra/config/backup-policy.json`:

- Primary: `/srv/backup/gitea-dumps`
- Mirrors: resolved from `gardusi-gustavo/private/infra/config/offline-devices.json`;
  the card target is `<microsd mount>/0-library/backup/gitea-dumps`
- 5 GB ceiling per destination
- 512 MB reserve
- Keep at least 5 validated archives
- Prune oldest first, never the newest validated archive
- Quiesce, encrypt, copy, verify, then prune
- Required mirrors for scheduled runs
- Device mounts resolved from `gardusi-gustavo/private/infra/config/offline-devices.json`
- Card dumps older than 30 days are pruned when the folder exceeds 4.5 GiB,
  always keeping the newest 5 archives

The effective limit is the smaller of the 5 GB ceiling minus reserve and the
filesystem capacity minus reserve. A destination with less free space is
capacity-bound, not silently over budget.

## Modes

```text
BACKUP_MODE=scheduled   systemd timer; missing required mirror is a failure
BACKUP_MODE=manual      interactive run; missing mirror is degraded
```

A degraded manual backup is not reported as complete. It records
`result: "degraded"` and skips pruning.

## Generate

```bash
cd /home/user/repos/gardusi-gustavo/workflow-event
sudo ./infra/scripts/backup/make.sh
```

Flow:

1. Acquire `/run/lock/gitea-backup.lock`.
2. Verify inventory when `GITEA_TOKEN` is available.
3. Preflight reserve and estimated archive size on required destinations.
4. Stop Gitea.
5. Run `gitea dump` in a one-off container.
6. Restart Gitea in a trap.
7. Extract and validate the dump.
8. Write `manifest.txt`.
9. Create one AES-256 `.7z`.
10. Run `7z t`, write the SHA256 sidecar.
11. Copy to temporary names on every required destination.
12. Verify SHA256 and `7z t` on every copy.
13. Atomically rename the archive and sidecar.
14. Reconcile missing archives from primary to mirrors.
15. Prune oldest first on each destination.
16. Write `/srv/backup/status/backup-latest.json`.

If a required copy fails, the run fails and no destination is pruned.

Validation checks:

- SQLite `PRAGMA integrity_check`
- repository, issue, PR, user, comment, and attachment counts
- `git fsck --connectivity-only` on every repository
- `repos/`, `data/gitea.db`, `gitea-db.sql`, and `app.ini`

## Verify

```bash
7z t -p"$PASSWORD" gitea-....7z
sha256sum -c gitea-....7z.sha256
```

The backup run performs both checks on every destination before publishing.

## Retention

```text
gitea-...-oldest.7z   delete first
gitea-...-newest.7z   always keep
```

At about 113 MB per archive, 5 GB holds roughly 39 archives after the reserve.
Retention is independent per destination.

If the minimum of five archives cannot fit, the run keeps the newest archive,
marks the result critical, and fails a scheduled run.

## Size warnings

The backup status records `size_baseline_bytes` and `size_warning`.

- Baseline: median of the previous five archives.
- Warning: the new archive is more than twice the baseline or larger than
  512 MB.
- The warning is informational; the hard cap and oldest-first pruning still
  enforce retention.

When a warning appears, audit the source:

```bash
./infra/scripts/backup/audit-large-blobs.sh --top 10
./infra/scripts/backup/audit-large-blobs.sh --top 3 --deep
```

Keep generated PDFs and heavy exports out of Git. Files over 5 MB belong in a
dedicated asset path such as `/srv/assets`, not in a repository or the backup
directory.

## Restore

```bash
./infra/scripts/backup/restore-dump.sh \
  --dump /srv/backup/gitea-dumps/gitea-....7z \
  --out /tmp/gitea-restore
```

The script decrypts, verifies, and prepares:

```text
/tmp/gitea-restore/data/gitea
/tmp/gitea-restore/data/git/repositories
```

Then start a temporary instance on a separate port:

```bash
chown -R 1000:1000 /tmp/gitea-restore/data
docker run -d --name gitea-restore -p 3002:3000 \
  -v /tmp/gitea-restore/data:/data gitea/gitea:28.2.0
```

Production can stay running. Verify login, repositories, tags, issues, PRs,
attachments, and Git operations before replacing production.

## Automation

```bash
sudo ./infra/scripts/backup/install-timer.sh
systemctl list-timers gitea-backup.timer
journalctl -u gitea-backup.service
```

The timer runs daily between 03:00 and 06:00 and catches up after downtime.

Check target health:

```bash
./infra/scripts/backup/backup-status.sh
./infra/scripts/backup/verify-latest-backup.sh
```

`backup-status.sh` reports archive count, size, free space, newest archive,
timer state, and the last backup/verification/restore records.
`verify-latest-backup.sh` checks archive age, checksum, integrity, and mirror
parity.

Install the monthly local restore test:

```bash
sudo ./infra/scripts/backup/install-restore-timer.sh
systemctl list-timers gitea-restore-test.timer
```

## Outside the dump

- uncommitted local changes
- untracked files
- external application databases
- Docker volumes not owned by Gitea
- secrets outside the Gitea data directory
- systemd units, runner config, and compose files

## Related

- Monthly local restore and quarterly separate-host restore:
  `docs/repository/disaster-recovery-test.md`
- Environment and accounts: `docs/repository/agent-env.md`
- Card state and sync: `gardusi-gustavo/private/docs/offline/state/` and
  `gardusi-gustavo/private/docs/offline/sync.md`
- Public data policy: `docs/public-data.md`
