# GitHub App runbook

## Manifest

`infra/config/github/app-manifest.json` defines the app:

- `contents: write` on `database` and the dashboards
- `pull_requests: write` to open and update one data PR per domain
- `issues: write` for cap notifications
- `metadata: read`
- `pages: write` for dashboard deployment
- no administration, secrets, or merge permission

## Create and install

1. Open the GitHub App manifest flow for `gardusi-gustavo`.
2. Install the app on `database` and the four `dashboard-*` repositories.
3. Store `APP_ID` and `APP_PRIVATE_KEY` as environment secrets on each
   `workflow-*` repository under the `ingest` environment.
4. Store the same secrets on `database` for the post-merge dispatcher.
5. Run one ingestion with `workflow_dispatch`.

## Guardrails

- The app never approves or merges.
- The app token is short-lived and scoped to the named repositories.
- Human approval is still required by branch protection.
- If the app is unavailable, ingestion fails closed.
