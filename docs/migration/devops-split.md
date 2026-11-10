# devops split

**What this is:** the retirement record for the former `devops` repository.

`devops` was split into three repositories so that portable code, image
content, and maintenance orchestration no longer share one control plane.

| Destination | Holds |
| --- | --- |
| `package-sh` | portable shell scripts, CI validators, and bundle primitives |
| `package-docker` | Dockerfiles, CI images, runtime installers, and image build helpers |
| `workflow-event` | reusable workflows, policy, inventory, backup orchestration, agent control, and runbooks |

## Caller migration

Every reusable workflow caller moved from:

```yaml
uses: gardusi-gustavo/devops/.github/workflows/<workflow>.yml@v0.1.0
```

to:

```yaml
uses: gardusi-gustavo/workflow-event/.github/workflows/<workflow>.yml@v0.1.0
```

## Tags

| Repository | Tag |
| --- | --- |
| `package-sh` | `v0.7.3` |
| `package-docker` | `v0.1.0` |
| `workflow-event` | `v0.1.0` |

## Metadata

Native Gitea issues, PRs, comments, labels, and milestones are exported to the
backup host before retirement. Git history is preserved in the per-repository
bundle backup. The archive manifest records the split as `deleted`.

## Rule

Do not recreate `devops`. Portable code goes to `package-sh`, image content to
`package-docker`, and maintenance orchestration to `workflow-event`.
