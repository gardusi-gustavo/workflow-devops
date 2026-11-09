#!/usr/bin/env python3
"""Collect media metadata from a mounted card and write JSONL."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path

VIDEO_TARGET = 1_000_000
AUDIO_TARGET = 192_000
SKIP_NAMES = {"README.md", ".nomedia"}
SKIP_DIRS = {".thumbnails", ".Trash", "System Volume Information"}
BOOK_EXTS = {".pdf", ".epub", ".mobi", ".azw3"}


def run_json(cmd: list[str]) -> dict:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.strip() or f"command failed: {cmd[0]}")
    text = proc.stdout.strip()
    return json.loads(text) if text else {}


def human(num: int) -> str:
    value = float(num)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if value < 1024 or unit == "TB":
            return f"{value:.0f} {unit}" if unit == "B" else f"{value:.1f} {unit}"
        value /= 1024
    return f"{num} B"


def kind_for(path: Path, probe: dict) -> str:
    streams = probe.get("streams", [])
    if any(s.get("codec_type") == "video" for s in streams):
        return "video"
    if any(s.get("codec_type") == "audio" for s in streams):
        return "audio"
    if path.suffix.lower() in {".pdf", ".epub", ".mobi", ".azw3"}:
        return "book"
    return "other"


def lang_of(stream: dict) -> str:
    return (stream.get("tags") or {}).get("language", "und") or "und"


def title_of(stream: dict) -> str:
    return (stream.get("tags") or {}).get("title", "") or ""


def track_flag(stream: dict, key: str) -> bool:
    return bool((stream.get("disposition") or {}).get(key, 0))


def media_info(path: Path) -> dict:
    if not shutil_which("mediainfo"):
        return {}
    try:
        raw = run_json(["mediainfo", "--Output=JSON", str(path)])
    except Exception:
        return {}
    tracks = (raw.get("media") or {}).get("track") or []
    out = {"general": {}, "video": [], "audio": [], "text": []}
    for track in tracks:
        typ = track.get("@type", "").lower()
        if typ == "general":
            out["general"] = {
                "format": track.get("Format"),
                "duration": track.get("Duration"),
                "overall_bitrate": track.get("OverallBitRate"),
                "encoded_date": track.get("Encoded_Date"),
                "writing_application": track.get("Writing_Application"),
            }
        elif typ in out:
            out[typ].append({
                "format": track.get("Format"),
                "codec_id": track.get("CodecID"),
                "bitrate": track.get("BitRate"),
                "language": track.get("Language"),
                "title": track.get("Title"),
                "channels": track.get("Channels"),
                "sampling_rate": track.get("SamplingRate"),
                "width": track.get("Width"),
                "height": track.get("Height"),
                "hdr": track.get("HDR_Format"),
                "color_primaries": track.get("colour_primaries"),
                "transfer": track.get("transfer_characteristics"),
            })
    return out


def pdf_info(path: Path) -> dict:
    if path.suffix.lower() != ".pdf" or not shutil_which("pdfinfo"):
        return {}
    try:
        proc = subprocess.run(["pdfinfo", str(path)], capture_output=True, text=True)
    except Exception:
        return {}
    if proc.returncode != 0:
        return {}
    out = {}
    for line in proc.stdout.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key, value = key.strip(), value.strip()
        if key in {"Title", "Author", "Pages", "CreationDate", "Producer", "Creator"}:
            out[key.lower()] = value
    return out


def shutil_which(name: str) -> bool:
    return any((Path(p) / name).is_file() for p in os.environ.get("PATH", "").split(":") if p)


def probe_file(root: Path, path: Path) -> dict:
    rel = str(path.relative_to(root))
    size = path.stat().st_size
    mtime = datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat()
    record = {
        "path": rel,
        "size": size,
        "mtime": mtime,
        "extension": path.suffix.lower(),
        "kind": "other",
        "probe_error": None,
    }
    if path.suffix.lower() in BOOK_EXTS:
        record["kind"] = "book"
        record["pdf"] = pdf_info(path)
        record["pending"] = []
        record["status"] = "green"
        return record
    try:
        probe = run_json([
            "ffprobe", "-v", "error", "-print_format", "json",
            "-show_format", "-show_streams", "-show_chapters", str(path),
        ])
    except Exception as exc:
        record["probe_error"] = str(exc)
        record["pending"] = ["unreadable"]
        record["status"] = "red"
        return record

    record["kind"] = kind_for(path, probe)
    fmt = probe.get("format") or {}
    streams = probe.get("streams") or []
    video = [s for s in streams if s.get("codec_type") == "video"]
    audio = [s for s in streams if s.get("codec_type") == "audio"]
    subs = [s for s in streams if s.get("codec_type") == "subtitle"]
    attachments = [s for s in streams if s.get("codec_type") == "attachment"]
    duration = float(fmt.get("duration") or 0)
    overall = int(fmt.get("bit_rate") or 0)
    if not overall and duration:
        overall = int(size * 8 / duration)

    record.update({
        "format": fmt.get("format_name"),
        "duration": round(duration, 3),
        "overall_bitrate": overall,
        "video_bitrate": int((video[0].get("bit_rate") or 0)) if video else 0,
        "video": [{
            "codec": s.get("codec_name"),
            "profile": s.get("profile"),
            "level": s.get("level"),
            "width": s.get("width"),
            "height": s.get("height"),
            "pix_fmt": s.get("pix_fmt"),
            "bit_depth": s.get("bits_per_raw_sample"),
            "frame_rate": s.get("avg_frame_rate") or s.get("r_frame_rate"),
            "bitrate": int(s.get("bit_rate") or 0),
            "color_primaries": s.get("color_primaries"),
            "color_transfer": s.get("color_transfer"),
            "color_space": s.get("color_space"),
            "hdr": (s.get("color_transfer") in {"smpte2084", "arib-std-b67"}),
        } for s in video],
        "audio": [{
            "codec": s.get("codec_name"),
            "profile": s.get("profile"),
            "sample_rate": s.get("sample_rate"),
            "channels": s.get("channels"),
            "channel_layout": s.get("channel_layout"),
            "bitrate": int(s.get("bit_rate") or 0),
            "language": lang_of(s),
            "title": title_of(s),
            "default": track_flag(s, "default"),
            "forced": track_flag(s, "forced"),
        } for s in audio],
        "subtitles": [{
            "codec": s.get("codec_name"),
            "language": lang_of(s),
            "title": title_of(s),
            "default": track_flag(s, "default"),
            "forced": track_flag(s, "forced"),
        } for s in subs],
        "attachments": [{
            "filename": (s.get("tags") or {}).get("filename", ""),
            "mimetype": (s.get("tags") or {}).get("mimetype", ""),
        } for s in attachments],
        "chapters": len(probe.get("chapters") or []),
        "tags": {
            key: (fmt.get("tags") or {}).get(key)
            for key in ("title", "show", "season", "episode", "encoder", "comment")
            if (fmt.get("tags") or {}).get(key)
        },
    })

    audio_langs = sorted({a["language"] for a in record["audio"]})
    sub_langs = sorted({s["language"] for s in record["subtitles"]})
    record["audio_languages"] = audio_langs
    record["subtitle_languages"] = sub_langs
    record["mediainfo"] = media_info(path)
    record["pdf"] = pdf_info(path)

    pending = []
    if record["kind"] == "video":
        if not (("eng" in audio_langs) or ("eng" in sub_langs)):
            pending.append("no-english")
        if "und" in audio_langs or "und" in sub_langs:
            pending.append("und-language")
        if len(record["audio"]) > 1:
            pending.append("extra-audio")
        if len(record["subtitles"]) > 1:
            pending.append("extra-subtitles")
        if overall > VIDEO_TARGET:
            pending.append("compress")
        if len(record["video"]) > 1:
            pending.append("multiple-video")
    elif record["kind"] == "audio":
        if overall > AUDIO_TARGET:
            pending.append("compress")
        if "und" in audio_langs:
            pending.append("und-language")

    status = "green"
    if record["probe_error"]:
        status = "red"
    elif record["kind"] == "video":
        if "no-english" in pending:
            status = "red"
        elif pending:
            status = "yellow"
    elif record["kind"] == "audio" and "compress" in pending:
        status = "yellow"
    record["pending"] = pending
    record["status"] = status
    record["compressed"] = False
    return record


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default="/card")
    parser.add_argument("--out", default="/out")
    parser.add_argument("--roots", default="0-library/video,0-library/books,0-library/music")
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()

    root = Path(args.root)
    out = Path(args.out)
    roots = [item.strip() for item in args.roots.split(",") if item.strip()]
    out.mkdir(parents=True, exist_ok=True)

    files: list[Path] = []
    for rel_root in roots:
        base = root / rel_root
        if not base.is_dir():
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            for name in filenames:
                if name in SKIP_NAMES or name.startswith("."):
                    continue
                files.append(Path(dirpath) / name)

    records: list[dict] = []
    errors: list[dict] = []
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        futures = {pool.submit(probe_file, root, path): path for path in files}
        for future in as_completed(futures):
            path = futures[future]
            try:
                record = future.result()
            except Exception as exc:
                errors.append({"path": str(path.relative_to(root)), "error": str(exc)})
                continue
            if record.get("probe_error"):
                errors.append({"path": record["path"], "error": record["probe_error"]})
            records.append(record)

    records.sort(key=lambda item: item["path"])
    with (out / "files.jsonl").open("w") as handle:
        for record in records:
            handle.write(json.dumps(record, sort_keys=True) + "\n")
    with (out / "errors.jsonl").open("w") as handle:
        for error in errors:
            handle.write(json.dumps(error, sort_keys=True) + "\n")

    by_root = {}
    for record in records:
        top = record["path"].split("/", 1)[0]
        by_root[top] = by_root.get(top, 0) + 1

    run = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "root": str(root),
        "roots": roots,
        "files": len(records),
        "bytes": sum(item["size"] for item in records),
        "by_root": by_root,
        "errors": len(errors),
        "tools": {
            "ffprobe": subprocess.run(["ffprobe", "-version"], capture_output=True, text=True).stdout.splitlines()[0],
            "mediainfo": subprocess.run(["mediainfo", "--Version"], capture_output=True, text=True).stdout.splitlines()[0] if shutil_which("mediainfo") else "missing",
        },
    }
    (out / "run.json").write_text(json.dumps(run, indent=2) + "\n")
    print(f"collected {len(records)} files, {human(run['bytes'])}, {len(errors)} errors")


if __name__ == "__main__":
    main()
