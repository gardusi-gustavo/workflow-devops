# 🧑‍💻 Code

**What this is:** how the code and repositories are organized across the ecosystem — issues, cleanup, improvement, and the repo shape.

## 🗂️ Files

<!-- begin table -->
| Path | Covers |
| --- | --- |
| [repository/actions.md](repository/actions.md) | Runner capacity, timeouts, concurrency, tag protection |
| [repository/exposure.md](repository/exposure.md) | Localhost-only exposure, visibility rules, and public export boundary |
| [repository/agent-env.md](repository/agent-env.md) | Agent account, rootless Docker, runner, and capability checks |
| [repository/agent-throughput.md](repository/agent-throughput.md) | Owner/author model, guardrails, and throughput improvements |
| [repository/backup.md](repository/backup.md) | Append-only encrypted Gitea dump backup and restore |
| [repository/bundles.md](repository/bundles.md) | Per-repository Git bundles, tag bundles, manifests, and restore drills |
| [repository/disaster-recovery-test.md](repository/disaster-recovery-test.md) | Quarterly restore test checklist and record |
| [repository/improvement.md](repository/improvement.md) | Improving a repo — audits and feedback loops |
| [repository/next-work.md](repository/next-work.md) | Deterministic next-issue selection and PR handoff |
| [repository/policy.md](repository/policy.md) | Canonical repository rules, policy apply, and org pruning |
| [repository/lifecycle.md](repository/lifecycle.md) | Repository cap, creation, rename, archive, and deletion rules |
| [runbooks/archive-migration.md](runbooks/archive-migration.md) | Archived repository migration manifest and verifier |
| [repository/packages.md](repository/packages.md) | Package identity, registry names, and 0.1.0 scope |
| [repository/self-contained.md](repository/self-contained.md) | Repository self-containment checklist |
| [public-data.md](public-data.md) | Public data and asset policy |
| [observability/README.md](observability/README.md) | Metrics, on-call, runbooks, and observability configuration |
| [repository/dashboards.md](repository/dashboards.md) | Async data and observability dashboards |
<!-- end table -->

## 🗂️ Issues

Active work lives in [Gitea issues](http://gitea.localhost:3001/gardusi-gustavo/workflow-devops/issues).
Use the labels and issue workflow in
[`AGENTS.md`](http://gitea.localhost:3001/gardusi-gustavo/workflow-devops/src/branch/main/AGENTS.md).

- [GitHub App](runbooks/github-app.md)
- [Gitea retirement](runbooks/gitea-retirement.md)
