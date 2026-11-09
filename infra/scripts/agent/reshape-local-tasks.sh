#!/usr/bin/env bash
# Convert legacy docs/issues records to the append-only task schema.
#
# Legacy records carried id, type, status, source, author, created, platform,
# and tag metadata. The task schema keeps rank, title, context, limits, spec,
# and optional attempts. This script drops the rest and normalizes ranks.
set -euo pipefail

ROOT="$PWD"
MODE="dry-run"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:?}"; shift 2 ;;
    --dry-run) MODE="dry-run"; shift ;;
    --apply) MODE="apply"; shift ;;
    -h|--help)
      echo "usage: reshape-local-tasks.sh [--root PATH] [--dry-run|--apply]"
      exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -d "$ROOT/docs/issues" ]] || { echo "error: docs/issues not found in $ROOT" >&2; exit 2; }

python3 - "$ROOT" "$MODE" <<'PY'
import json, re, sys
from pathlib import Path

root, mode = Path(sys.argv[1]), sys.argv[2]
directory = root / "docs" / "issues"
RANK_RE = re.compile(r"^([123])\.([0-9]{1,6})$")
NAME_RE = re.compile(r"^([123])\.([0-9]{1,6})-.*\.json$")
TITLE_RE = re.compile(r"^[123]\.[0-9]{1,6}\s*-\s*")
SLUG_RE = re.compile(r"[^a-z0-9]+")


def clean_title(value):
    return TITLE_RE.sub("", str(value or "")).strip() or "Migrated task"


def lines_of(record):
    body = (record.get("legacy") or {}).get("body") or ""
    return [line.strip() for line in body.splitlines()]


def first_body_line(record):
    for line in lines_of(record):
        if line and not line.startswith("#"):
            return line
    return ""


def criteria_from_body(record):
    found = []
    for line in lines_of(record):
        match = re.match(r"^-\s*\[\s*\]\s*(.+)$", line)
        if match:
            found.append(match.group(1).strip())
    return found


def positive_int(value, default):
    if isinstance(value, (int, float)) and value >= 1 and float(value).is_integer():
        return int(value)
    return default


def slugify(title):
    slug = SLUG_RE.sub("-", title.lower()).strip("-")[:60].strip("-")
    return slug or "task"


def normalize(rank, seen):
    match = RANK_RE.match(rank or "")
    if not match:
        return None
    major, frac = match.group(1), match.group(2).rstrip("0") or "1"
    candidate = f"{major}.{frac}"
    while candidate in seen:
        frac += "1"
        candidate = f"{major}.{frac}"
    seen.add(candidate)
    return candidate


def convert(record, rank):
    title = clean_title(record.get("title") or (record.get("spec") or {}).get("summary"))
    spec = record.get("spec") or {}
    summary = str(spec.get("summary") or "")
    if not summary or summary.startswith("#"):
        summary = title
    context = record.get("context") or ""
    if not context or str(context).startswith("#"):
        context = first_body_line(record) or summary
    outcome = spec.get("expected_outcome") or ""
    if not outcome or outcome.startswith("## ") or "Migrated from Gitea issue" in outcome:
        outcome = "Confirm the migrated scope and acceptance criteria."
    criteria = [c for c in (spec.get("acceptance_criteria") or []) if isinstance(c, str) and c.strip()]
    placeholders = {
        "Review the legacy body and confirm the acceptance criteria.",
        "Confirm the migrated scope and acceptance criteria.",
    }
    if not criteria or set(criteria) <= placeholders:
        criteria = criteria_from_body(record) or criteria or ["Confirm the migrated scope and acceptance criteria."]
    attempts = []
    for attempt in record.get("attempts") or []:
        if not isinstance(attempt, dict):
            continue
        item = {"summary": str(attempt.get("summary") or "Attempt recorded during migration.")}
        if isinstance(attempt.get("next_step"), str) and attempt["next_step"].strip():
            item["next_step"] = attempt["next_step"]
        attempts.append(item)
    limits = record.get("limits") or {}
    return {
        "rank": rank,
        "title": title,
        "context": str(context),
        "limits": {
            "max_commits": positive_int(limits.get("max_commits"), 5),
            "max_file_changes": positive_int(limits.get("max_file_changes"), 4),
        },
        "spec": {"summary": summary, "expected_outcome": str(outcome), "acceptance_criteria": criteria},
        "attempts": attempts,
    }


files = sorted(p for p in directory.glob("*.json") if p.name not in {"schema.json", "template.json"})
seen, changed = set(), 0
for path in files:
    try:
        record = json.loads(path.read_text())
    except json.JSONDecodeError:
        print(f"skip {path.name}: invalid JSON", file=sys.stderr)
        continue
    rank = record.get("rank") or ""
    if not RANK_RE.match(str(rank)):
        match = NAME_RE.match(path.name)
        rank = f"{match.group(1)}.{match.group(2)}" if match else ""
    rank = normalize(str(rank), seen)
    if not rank:
        print(f"skip {path.name}: no valid rank", file=sys.stderr)
        continue
    task = convert(record, rank)
    target = directory / f"{rank}-{slugify(task['title'])}.json"
    if target == path and json.loads(path.read_text()) == task:
        continue
    changed += 1
    print(f"{path.name} -> {target.name}")
    if mode == "apply":
        target.write_text(json.dumps(task, indent=2) + "\n")
        if target != path:
            path.unlink()
print(f"reshape {mode} complete ({changed} files)")
PY
