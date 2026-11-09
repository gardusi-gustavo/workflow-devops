#!/usr/bin/env bash
# Migrate docs/issues records into Gitea issues. Dry-run by default.
set -euo pipefail

exec python3 - "$@" <<'PY'
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

BASE = os.environ.get("GITEA_URL", "http://127.0.0.1:3001").rstrip("/")
TOKEN = os.environ.get("GITEA_TOKEN", "")
ADMIN_TOKEN = os.environ.get("GITEA_ADMIN_TOKEN", "") or TOKEN
REPOS_ROOT = Path(os.environ.get("REPOS_ROOT", "/home/user/repos"))
MARKER = "<!-- docs-issue:"

COLORS = {
    "type:initiative": "#1d76db",
    "type:investigation": "#5319e7",
    "type:enhancement": "#0e8a16",
    "type:bug": "#b60205",
    "type:task": "#fbca04",
    "type:question": "#d876e3",
    "status:idea": "#ededed",
    "status:backlog": "#c5def5",
    "status:ready": "#0e8a16",
    "status:in-progress": "#1d76db",
    "status:blocked": "#b60205",
    "status:done": "#6e7781",
    "status:dropped": "#000000",
    "priority:low": "#ededed",
    "priority:normal": "#c5def5",
    "priority:high": "#fbca04",
    "priority:critical": "#b60205",
}
DEFAULT_AREA_COLOR = "#d4c5f9"


def usage():
    print(
        "usage: migrate-docs-issues.sh [--dry-run|--apply] REPO...\n\n"
        "  REPO may be group/name or a checkout path.\n"
        "  GITEA_URL defaults to http://127.0.0.1:3001.\n"
        "  GITEA_TOKEN is required for --apply; GITEA_ADMIN_TOKEN is used for labels.",
        file=sys.stderr,
    )
    raise SystemExit(2)


