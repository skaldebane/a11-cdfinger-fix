#!/usr/bin/env python3
"""Build the separate passive-monitor Magisk module using only Python's stdlib."""
import hashlib
from pathlib import Path
import stat
import zipfile

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
FILES = (
    "module.prop", "skip_mount", "customize.sh", "lib.sh", "collector.sh",
    "kernel-log.awk", "snapshot.sh", "daemon.sh", "control.sh", "service.sh",
    "action.sh", "uninstall.sh", "README.md",
)


def build(output_dir=None):
    metadata = dict(line.split("=", 1) for line in (ROOT / "module.prop").read_text().splitlines())
    output_dir = Path(output_dir) if output_dir is not None else REPO / "dist"
    output_dir.mkdir(parents=True, exist_ok=True)
    destination = output_dir / f"{metadata['id']}-{metadata['version']}.zip"
    sources = {name: ROOT / name for name in FILES}
    sources.update({"common.sh": REPO / "common.sh", "LICENSE": REPO / "LICENSE"})
    with zipfile.ZipFile(destination, "w") as archive:
        for name, source in sorted(sources.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            mode = 0o755 if name.endswith(".sh") else 0o644
            info.external_attr = (stat.S_IFREG | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, source.read_bytes())
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    destination.with_suffix(".zip.sha256").write_text(f"{digest}  {destination.name}\n")
    return destination


if __name__ == "__main__":
    print(build())
