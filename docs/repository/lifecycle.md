# Repository lifecycle

**What this is:** the simple rules for creating, renaming, archiving, and
deleting repositories.

## Cap

- Hard cap: **50 standard repositories**.
- Archived repositories count.
- No soft target and no warning threshold.
- `check-inventory.sh` fails above the cap.
- Gitea's per-owner creation limits are safety nets, not the instance cap:
  `MAX_CREATION_LIMIT`, `USER_MAX_CREATION_LIMIT`, and
  `ORG_MAX_CREATION_LIMIT` are set to 50.

## New repository

Create the repository normally in Gitea. Before the first pull request:

- define the purpose
- add `infra/config/repo.json`
- register it in `infra/config/repos.json`
- add README, AGENTS, docs, CI, and hubs
- choose the correct organization and visibility

Do not build a separate repository-provisioning service.

## Rename or transfer

1. Record the current inventory.
2. Back up.
3. Rename or transfer.
4. Update local remotes, `repos.json`, links, and AGENTS identity blocks.
5. Run inventory, visibility, org, and CI checks.
6. Verify issues, pull requests, and Git transport.
7. Back up again.

## Archive

- Use Gitea's native archive flag.
- Keep the repository in the inventory with `archived: true`.
- Close or transfer unfinished issues first.
- Archived repositories do not need active hubs.

## Delete

Delete only when:

- the content is covered by a verified backup
- at least one successful restore has included it
- the retention date has passed
- no active repository links to it

Deletion is manual. There is no automated deletion service.

## Organization retirement

Remove all repositories first, then delete the organization. Keep a backup and
a restore record before deleting the last repository.
