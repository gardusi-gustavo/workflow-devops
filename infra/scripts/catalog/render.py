#!/usr/bin/env python3
"""Render per-domain media READMEs from catalog JSONL."""
from __future__ import annotations

import argparse
import json
import re
import shutil
from collections import defaultdict
from pathlib import Path

MANUAL_RE = re.compile(r"<!-- manual:begin -->(.*?)<!-- manual:end -->", re.S)
CATALOG_RE = re.compile(r"<!-- catalog:begin -->.*?<!-- catalog:end -->", re.S)


def human(num: int) -> str:
    value = float(num)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if value < 1024 or unit == "TB":
            return f"{value:.0f} {unit}" if unit == "B" else f"{value:.1f} {unit}"
        value /= 1024
    return f"{num} B"


def duration(seconds: float) -> str:
    if not seconds:
        return "—"
    total = int(round(seconds))
    hours, rest = divmod(total, 3600)
    minutes, secs = divmod(rest, 60)
    return f"{hours}:{minutes:02d}:{secs:02d}" if hours else f"{minutes}:{secs:02d}"


def bitrate(value: int) -> str:
    if not value:
        return "—"
    return f"{value / 1_000_000:.2f} Mbps" if value >= 1_000_000 else f"{value / 1000:.0f} kbps"


def video_desc(record: dict) -> str:
    videos = record.get("video") or []
    if not videos:
        return "—"
    v = videos[0]
    size = f"{v.get('width')}x{v.get('height')}" if v.get("width") and v.get("height") else ""
    hdr = " HDR" if v.get("hdr") else ""
    return " ".join(part for part in (v.get("codec"), size + hdr) if part)


def audio_langs(record: dict) -> str:
    langs = record.get("audio_languages") or []
    return "+".join(langs) if langs else "—"


def sub_langs(record: dict) -> str:
    langs = record.get("subtitle_languages") or []
    return "+".join(langs) if langs else "—"


def is_compress(record: dict) -> bool:
    return "compress" in (record.get("pending") or [])


def pending_text(records: list[dict]) -> str:
    counts = defaultdict(int)
    for record in records:
        for item in record.get("pending") or []:
            counts[item] += 1
        if record.get("probe_error"):
            counts["unreadable"] += 1
    labels = {
        "compress": "exceed the bitrate target",
        "no-english": "have no English audio or subtitles",
        "und-language": "have und language metadata",
        "extra-audio": "have extra audio tracks",
        "extra-subtitles": "have extra subtitle tracks",
        "multiple-video": "have multiple video streams",
        "unreadable": "could not be probed",
    }
    lines = []
    for key, label in labels.items():
        if counts.get(key):
            lines.append(f"- [ ] {counts[key]} {label}")
    return "\n".join(lines) if lines else "- [ ] None"


def manual_block(path: Path) -> str:
    if path.exists():
        match = MANUAL_RE.search(path.read_text())
        if match:
            return f"<!-- manual:begin -->{match.group(1)}<!-- manual:end -->"
    return "<!-- manual:begin -->\n<!-- manual:end -->"


def compression_table(records: list[dict]) -> str:
    rows = sorted(
        (record for record in records if is_compress(record)),
        key=lambda record: record.get("overall_bitrate") or 0,
        reverse=True,
    )[:10]
    if not rows:
        return "_None._"
    table = [
        "| File | Size | Bitrate | Target | Excess |",
        "| --- | ---: | ---: | ---: | ---: |",
    ]
    for record in rows:
        target = 1_000_000 if record.get("kind") == "video" else 192_000
        bit = record.get("overall_bitrate") or 0
        table.append(
            f"| `{Path(record['path']).name}` | {human(record['size'])} | "
            f"{bitrate(bit)} | {bitrate(target)} | {bitrate(max(0, bit - target))} |"
        )
    return "\n".join(table)


