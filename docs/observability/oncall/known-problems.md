# 🧠 Known problems

**What this is:** operational failures already seen, their cause, workaround, and
the issue that closes the gap. Add a row after every incident or surprise.

| Area | Symptom | Cause | Workaround | Follow-up |
| --- | --- | --- | --- | --- |
| Gitea dump | `permission denied` on `app.ini.bak` | root-owned file inside the data dir | keep backups outside `/data/gitea` | #19 |
| Grafana / Prometheus | container restarts, permission errors | data dir UID mismatch (`472`, `65534`) | `chown` the data dirs | #19 |
| Docker secrets | `/run/secrets` permission denied | bind-mounted secret not readable by the container user | direct file mount with `0644` | #19 |
| Tag protection | `user not allowed to create protected tag` | `v*` protection with an empty allowlist | allow `human` | #19 |
| Runner | 60m image job killed early | runner timeout was 10m | runner timeout 60m | #24 |
| Private CI | commit status API returns `null` | private-repo status not exposed | use the Actions run page | #25 |
| Local repos | backup manifest mismatch | local `main` stale after squash merge | reset to `origin/main` before backup | #18 |
| Recovery bundle | `targets.json` missing | relative path failed in installed tooling | copy `/srv/backup/targets.json` | #19 |
| Target registry | source says USB optional, runtime required | hand-edited runtime copy | install/render script | #19 |
| Legacy backup | two commands with different targets | `manual.sh` vs `store.sh` | retire `manual.sh` | #16 |
| Staging | 934 MB `.stage` left behind | no clean mode | `store.sh clean` | #18 |
| Package versions | tag `v0.2.8`, package `0.1.0` | tags bumped without package versions | release policy | infrastructure/templates#30 |
| Audit log | DB mtime newer than dump | audit writes after dump | compare content, not mtime | #21 |
| Git as root | `dubious ownership` | root reads `bot-event` repos | `safe.directory` or `runuser` | #19 |
| USB prep | `/dev/...-part1` missing after `sgdisk` | udev race | `partprobe` + `udevadm settle` | #18 |
| USB identity | same model/size, letters swap | two identical sticks | always use `/dev/disk/by-id` | #18 |
| Agent PRs | cannot approve own PR | PR authored by `human` | author as `bot-event` | #19 |
| Records merge | YAML rejected in `infra/config` | validator requires JSON | keep YAML under `src/.../config` | #19 |

## Rules

- One row per distinct failure, not per occurrence.
- Link the issue that removes the workaround.
- Move the row to the postmortem when the root cause is fixed.
- Do not put secrets or private data in this file.
