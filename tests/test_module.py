import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("build", ROOT / "tools/build.py")
BUILD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD)


class ModuleTests(unittest.TestCase):
    def check_device(self, **overrides):
        properties = {
            "DEVICE": "a11q",
            "API": "31",
            "FIRMWARE": "samsung/a11qnsxx/a11q:12/SP1A.210812.016/A115FXXU3CVI3:user/release-keys",
            "SENSOR": "cdfinger",
        }
        properties.update(overrides)
        script = '''
getprop() {
  case "$1" in
    ro.product.device) echo "$DEVICE" ;;
    ro.build.version.sdk) echo "$API" ;;
    ro.vendor.build.fingerprint) echo "$FIRMWARE" ;;
    persist.vendor.runin.fp) echo "$SENSOR" ;;
  esac
}
. "$COMMON"
check_compatibility
'''
        return subprocess.run(
            ["sh", "-c", script],
            env={**os.environ, **properties, "COMMON": str(ROOT / "common.sh")},
            capture_output=True, text=True,
        )

    def test_supported_device(self):
        self.assertEqual(self.check_device().returncode, 0)

    def test_reject_other_device(self):
        self.assertNotEqual(self.check_device(DEVICE="a22").returncode, 0)

    def test_reject_other_android(self):
        self.assertNotEqual(self.check_device(API="30").returncode, 0)

    def test_reject_other_firmware(self):
        self.assertNotEqual(self.check_device(FIRMWARE="another-build").returncode, 0)

    def test_reject_other_sensor(self):
        self.assertNotEqual(self.check_device(SENSOR="silead").returncode, 0)

    def test_reject_unknown_sensor(self):
        self.assertNotEqual(self.check_device(SENSOR="").returncode, 0)

    def test_shell_syntax(self):
        for script in ROOT.glob("*.sh"):
            with self.subTest(script=script.name):
                subprocess.run(["sh", "-n", str(script)], check=True)

    def test_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            archive_path = BUILD.build(Path(directory))
            with zipfile.ZipFile(archive_path) as archive:
                self.assertEqual(
                    set(archive.namelist()), set((*BUILD.MODULE_FILES, BUILD.PAYLOAD))
                )
                self.assertEqual(archive.read(BUILD.PAYLOAD), b"")
                self.assertEqual(archive.testzip(), None)
                self.assertNotIn("skip_mount", archive.namelist())
                self.assertNotIn("system.prop", archive.namelist())
                self.assertNotIn("sepolicy.rule", archive.namelist())
                self.assertEqual(
                    (archive.getinfo("action.sh").external_attr >> 16) & 0o777, 0o755
                )
            self.assertTrue(archive_path.with_suffix(".zip.sha256").exists())

    def test_reproducible_build(self):
        with tempfile.TemporaryDirectory() as directory:
            first = BUILD.build(Path(directory) / "one").read_bytes()
            second = BUILD.build(Path(directory) / "two").read_bytes()
            self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main()
