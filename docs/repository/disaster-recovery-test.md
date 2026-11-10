# 🧯 Disaster recovery test

**What this is:** a quarterly check that the newest backup restores into a
working Gitea instance.

Creating a backup is not proof. Only a restore is.

## Cadence

- Local restore: monthly, against the newest archive.
- Separate-host restore: quarterly, using the microSD or USB copy.

A monthly local restore catches routine recovery failures. The quarterly
separate-host test covers host loss.

## Before you start

- The newest `gitea-*.7z` from `/srv/backup/gitea-dumps`.
- The password file, normally `/srv/backup/secrets/backup.pass`.
- Docker and the matching `gitea/gitea` image.
- Port `3002` free.
- At least 1 GB free under `/tmp` or the chosen restore path.

Do not stop or modify the production Gitea instance. The test uses a separate
container and a separate data directory.

## Procedure

1. Pick the newest archive.

   ```bash
   archive="$(ls -1t /srv/backup/gitea-dumps/gitea-*.7z | head -1)"
   echo "$archive"
   ```

2. Extract and validate it.

   ```bash
   ./infra/scripts/backup/restore-dump.sh \
     --dump "$archive" \
     --out /tmp/gitea-dr-test
   ```

3. Prepare ownership and start an isolated Gitea 28.2.0 container.

   ```bash
   chown -R 1000:1000 /tmp/gitea-dr-test/data
   docker run -d --name gitea-dr-test -p 3002:3000 \
     -e GITEA__server__ROOT_URL=http://127.0.0.1:3002/ \
     -e GITEA__server__DOMAIN=127.0.0.1 \
     -e GITEA__server__HTTP_PORT=3000 \
     -e GITEA__server__START_SSH_SERVER=false \
     -v /tmp/gitea-dr-test/data:/data gitea/gitea:28.2.0
   ```

4. Verify login and the UI.

   ```bash
   curl -fsS http://127.0.0.1:3002/api/v1/version
   curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3002/
   ```

   Open the UI and sign in with a known account. Check that no unexpected
   password reset or setup screen appears.

5. Verify the repository count.

   ```bash
   find /tmp/gitea-dr-test/data/git/repositories \
     -mindepth 2 -maxdepth 2 -type d -name '*.git' | wc -l
   ```

   Compare with the count in `manifest.txt` inside the archive.

6. Verify tags and commits.

   ```bash
   git --git-dir=/tmp/gitea-dr-test/data/git/repositories/gardusi-gustavo/workflow-event.git tag --list
   git --git-dir=/tmp/gitea-dr-test/data/git/repositories/gardusi-gustavo/workflow-event.git log --oneline -3
   ```

7. Verify issues and pull requests.

   Open a known issue and a known pull request. Check titles, comments, labels,
   and review state.

8. Verify attachments.

   ```bash
   python3 - <<'PY'
   import sqlite3
   db = sqlite3.connect('/tmp/gitea-dr-test/data/gitea/gitea.db')
   for table in ('repository', 'issue', 'pull_request', 'user', 'comment', 'attachment'):
       print(table, db.execute(f'select count(*) from "{table}"').fetchone()[0])
   print('integrity', db.execute('pragma integrity_check').fetchone()[0])
   PY
   ```

9. Verify Git transport.

   ```bash
   GIT_TERMINAL_PROMPT=0 git ls-remote http://127.0.0.1:3002/gardusi-gustavo/workflow-event.git
   ```

10. Record the result below, then remove the test instance.

    ```bash
    docker rm -f gitea-dr-test
    rm -rf /tmp/gitea-dr-test
    ```

## Record

| Date | Archive | Gitea | Repos | Git dirs | Issues | PRs | Users | Attachments | Elapsed | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2026-11-06 | `gitea-20261106T123857Z.7z` | 28.2.0 | 24 | 28 | 812 | 426 | 8 | 15 | ~20s | pass |

The 2026-11-06 restore verified:

- open issues: 252
- open pull requests: 0
- archived repositories: 2
- private repositories: 2
- SQLite `integrity_check`: `ok`
- UI: `200`
- `git ls-remote`: returned `refs/heads/main`
- Production Gitea was not stopped
- Test container and restore directory removed

## Failure handling

Do not delete the archive that failed. Keep it for diagnosis and restore from
the previous archive. File the failure as a `3.x` bug with the archive name,
the failing step, and the exact error. Run the test again after the fix.

## Related

- Backup generation and retention: `docs/repository/backup.md`
- Environment and accounts: `docs/repository/agent-env.md`
