# Repository self-containment

**What this is:** the checklist for making this repository understandable,
recoverable, and copyable without Gitea.

## Source of truth

- Repository: `gardusi-gustavo/workflow-devops`
- Visibility: public
- Owner: `human`
- Git platform: Gitea
- Local checkout: `~/repos/gardusi-gustavo/workflow-devops`

## Durable data

- [x] `README.md` and `AGENTS.md`
- [x] `docs/README.md` and the docs tree
- [x] `docs/issues/` backlog and active work
- [x] decisions and repository policy
- [x] runbooks and recovery notes
- [x] `VERSION`
- [ ] `CHANGELOG.md`
- [ ] release tags
- [x] `infra/config/repo.json`
- [x] CI and release workflows
- [x] tests
- [x] external service references
- [x] backup and restore notes

## External-only data

- issues and comments: owner-created native issues remain on Gitea
- PR discussions: Gitea
- attachments and media: microSD and external storage
- secrets: local files and repository secret stores
- package registry artifacts: external registries
- external services: Gitea, Docker Hub, microSD, USB

## Migration status

- [x] Agent-created issues migrated to `docs/issues/`
- [ ] Owner-created issues classified
- [ ] Closed history exported to backup
- [x] Wiki content not applicable
- [x] GitHub v1 issue created: #221

## Copy test

A new machine must be able to:

1. Clone the repository.
2. Read the docs and understand its purpose.
3. Find all open work.
4. Run CI.
5. Recover external dependencies from the recorded references.
