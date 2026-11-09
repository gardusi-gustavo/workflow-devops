# ⚡ Agent throughput

**What this is:** the high-permission, low-deletion-risk authoring model. The
agent gets freedom to create; deletions stay visible and owner-approved.

## Model

- `human` is the owner: issue lifecycle, labels after creation, review,
  approval, merge, tags, repositories, tokens, and system changes.
- `bot-event` is the author: branches, commits, files, issue comments, and pull
  requests linked to at least one open issue.
- Append is cheap. Delete is a proposal inside a pull request.
- Nothing reaches `main` without `human`'s merge.
- One open PR per repository is the review lane. It is a lock, not a quota.
- A PR must fit the size budget; split the rest into follow-up issues.

## Happy path

1. Check the review lane: `pr-limit.sh status --repo OWNER/REPO`.
2. Pick the next issue: `next-issue.sh --repo OWNER/REPO`.
3. Ask `human` to create or refine the issue; add details as comments.
4. Branch from `main`: `next-work.sh --repo OWNER/REPO --start`.
5. Commit and push.
6. Open the pull request with `Closes #N`:
   `next-work.sh --repo OWNER/REPO --ship`.
7. Comment status.
8. `human` reviews, merges, and closes.

The selector is deterministic; AI does not choose the issue. See `docs/repository/next-work.md`.

If the lane is occupied, comment on the existing issue or PR, or wait. Do not
open a second PR or push a new branch in that repository.

## Deletion path

- File deletion is allowed in a branch, but add a `## Deletions` section to the
  pull request body.
- Issue, comment, label, branch, tag, repository, token, or system deletion is
  `human` only.
- Never bypass `gitea-api` with raw `curl`.
- Never force-push to "clean up" a branch.

## Guardrails

- `gitea-api` append-only allowlist for `bot-event`.
- One open PR per repository; `gitea-api` and `pre-push` enforce it.
- A PR size budget; `gitea-api`, `pre-push`, and CI enforce it.
- `pre-push` blocks force-push, remote branch deletion, tag changes, `main`,
  a new branch while a PR is open, and an over-budget diff.
- Audit scans issue timelines for destructive `bot-event` actions.
- Branch and tag protection keep merge and release with `human`.
- `user` (Gitea `human`) has sudo but no OpenCode; `gitea-automation` (Gitea `bot-event`) has OpenCode but no sudo.

These are guardrails, not a security boundary: the token owner can bypass the
wrapper. The audit is the detective layer.

## Throughput improvements

| Improvement | Impact | Why |
| --- | --- | --- |
| High-level `gitea-api` subcommands | high | no hand-built JSON or paths |
| PR helper with `Closes #N` | high | one command from branch to PR |
| Issue and PR templates everywhere | high | fewer review round-trips |
| `## Deletions` validator | medium | makes deletions explicit |
| Worktrees for parallel tasks | medium | fewer branch conflicts |
| Batch issue creation from JSON | owner-only | `human` controls the issue backlog |
| Second runner | low until CI queues | one runner is the current cap |
| Project board | low for agents | board moves are owner-only |

## High-value commands to add

```bash
gitea-api issue comment --repo OWNER/REPO --number 123 --body-file comment.md
gitea-api pr new --repo OWNER/REPO --title "..." --body-file pr.md
gitea-api status --repo OWNER/REPO
gitea-api audit --repo OWNER/REPO --days 7
pr-limit status --repo OWNER/REPO
pr-size check --repo OWNER/REPO --branch BRANCH --head HEAD --repo-root .
```

The PR helper should infer the issue number from `feat/123-slug`, push the
branch, and add `Closes #123` when the body does not already contain it. The
body must reference at least one open issue.

## Metrics

- time from idea to issue
- time from issue to pull request
- pull request cycle time
- open PRs per repository (target 0 or 1)
- PR files and lines (target within budget)
- audit violations
- rework rate

## Anti-patterns

- raw `curl` around the wrapper
- creating, editing, or closing an issue directly
- two open PRs in one repository
- a new branch while a PR is open
- appending new scope to an over-budget PR
- fixing conflicts in a second PR
- force-push to "clean up" a branch
- deleting a branch or tag after merge
- merging without `human`
