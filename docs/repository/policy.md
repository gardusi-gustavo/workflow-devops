# 🧭 Repository policy

One canonical policy applies to every repository, regardless of the owning
organization. The machine-readable rule lives in
`infra/config/policy.json`.

## Merge policy

- Squash is the only merge method.
- Delete the pull request branch after merge by default.
- `human` is the only approver and the only merger.
- A pull request needs one approval and the `ci / ci (pull_request)` status.
- The branch must be up to date, stale approvals are dismissed, and rejected
  reviews block the merge.
- Direct pushes, force pushes, and admin merge overrides are disabled.

## CI policy

- Repository CI runs only for pull requests targeting `main`.
- There is no push-to-main run after merge.

## Images

- Shared images are published to Docker Hub as
  `docker.io/gardusi-gustavo/<name>:<version>`.
- Gitea packages are not used for images.

## Organizations

- Keep every organization that has at least one repository.
- Keep every organization that owns packages until the package is migrated.
- Delete an organization only when it has zero repositories, zero packages,
  zero hooks, and zero organization runners.
- Desired display names, descriptions, and visibility live in
  `infra/config/orgs.json`.
- The instance hard cap is 50 standard repositories; archived repositories
  count. `check-inventory.sh` enforces the cap.
- `check-orgs.sh` verifies organization metadata; `check-visibility.sh` verifies
  that only the `private` organization contains private repositories;
  `check-teams.sh` verifies the contributor, reviewer, and owner teams.
- New organizations and repositories default to public. Only `private` may be
  private.

## New repository

Use this checklist before the first pull request.

- [ ] Create the repository under the owning organization.
- [ ] Add `infra/config/repo.json` with the current `template.ref`.
- [ ] Register the repository in `infra/config/repos.json`.
- [ ] Copy the canonical CI files, `check-layout.sh`, and
      `.gitea/pull_request_template.md`.
- [ ] Add `README.md`, `AGENTS.md`, and the `docs/` tree.
- [ ] Create the `reviewers` team with write access if the organization is new.
- [ ] Create the `bug`, `documentation`, `enhancement`, and `security-review`
      labels.
- [ ] Run `repos.sh --apply` to set squash-only, branch protection, and `v*`
      tag protection.
- [ ] Run the template, guardrail, and limit audits.
- [ ] Verify that a `main` push and a `v*` tag push by `bot-event` are denied.
- [ ] Verify that a pull request needs one approval from `reviewers`.

## Apply

```bash
GITEA_URL=http://127.0.0.1:3001 GITEA_TOKEN=... \
  ./infra/scripts/policy/repos.sh
```

`repos.sh` is a dry run by default. Add `--apply` to change repositories.
Add `--prune-orgs` to delete eligible organizations:

```bash
GITEA_URL=http://127.0.0.1:3001 GITEA_TOKEN=... \
  ./infra/scripts/policy/repos.sh --apply --prune-orgs
```

The `policy` workflow is manual. It has no standing token and no daily
schedule. When `POLICY_TOKEN` is not configured, the workflow fails with an
explicit message; a skip is not a successful policy gate. The token is scoped
read-only for organization, repository, user, and issue reads. To apply rules,
run `repos.sh` locally with a temporary admin token and delete the token
afterwards.