def api(method, path, data=None, token=None):
    token = token or TOKEN
    if not token:
        raise RuntimeError("GITEA_TOKEN is required for --apply")
    body = None if data is None else json.dumps(data).encode()
    request = urllib.request.Request(
        BASE + "/api/v1" + path,
        data=body,
        method=method,
        headers={
            "Authorization": f"token {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise RuntimeError(f"{method} {path}: HTTP {error.code}: {detail}") from error


def resolve_repo(arg):
    path = Path(arg)
    if not path.is_absolute():
        candidate = REPOS_ROOT / arg
        if candidate.exists():
            path = candidate
    path = path.resolve()
    if not (path / ".git").exists():
        raise RuntimeError(f"not a git checkout: {path}")
    if not (path / "docs" / "issues").is_dir():
        raise RuntimeError(f"missing docs/issues: {path}")
    full_name = f"{path.parent.name}/{path.name}"
    return path, full_name


def parse_issue(path):
    text = path.read_text(errors="replace")
    match = re.search(r"```json issue\n(.*?)\n```", text, re.S)
    if not match:
        raise RuntimeError(f"{path}: missing fenced json issue block")
    meta = json.loads(match.group(1))
    body = text[match.end():].lstrip("\n")
    if not body.strip():
        raise RuntimeError(f"{path}: empty issue body")
    labels = set(meta.get("labels") or [])
    labels.discard("ready")
    labels.discard("not-ready")
    labels.add(f"type:{meta['type']}")
    labels.add(f"priority:{meta['priority']}")
    labels.add(f"status:{meta['status']}")
    for area in meta.get("areas") or []:
        labels.add(f"area:{area}")
    return meta, body, sorted(labels)


def issue_body(path, meta, body):
    rel = path.as_posix().split("/repos/", 1)[-1]
    try:
        commit = subprocess.check_output(
            ["git", "-C", str(path.parents[2]), "rev-parse", "--short", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        commit = "unknown"
    marker = f"{MARKER}{meta['id']} -->"
    metadata = json.dumps(meta, indent=2, ensure_ascii=False)
    return (
        f"{marker}\n"
        f"_Migrated from `{rel}` at `{commit}`._\n\n"
        f"<details>\n<summary>Original docs issue metadata</summary>\n\n"
        f"```json\n{metadata}\n```\n\n</details>\n\n"
        f"{body.rstrip()}\n"
    )


def existing_markers(full_name):
    found = {}
    page = 1
    while True:
        issues = api("GET", f"/repos/{urllib.parse.quote(full_name, safe='/')}/issues?state=all&limit=50&page={page}")
        if not issues:
            break
        for issue in issues:
            body = issue.get("body") or ""
            for marker in re.findall(r"<!-- docs-issue:([0-9a-f-]+) -->", body):
                found[marker] = issue["number"]
        if len(issues) < 50:
            break
        page += 1
    return found


def labels_for(full_name, wanted):
    encoded = urllib.parse.quote(full_name, safe="/")
    existing = {}
    page = 1
    while True:
        data = api("GET", f"/repos/{encoded}/labels?limit=50&page={page}", token=ADMIN_TOKEN)
        if not data:
            break
        for label in data:
            existing[label["name"]] = label["id"]
        if len(data) < 50:
            break
        page += 1
    for name in wanted:
        if name in existing:
            continue
        color = COLORS.get(name, DEFAULT_AREA_COLOR)
        created = api("POST", f"/repos/{encoded}/labels", {"name": name, "color": color}, token=ADMIN_TOKEN)
        existing[name] = created["id"]
        print(f"  label created: {name}")
    return existing


def main():
    mode = "dry-run"
    args = []
    for arg in sys.argv[1:]:
        if arg in ("--dry-run", "--apply"):
            mode = arg[2:]
        elif arg in ("-h", "--help"):
            usage()
        else:
            args.append(arg)
    if not args:
        usage()
    if mode == "apply" and not TOKEN:
        usage()
    if mode == "apply":
        me = api("GET", "/user")
        if me.get("login") != "human":
            raise SystemExit("error: --apply requires the human token; bot-event may not create issues")

    total = 0
    failures = 0
    for arg in args:
        try:
            path, full_name = resolve_repo(arg)
            files = sorted((path / "docs" / "issues").glob("issue-*.md"))
            files += sorted((path / "docs" / "issues").glob("question-*.md"))
            files = [f for f in files if f.name not in ("template.md", "question-template.md")]
            print(f"== {full_name}: {len(files)} records")
            existing = existing_markers(full_name) if mode == "apply" else {}
            encoded = urllib.parse.quote(full_name, safe="/")
            for file in files:
                total += 1
                meta, body, wanted = parse_issue(file)
                if meta["id"] in existing:
                    print(f"  skip {file.name}: already imported")
                    if mode == "apply":
                        labels = labels_for(full_name, wanted)
                        api(
                            "PUT",
                            f"/repos/{encoded}/issues/{existing[meta['id']]}/labels",
                            {"labels": [labels[name] for name in wanted]},
                            token=ADMIN_TOKEN,
                        )
                    continue
                if mode == "dry-run":
                    print(f"  create {file.name}: {meta['title']}")
                    print(f"    labels: {', '.join(wanted)}")
                    continue
                labels = labels_for(full_name, wanted)
                created = api(
                    "POST",
                    f"/repos/{encoded}/issues",
                    {
                        "title": meta["title"],
                        "body": issue_body(file, meta, body),
                        "closed": False,
                    },
                )
                api(
                    "PUT",
                    f"/repos/{encoded}/issues/{created['number']}/labels",
                    {"labels": [labels[name] for name in wanted]},
                    token=ADMIN_TOKEN,
                )
                print(f"  created #{created['number']}: {meta['title']}")
        except Exception as exc:
            failures += 1
            print(f"ERROR {arg}: {exc}", file=sys.stderr)

    print(f"{mode}: {total} records, {failures} failures")
    raise SystemExit(1 if failures else 0)


if __name__ == "__main__":
    main()
PY
