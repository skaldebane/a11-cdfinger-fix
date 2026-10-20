#!/usr/bin/env python3
"""Build a reproducible, Magisk-app-installable module ZIP (stdlib only)."""

import argparse
import hashlib
from pathlib import Path
import re
import stat
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MODULE_FILES = (
    "module.prop", "customize.sh", "common.sh", "action.sh", "README.md", "LICENSE",
)
PAYLOAD = "system/vendor/lib/hw/fingerprint.silead.default.so"


def build(output_dir: Path) -> Path:
    metadata = dict(
        line.split("=", 1)
        for line in (ROOT / "module.prop").read_text().splitlines()
        if line and not line.startswith("#")
    )
    module_id, version = metadata["id"], metadata["version"]
    if not re.fullmatch(r"[a-zA-Z][a-zA-Z0-9._-]+", module_id):
        raise ValueError("Invalid Magisk module ID")
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Expected a vMAJOR.MINOR.PATCH version")
    if (ROOT / PAYLOAD).read_bytes() != b"":
        raise ValueError("Silead overlay must be exactly zero bytes")

    output_dir.mkdir(parents=True, exist_ok=True)
    destination = output_dir / f"{module_id}-{version}.zip"
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name in sorted((*MODULE_FILES, PAYLOAD)):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            mode = 0o755 if name == "action.sh" else 0o644
            info.external_attr = (stat.S_IFREG | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, (ROOT / name).read_bytes())
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    destination.with_suffix(".zip.sha256").write_text(f"{digest}  {destination.name}\n")
    return destination


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    print(build(parser.parse_args().output))
