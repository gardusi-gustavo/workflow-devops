# Repository bundles

**What this is:** per-repository Git history backups using standard
`git bundle` files, plus immutable tag bundles and a manifest.

## Why

A bundle can restore a repository without Gitea or GitHub. It is portable,
verifiable with standard Git, and does not require stopping a forge.

A bundle contains Git history only. Issues, PRs, labels, users, attachments,
packages, and forge settings need a separate metadata export. The weekly full
Gitea dump remains the cold fallback until that export is verified.

## Layout

```text
/srv/backup/git-bundles/
  <owner>/
    <repo>/
      snapshots/
        YYYYMMDDTHHMMSSZ.bundle
      tags/
        <tag>-<commit7>.bundle
      manifest.json
      SHA256SUMS
  index.json
```

- Snapshots keep the latest `N` per repository.
- Tag bundles are kept forever.
- Private bundles are GPG-encrypted per file.
- `manifest.json` records size, SHA256, refs, HEAD, and creation time.
- `index.json` records every repository’s latest snapshot and totals.

## Create

```bash
# The scripts live in package-sh.
BIN=~/repos/gardusi-gustavo/package-sh/infra/scripts/backup

# One repository from a local bare clone
"$BIN/bundle-backup.sh" gardusi-gustavo/package-json \
  --source /srv/gitea/data/git/repositories/gardusi-gustavo/package-json.git

# One repository from GitHub
"$BIN/bundle-backup.sh" gardusi-gustavo/package-json

# Encrypted private repository
"$BIN/bundle-backup.sh" gardusi-gustavo/private \
  --source /srv/gitea/data/git/repositories/human/private.git \
  --encrypt --passphrase-file /srv/backup/secrets/backup.pass
```

The default is `--branches --tags`; tag bundles use the tag ref only. Files are
written to a temporary path, verified, then atomically renamed.

## Topological order

`infra/config/bundle-order.json` defines the order:

```text
profile → contracts → tooling → languages → data → workflows → dashboards → games → private
```

Run all, or a test subset:

```bash
BIN=~/repos/gardusi-gustavo/package-sh/infra/scripts/backup
ORDER=~/repos/gardusi-gustavo/workflow-devops/infra/config/bundle-order.json
"$BIN/bundle-all.sh" --order "$ORDER"
"$BIN/bundle-all.sh" --order "$ORDER" --dry-run --only gardusi-gustavo/gardusi-gustavo
```

## Verify

```bash
~/repos/gardusi-gustavo/package-sh/infra/scripts/backup/bundle-verify.sh /srv/backup/git-bundles
```

Checks every `SHA256SUMS`, then runs `git bundle verify` for plain bundles. If a
passphrase file is available, encrypted bundles are decrypted to a temporary
file and verified.

## Restore drill

```bash
~/repos/gardusi-gustavo/package-sh/infra/scripts/backup/bundle-restore-test.sh gardusi-gustavo/package-json \
  --root /srv/backup/git-bundles \
  --out /tmp/restore-test \
  --status-file /srv/backup/status/bundle-restore-latest.json
```

The drill verifies a snapshot and a tag bundle, clones each into a temporary
bare repository, runs `git fsck --full`, and compares restored refs with the
bundle heads.

## Retention

- Snapshots: keep latest `N`, default 5.
- Tags: keep all.
- Never prune the newest snapshot.
- Prune after the manifest update; keep a failed bundle for inspection.

## Mirrors

Pass `--mirror DIR` to copy the repository bundle tree to a microSD or USB
destination. The copy is checksum-verified after `rsync`.

## Limitations

- No issues, PRs, labels, users, attachments, packages, or forge settings.
- No uncommitted or untracked files.
- Private bundles must be encrypted and never mirrored to a public target.

## Script location

The generic bundle primitives live in `package-sh` under
`infra/scripts/backup/`. `workflow-devops` owns the order file and backup policy.
Run `package-sh/infra/scripts/backup/bundle-all.sh --order infra/config/bundle-order.json`.
