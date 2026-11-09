# 🎯 Next work

**What this is:** the deterministic handoff from a work queue to one branch and
one pull request. AI drafts and implements; scripts decide what is next.

## Two queues

- **Agent work** lives in `docs/issues/` as append-only task files. Pick the
  highest `rank`. The task file is the work item; the pull request deletes it
  when the work completes.
- **Owner work** stays in native Gitea issues with ranked titles.
  `next-issue.sh` and `next-work.sh` operate on this queue only.

Both queues use `3.x` bug, `2.x` documentation or chore, `1.x` feature or
refactor. Higher fraction wins; reverse sort is the order.

## Why

Gitea cannot sort issues by title. The rank is the queue: `3.x` bug, `2.x`
documentation, `1.x` feature. Higher fraction wins; reverse sort is the order.
Selection is reproducible and never calls a model.

## Commands

```bash
next-issue.sh --repo OWNER/REPO           # top issue
next-issue.sh --repo OWNER/REPO --list    # full queue
next-issue.sh --repo OWNER/REPO --check   # validate ranks
next-issue.sh --repo OWNER/REPO --json    # machine-readable

next-work.sh --repo OWNER/REPO --dry-run  # show issue and branch
next-work.sh --repo OWNER/REPO --start    # branch + context file
next-work.sh --repo OWNER/REPO --ship     # CI, push, one PR
```

## Selector rules

1. Fetch open issues (limit 50).
2. Keep titles shaped `<type>.<priority> - <title>`.
3. Reject a type outside `1`, `2`, `3`.
4. Reject trailing zeros (`3.10` must be `3.1`) and more than 6 decimals.
5. Reject duplicate ranks.
6. Require `3.x -> bug`, `2.x -> documentation`, `1.x -> enhancement`.
7. Skip issues with an open dependency.
8. Sort reverse; print the first unblocked issue.

Errors stop selection. Unranked issues are ignored.

## PR creator workflow

```text
next-work --dry-run  -> issue, rank, branch, lane state
next-work --start    -> verify lane, branch from origin/main, write context
AI                   -> implement the issue
next-work --ship     -> verify lane, run CI, push, open one PR
human              -> review, approve, merge
```

- `--start` and `--ship` stop while a PR is open.
- `--ship` refuses a dirty tree or a branch other than the selected one.
- Context lives outside git:
  `${NEXT_WORK_CONTEXT_DIR:-$HOME/work/<owner>-<repo>}/issue-<n>.md`.
- The PR body contains `Closes #N` or `Part of #N`; at least one open issue is required.

## Boundaries

AI may draft issue comments, propose ranks, write code, tests, and PR text. AI
may not create issues, choose the issue, sort or break ties, judge the diff
budget, approve, or merge.

## Limits

Open issues 50/repo; comments 50/issue; agent comments 20/day/repo; PR diff 12
files / 500 lines / 250 per file / 1 binary / 12 commits; one open PR per repo;
soft cap 10 PRs per issue.

## Related

- Issue workflow: `templates/md/agents/blocks/issue-workflow.md`
- Local tasks: `docs/issues/README.md`
- Task validator: `templates/sh/infra/scripts/ci/validate-local-issues.sh`
- Review lane: `agent/pr-limit.sh`
- PR budget: `agent/pr-size.sh`
