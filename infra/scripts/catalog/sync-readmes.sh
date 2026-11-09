#!/usr/bin/env bash
# Mirror every managed card README into the private offline tree.
set -euo pipefail

CARD="${1:-/mnt/microsd}"
OUT="${2:-/home/user/repos/private/journal/docs/offline/card}"

python3 - "$CARD" "$OUT" <<'PY'
import os
import shutil
import sys
from pathlib import Path

card = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()
skip_top = {
    "Android", "Alarms", "DCIM", "Notifications", "Pictures",
    "Recordings", "Ringtones", ".trash-storage", "System Volume Information",
}
skip_names = {"porn"}
expected = set()
for dirpath, dirnames, filenames in os.walk(card):
    rel_dir = Path(dirpath).relative_to(card)
    if rel_dir.parts and rel_dir.parts[0] in skip_top:
        dirnames[:] = []
        continue
    dirnames[:] = [d for d in dirnames if d not in skip_top and d not in skip_names]
    if "README.md" not in filenames:
        continue
    src = Path(dirpath) / "README.md"
    rel = src.relative_to(card)
    dst = out / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    dst.chmod(0o644)
    expected.add(rel)

# Remove mirrored READMEs that no longer exist on the card.
for path in sorted(out.rglob("README.md")):
    rel = path.relative_to(out)
    if rel not in expected:
        path.unlink()
        print(f"removed stale {rel}")

# Remove empty directories left behind.
for path in sorted((p for p in out.rglob("*") if p.is_dir()), reverse=True):
    try:
        path.rmdir()
    except OSError:
        pass

print(f"mirrored {len(expected)} READMEs to {out}")
PY
