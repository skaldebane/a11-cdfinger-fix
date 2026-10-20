import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MONITOR = ROOT / "monitor"
SPEC = importlib.util.spec_from_file_location("monitor_build", MONITOR / "build.py")
BUILD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD)


class MonitorTests(unittest.TestCase):
    def shell(self, script, directory):
        return subprocess.run(
            ["sh", "-c", '. "$LIB"; STATE="$TEST_STATE"; ' + script],
            env={**os.environ, "LIB": str(MONITOR / "lib.sh"), "TEST_STATE": str(directory)},
            capture_output=True, text=True, check=True,
        )

    def test_shell_syntax(self):
        for script in MONITOR.glob("*.sh"):
            with self.subTest(script=script.name):
                subprocess.run(["sh", "-n", str(script)], check=True)

    def test_no_event_for_stable_state(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.shell('event_reason running:42 running:42 old old', directory)
            self.assertEqual(result.stdout, "")

    def test_pid_change_triggers(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.shell('event_reason running:42 running:43 old old', directory)
            self.assertEqual(result.stdout.strip(), "hal-lifecycle-change")

    def test_service_exit_triggers(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.shell('event_reason running:42 restarting:none old old', directory)
            self.assertEqual(result.stdout.strip(), "hal-lifecycle-change")

    def test_new_error_triggers_without_pid_change(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.shell('event_reason running:42 running:42 old new', directory)
            self.assertEqual(result.stdout.strip(), "hal-error-log")

    def test_empty_error_does_not_trigger(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.shell('event_reason running:42 running:42 old ""', directory)
            self.assertEqual(result.stdout, "")

    def test_root_only_state(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "private"
            self.shell('prepare_state; echo private > "$STATE/test"', state)
            self.assertEqual(state.stat().st_mode & 0o777, 0o700)
            self.assertEqual((state / "test").stat().st_mode & 0o777, 0o600)

    def test_disabled_module_is_detected(self):
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "disable").touch()
            result = self.shell('MODDIR="$STATE"; if module_disabled; then echo disabled; fi', directory)
            self.assertEqual(result.stdout.strip(), "disabled")

    def test_invalid_pids_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.shell(
                'for pid in "" 0 1 -1 nope "2 3"; do if valid_pid "$pid"; then echo unsafe; fi; done',
                directory,
            )
            self.assertEqual(result.stdout, "")

    def test_collectors_release_inherited_lock_descriptor(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.shell(
                'exec 9> "$STATE/run.lock"; close_inherited_lock; '
                'if [ -e /proc/$$/fd/9 ]; then echo leaked; else echo closed; fi', directory
            )
            self.assertEqual(result.stdout.strip(), "closed")

    def test_retention_keeps_six_newest(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            (state / "incidents").mkdir()
            for i in range(8):
                (state / "incidents" / f"incident-{i:02d}").mkdir()
            (state / "incidents" / "unrelated").mkdir()
            self.shell('prune_incidents', state)
            names = sorted(path.name for path in (state / "incidents").iterdir())
            self.assertEqual(names, [f"incident-{i:02d}" for i in range(2, 8)] + ["unrelated"])

    def test_retention_does_not_follow_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "state"
            external = Path(directory) / "external"
            (state / "incidents").mkdir(parents=True)
            external.mkdir()
            (external / "keep").write_text("private")
            (state / "incidents" / "incident-00").symlink_to(external, target_is_directory=True)
            self.shell('MAX_INCIDENTS=0; prune_incidents', state)
            self.assertTrue((external / "keep").exists())

    def test_context_is_bounded(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory)
            (state / "logcat.log").write_bytes(b"a" * 100000)
            self.shell('copy_context "$STATE/before"', state)
            self.assertEqual((state / "before/logcat.log").stat().st_size, 65536)

    def test_kernel_filter_and_rotation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "kernel.log"
            lines = "unrelated secret\n" + "\n".join(f"cdfinger event {i}" for i in range(80))
            lines += "\ncdfinger template PRIVATE\nsilead irq error\n"
            subprocess.run(
                ["awk", "-v", f"path={path}", "-v", "limit=160", "-f", str(MONITOR / "kernel-log.awk")],
                input=lines, text=True, check=True,
            )
            chunks = list(Path(directory).glob("kernel.log*"))
            self.assertEqual(len(chunks), 4)
            contents = "".join(chunk.read_text() for chunk in chunks)
            self.assertNotIn("PRIVATE", contents)
            self.assertNotIn("secret", contents)
            self.assertIn("silead irq error", contents)
            self.assertTrue(all(chunk.stat().st_size <= 160 for chunk in chunks))

    def test_notification_cooldown(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.shell(
                'date +%s > "$STATE/last-notification"; notify_incident test hal-error-log', directory
            )
            self.assertEqual(result.stdout, "")
            self.assertIn("coalesced", (Path(directory) / "monitor.log").read_text())

    def test_kernel_filter_keeps_init_exit_status(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "kernel.log"
            event = "init: Service 'vendor.fps_hal' (pid 123) exited with status 0\n"
            subprocess.run(
                ["awk", "-v", f"path={path}", "-v", "limit=524288", "-f", str(MONITOR / "kernel-log.awk")],
                input=event, text=True, check=True,
            )
            self.assertEqual(path.read_text(), event)

    def test_shell_quote_keeps_arguments_literal(self):
        with tempfile.TemporaryDirectory() as directory:
            result = self.shell(
                '''value="spaces ' quote ; \\$(echo BAD)"; quoted=$(shell_quote "$value");
eval "set -- $quoted"; printf '%s' "$1"''', directory
            )
            self.assertEqual(result.stdout, "spaces ' quote ; $(echo BAD)")

    def test_archive_and_reproducibility(self):
        with tempfile.TemporaryDirectory() as directory:
            first = BUILD.build(Path(directory) / "one")
            second = BUILD.build(Path(directory) / "two")
            self.assertEqual(first.read_bytes(), second.read_bytes())
            with zipfile.ZipFile(first) as archive:
                self.assertEqual(archive.testzip(), None)
                self.assertIn("skip_mount", archive.namelist())
                self.assertIn("common.sh", archive.namelist())
                self.assertIn("snapshot.sh", archive.namelist())
                self.assertFalse(any(name.startswith("system/") for name in archive.namelist()))
                self.assertNotIn("sepolicy.rule", archive.namelist())
                for name in archive.namelist():
                    if name.endswith(".sh"):
                        self.assertEqual((archive.getinfo(name).external_attr >> 16) & 0o777, 0o755)


if __name__ == "__main__":
    unittest.main()
