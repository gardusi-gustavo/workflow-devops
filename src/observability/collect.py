#!/usr/bin/env python3
"""Collect Gitea repository health into append-only JSONL rows.

The collector talks to the Gitea API directly. It does not require Prometheus,
Grafana, or an exporter process.
"""

from __future__ import annotations

import argparse
import json
import os
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path

GITEA_URL = os.environ.get("GITEA_URL", "http://gitea:3000").rstrip("/")
GITEA_TOKEN = os.environ.get("GITEA_TOKEN", "")
PRIVATE_PREFIX = os.environ.get("PRIVATE_PREFIX", "private/")
PRIVATE_LABEL = os.environ.get("PRIVATE_LABEL", "private")
DEFAULT_OUTPUT = Path("src/data/observability/metrics")


def get(path: str, params: dict | None = None):
    url = f"{GITEA_URL}/api/v1{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(
        url,
        headers={
            "Authorization": f"token {GITEA_TOKEN}",
            "Accept": "application/json",
            "User-Agent": "gitea-static-observability",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def epoch(value: str | None) -> int:
    if not value:
        return 0
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return 0
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return int(parsed.timestamp())


def repos() -> list[dict]:
    items: list[dict] = []
    for page in range(1, 20):
        payload = get("/repos/search", {"limit": 50, "page": page, "mode": "source"})
        batch = payload.get("data", [])
        items.extend(batch)
        if len(batch) < 50:
            break
    return items


def rows_for(day: str, repositories: list[dict]) -> list[dict]:
    grouped: dict[str, dict] = {}
    for repo in repositories:
        full_name = repo.get("full_name") or ""
        if not full_name:
            continue
        label = PRIVATE_LABEL if full_name.startswith(PRIVATE_PREFIX) else full_name
        state = grouped.setdefault(
            label,
            {
                "open_issues": 0,
                "open_prs": 0,
                "size_bytes": 0,
                "updated": 0,
                "archived": 0,
                "repositories": 0,
            },
        )
        state["open_issues"] += int(repo.get("open_issues_count") or 0)
        state["open_prs"] += int(repo.get("open_pr_counter") or 0)
        state["size_bytes"] += int(repo.get("size") or 0) * 1024
        state["updated"] = max(state["updated"], epoch(repo.get("updated_at")))
        state["archived"] += 1 if repo.get("archived") else 0
        state["repositories"] += 1

    rows: list[dict] = []
    for label, state in sorted(grouped.items()):
        for metric, value in (
            ("repo_open_issues", state["open_issues"]),
            ("repo_open_prs", state["open_prs"]),
            ("repo_size_bytes", state["size_bytes"]),
            ("repo_updated_timestamp", state["updated"]),
            ("repo_archived", state["archived"]),
            ("repo_count", state["repositories"]),
        ):
            rows.append(
                {
                    "v": 1,
                    "day": day,
                    "scope": f"repo:{label}",
                    "metric": metric,
                    "value": value,
                }
            )

    total_repos = len(repositories)
    public_repos = sum(1 for r in repositories if not (r.get("full_name") or "").startswith(PRIVATE_PREFIX))
    private_repos = total_repos - public_repos
    archived = sum(1 for r in repositories if r.get("archived"))
    for metric, value in (
        ("gitea_repositories", total_repos),
        ("gitea_public_repositories", public_repos),
        ("gitea_private_repositories", private_repos),
        ("gitea_archived_repositories", archived),
    ):
        rows.append({"v": 1, "day": day, "scope": "service:gitea", "metric": metric, "value": value})
    return rows


def write_rows(output: Path, rows: list[dict]) -> int:
    buckets: dict[Path, list[dict]] = {}
    for row in rows:
        year, month = row["day"].split("-")[:2]
        buckets.setdefault(output / year / f"{month}.jsonl", []).append(row)
    written = 0
    for path, batch in buckets.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        days = {row["day"] for row in batch}
        kept: list[str] = []
        if path.exists():
            for line in path.read_text(encoding="utf-8").splitlines():
                if not line.strip():
                    continue
                try:
                    old = json.loads(line)
                except json.JSONDecodeError:
                    kept.append(line)
                    continue
                if old.get("day") not in days:
                    kept.append(line)
        lines = kept + [json.dumps(row, separators=(",", ":")) for row in batch]
        path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
        written += len(batch)
    return written


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--date", default=date.today().isoformat())
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    if not GITEA_TOKEN:
        raise SystemExit("GITEA_TOKEN is required")
    data = repos()
    count = write_rows(args.output, rows_for(args.date, data))
    print(f"collected {len(data)} repositories, wrote {count} rows")


if __name__ == "__main__":
    main()
