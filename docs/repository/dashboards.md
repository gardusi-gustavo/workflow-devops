# 📊 Dashboards

Asynchronous data and observability dashboards.

**What this is:** the former `radar` repository. It collects external public
data, analyzes it, and renders static pages. It also renders historical
repository-health metrics produced by the observability subdomain and published
under `dashboards/devops/src/data/observability/observability/`.

## 🗂️ Structure

| Path | Holds |
|---|---|
| `collectors/` | external data collectors |
| `analysis/` | statistics and aggregation |
| `views/` | markets, lottery, news, repositories |
| `ui/` | static pages and charts |
| `infra/config/` | curated rules and watchlists |
| `src/data/markets/` | market snapshots |
| `src/data/news/` | news snapshots |
| `src/data/observability/` | repository-health snapshots |
| `infra/scripts/` | collect, analyze, pages, CI |
| `tests/` | collector, analysis, schema and page checks |
| `docs/` | architecture, data sources, freshness |

## 📈 Views

- **Markets** — B3 quotes, returns, moving averages, volatility, threshold events
- **Lottery** — Caixa draw statistics, gaps, sums, pairs, cycles
- **News** — Brazil and tech headline volume and keyword trends
- **Repositories** — pipeline failure rate, commits/week, review load, issues,
  tags, sizes, backup coverage, repository health

The repository view is historical. It reads local aggregated snapshots; it does
not query live Prometheus.

## 🗄️ Data sources

- `dashboards/devops/src/data/observability/markets` and `src/data/news` — external data snapshots
- `dashboards/devops/src/data/observability/observability` — repository-health snapshots

`dashboards` is the durable store. Raw Prometheus/Loki data is not copied here.

## 🖥️ Runtime

Static pages only. No backend, no live database connection, no authentication
layer. Page builds run as CI jobs; outputs can be published as static pages or
opened locally.

## ✅ Tests

- collector imports and unit tests
- JSON schema validation
- static page build
- internal link checks
- data freshness checks

## 🔗 Related

- `gardusi-gustavo/workflow-devops/src/observability` — live collection and Grafana
