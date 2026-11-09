# observability

**What this is:** static Gitea and repository health pages.

- [Status page](status.md) — generated snapshot
- [Metrics](metrics.md) — collected metrics and collection rules
- [On-call](oncall/README.md) — escalation and recovery

The pipeline is:

```text
Gitea API -> JSONL rows -> static Markdown page
```

No Prometheus, Grafana, node_exporter, or long-running exporter is required.
