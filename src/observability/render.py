#!/usr/bin/env python3
"""Render the latest Gitea telemetry as a static Markdown page."""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path

DEFAULT_INPUT = Path("src/data/observability/metrics")
DEFAULT_OUTPUT = Path("docs/observability/status.md")

LABELS = {
    "repo_open_issues": "Open issues",
    "repo_open_prs": "Open pull requests",
    "repo_size_bytes": "Size",
    "repo_archived": "Archived",
    "repo_count": "Repositories",
    "repo_updated_timestamp": "Last update",
    "gitea_repositories": "Repositories",
    "gitea_public_repositories": "Public repositories",
    "gitea_private_repositories": "Private repositories",
    "gitea_archived_repositories": "Archived repositories",
}


def load(directory: Path) -> dict[tuple[str, str], tuple[str, float]]:
    latest: dict[tuple[str, str], tuple[str, float]] = {}
    for path in sorted(directory.rglob("*.jsonl")):
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            scope = row.get("scope")
            metric = row.get("metric")
            day = row.get("day")
            if not scope or not metric or not day:
                continue
            value = row.get("value", row.get("avg"))
            if value is None:
                continue
            key = (scope, metric)
            if key not in latest or day >= latest[key][0]:
                latest[key] = (day, float(value))
    return latest


def human(value: float, metric: str) -> str:
    if metric == "repo_size_bytes":
        size = value
        for unit in ("B", "KB", "MB", "GB"):
            if size < 1024 or unit == "GB":
                return f"{size:.1f} {unit}" if unit != "B" else f"{int(size)} B"
            size /= 1024
    if metric == "repo_updated_timestamp":
        from datetime import datetime, timezone
        return datetime.fromtimestamp(value, tz=timezone.utc).strftime("%Y-%m-%d")
    if float(value).is_integer():
        return str(int(value))
    return f"{value:.2f}"


def render(latest: dict[tuple[str, str], tuple[str, float]]) -> str:
    days = sorted({day for day, _ in latest.values()})
    lines = [
        "# Gitea telemetry",
        "",
        "**What this is:** a static snapshot of repository and service health.",
        "",
    ]
    if not days:
        lines += ["No telemetry rows yet. Run `collect.sh` first.", ""]
        return "\n".join(lines)
    lines += [f"Day: `{days[-1]}`", ""]

    service = {metric: value for (scope, metric), (_, value) in latest.items() if scope == "service:gitea"}
    if service:
        lines += ["## Service", "", "| Metric | Value |", "| --- | --- |"]
        for metric in sorted(service):
            lines.append(f"| {LABELS.get(metric, metric)} | {human(service[metric], metric)} |")
        lines.append("")

    repos: dict[str, dict[str, float]] = defaultdict(dict)
    for (scope, metric), (_, value) in latest.items():
        if scope.startswith("repo:"):
            repos[scope.removeprefix("repo:")][metric] = value
    if repos:
        lines += [
            "## Repositories",
            "",
            "| Repository | Open issues | Open PRs | Archived | Size | Last update |",
            "| --- | ---: | ---: | ---: | ---: | --- |",
        ]
        for name in sorted(repos, key=lambda item: (-repos[item].get("repo_open_issues", 0), item)):
            state = repos[name]
            lines.append(
                "| {name} | {issues} | {prs} | {archived} | {size} | {updated} |".format(
                    name=name,
                    issues=human(state.get("repo_open_issues", 0), "repo_open_issues"),
                    prs=human(state.get("repo_open_prs", 0), "repo_open_prs"),
                    archived=human(state.get("repo_archived", 0), "repo_archived"),
                    size=human(state.get("repo_size_bytes", 0), "repo_size_bytes"),
                    updated=human(state.get("repo_updated_timestamp", 0), "repo_updated_timestamp"),
                )
            )
        lines.append("")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    page = render(load(args.input))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(page + "\n", encoding="utf-8")
    print(f"wrote {args.output}")


if __name__ == "__main__":
    main()
