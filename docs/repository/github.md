# GitHub

## Namespace

`gardusi-gustavo` is a GitHub **user**, not an organization. Every repository is
`gardusi-gustavo/<repo>`. There are no organization rulesets or organization
secrets. Rulesets are applied per repository.

## Repositories

| Repository | Role |
| --- | --- |
| `database` | public raw data lake |
| `workflow-devops` | reusable workflows, policy, backups, bootstrap |
| `package-python` | PyPI `gardusi-gustavo-python` |
| `package-cpp` | C++ CMake package |
| `package-sh` | pinned-tag shell package and bundle primitives |
| `package-docker` | Dockerfiles, CI images, runtime installers |
| `workflow-*` | ingestion orchestrators |
| `dashboard-*` | static GitHub Pages sites |
| `game-*` | games |
| `private` | private vault; never mirrored |

## Token scope

Pushing `.github/workflows/` requires the `workflow` scope:

```bash
gh auth refresh -h github.com -s workflow
```

## Rulesets

Source of truth: `infra/config/github/rulesets/`.
Apply with `infra/scripts/github/bootstrap.sh --apply`.

## Profile

The profile README is `gardusi-gustavo/gardusi-gustavo`.