def catalog_section(records: list[dict], domain: str) -> str:
    groups: dict[str, list[dict]] = defaultdict(list)
    for record in records:
        rel = record["path"]
        prefix = f"{record['_base_path']}/{domain}/"
        sub = rel[len(prefix):] if rel.startswith(prefix) else rel
        parts = sub.split("/")
        group = parts[0] if len(parts) > 1 else "Singles"
        groups[group].append(record)

    ordered = sorted(group for group in groups if group != "Singles")
    if "Singles" in groups:
        ordered.append("Singles")

    blocks = []
    for group in ordered:
        blocks.append(f"### {group}")
        if records[0].get("kind") == "book":
            blocks.append("| File | Size | Pages | Title | Author | Status |")
            blocks.append("| --- | ---: | ---: | --- | --- | --- |")
            for record in sorted(groups[group], key=lambda item: item["path"]):
                pdf = record.get("pdf") or {}
                blocks.append(
                    f"| `{Path(record['path']).name}` | {human(record['size'])} | "
                    f"{pdf.get('pages', '—')} | {pdf.get('title', '—')} | "
                    f"{pdf.get('author', '—')} | {record.get('status', '—')} |"
                )
        else:
            blocks.append("| File | Size | Duration | Bitrate | Video | Audio | Subs | Status |")
            blocks.append("| --- | ---: | ---: | ---: | --- | --- | --- | --- |")
            for record in sorted(groups[group], key=lambda item: item["path"]):
                blocks.append(
                    f"| `{Path(record['path']).name}` | {human(record['size'])} | "
                    f"{duration(record.get('duration') or 0)} | "
                    f"{bitrate(record.get('overall_bitrate') or 0)} | "
                    f"{video_desc(record)} | {audio_langs(record)} | "
                    f"{sub_langs(record)} | {record.get('status', '—')} |"
                )
        blocks.append("")
    return "\n".join(blocks)


def top_summary(domain_rows: list[tuple[str, int, int, int, int, int]]) -> str:
    lines = [
        "<!-- catalog:begin -->",
        "## Catalog summary",
        "",
        "| Domain | Files | Size | Pending | Max bitrate |",
        "| --- | ---: | ---: | ---: | ---: |",
    ]
    for domain, files, size, pending, max_bitrate, _ in domain_rows:
        lines.append(
            f"| [{domain}/]({domain}/README.md) | {files} | {human(size)} | "
            f"{pending} | {bitrate(max_bitrate)} |"
        )
    lines.extend(["", "<!-- catalog:end -->"])
    return "\n".join(lines)


def insert_summary(path: Path, block: str) -> None:
    if path.exists():
        text = path.read_text()
        if CATALOG_RE.search(text):
            text = CATALOG_RE.sub(block, text, count=1)
        else:
            lines = text.splitlines()
            index = 0
            for i, line in enumerate(lines):
                if line.startswith("# "):
                    index = i + 1
                    break
            lines[index:index] = ["", block]
            text = "\n".join(lines)
    else:
        text = block
    path.write_text(text.rstrip() + "\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--catalog", required=True, type=Path)
    parser.add_argument("--mirror", type=Path)
    args = parser.parse_args()

    root = args.root.resolve()
    catalog = args.catalog.resolve()
    records = [
        json.loads(line)
        for line in (catalog / "files.jsonl").read_text().splitlines()
        if line.strip()
    ]
    run = json.loads((catalog / "run.json").read_text())
    roots = run.get("roots", [])

    for record in records:
        for base in roots:
            if record["path"].startswith(base + "/"):
                record["_base_path"] = base
                break

    by_domain: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for record in records:
        base = record.get("_base_path")
        if not base:
            continue
        rest = record["path"][len(base) + 1:]
        domain = rest.split("/", 1)[0]
        if "/" not in rest:
            continue
        by_domain[(base, domain)].append(record)

    for base in roots:
        rows = []
        for (record_base, domain), items in sorted(by_domain.items()):
            if record_base != base:
                continue
            total = sum(item["size"] for item in items)
            pending = sum(1 for item in items if item.get("pending") or item.get("probe_error"))
            max_bitrate = max((item.get("overall_bitrate") or 0) for item in items)
            rows.append((domain, len(items), total, pending, max_bitrate, 0))
            path = root / base / domain / "README.md"
            text = f"""# {domain}

Rules: [../README.md](../README.md)

{manual_block(path)}

## Pending actions

{pending_text(items)}

## To compress

{compression_table(items)}

## Catalog

{catalog_section(items, domain)}
"""
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text.rstrip() + "\n")
            if args.mirror:
                target = args.mirror / base / domain / "README.md"
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(text.rstrip() + "\n")

        if rows:
            top = root / base / "README.md"
            insert_summary(top, top_summary(rows))
            if args.mirror:
                target = args.mirror / base / "README.md"
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(top.read_text().rstrip() + "\n")

    print(f"rendered {len(by_domain)} domains")


if __name__ == "__main__":
    main()
