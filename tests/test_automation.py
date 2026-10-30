import json
import plistlib
import shlex
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTROL = ROOT / "scripts" / "loon-reconnect.sh"
RUNTIME = ROOT / "scripts" / "reconnect.sh"
FIXTURE = ROOT / "tests" / "fixtures" / "commands.py"
LABEL = "com.ezio.loon-reconnect"
HARNESS = r'''
source "$1"
configure_paths "$2"
test_state=$3
test_python=$4
test_fixture=$5
launchctl() { "$test_python" "$test_fixture" "$test_state" launchctl "$@"; }
main "${@:6}"
'''


@unittest.skipUnless(sys.platform == "darwin", "macOS plutil is required")
class AutomationTests(unittest.TestCase):
    def setUp(self):
        work = ROOT / ".test-work"
        work.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="case-", dir=work)
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.home = self.base / "用户 & <test> ' home"
        self.home.mkdir()
        self.app = self.home / "Library/Application Support/LoonAutomation"
        self.logs = self.home / "Library/Logs/LoonAutomation"
        self.plist = self.home / "Library/LaunchAgents" / (LABEL + ".plist")
        self.backups = self.home / "Library/Application Support/LoonAutomationBackups"
        self.state_path = self.base / "commands.json"
        self.write_state({"gui": True, "loaded": False, "disabled": False, "calls": []})

    def read_state(self):
        return json.loads(self.state_path.read_text())

    def write_state(self, state):
        self.state_path.write_text(json.dumps(state))

    def control(self, *args, success=True, prelude=""):
        harness = HARNESS.replace('main "${@:6}"', prelude + '\nmain "${@:6}"')
        result = subprocess.run(
            ["/bin/bash", "-c", harness, "test", str(CONTROL), str(self.home),
             str(self.state_path), sys.executable, str(FIXTURE), *args],
            text=True, capture_output=True,
        )
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def install(self, *args):
        self.control("install", *args)
        return plistlib.loads(self.plist.read_bytes())

    def test_install_uses_current_user_paths_and_does_not_run(self):
        config = self.install()
        self.assertEqual(config["Label"], LABEL)
        self.assertEqual(config["ProgramArguments"], ["/bin/sh", str(self.app / "reconnect.sh")])
        self.assertEqual(config["StartInterval"], 21600)
        self.assertEqual(config["LimitLoadToSessionType"], "Aqua")
        self.assertEqual(config["Umask"], 63)
        self.assertNotIn("RunAtLoad", config)
        self.assertNotIn("KeepAlive", config)
        self.assertEqual(config["StandardOutPath"], str(self.logs / "reconnect.log"))
        self.assertEqual(config["StandardErrorPath"], str(self.logs / "reconnect.err.log"))
        for path, mode in [(self.app, 0o700), (self.logs, 0o700),
                           (self.app / "reconnect.sh", 0o700),
                           (self.app / "loon-reconnect.sh", 0o700), (self.plist, 0o600)]:
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), mode)
        state = self.read_state()
        self.assertTrue(state["loaded"])
        self.assertFalse(state["disabled"])
        self.assertEqual(state.get("runs", 0), 0)
        self.assertFalse(any(call[0] == "open" or "kickstart" in call for call in state["calls"]))

    def test_custom_hours(self):
        self.assertEqual(self.install("--hours", "3")["StartInterval"], 10800)

    def test_invalid_arguments_do_not_install(self):
        for args in [("install", "--hours", v) for v in ("0", "-1", "6.5", "abc", "9999999999999")]:
            with self.subTest(args=args):
                self.control(*args, success=False)
                self.assertFalse(self.app.exists())
                self.assertFalse(self.plist.exists())
        self.control("install", "--unknown", success=False)
        self.control("run", "unexpected", success=False)

    def test_repeat_install_is_idempotent_and_changed_content_is_preserved(self):
        self.install()
        before = self.plist.stat().st_mtime_ns
        self.control("install")
        self.assertEqual(self.plist.stat().st_mtime_ns, before)
        self.assertEqual(sum(c[1] == "bootstrap" for c in self.read_state()["calls"]), 1)
        runtime = self.app / "reconnect.sh"
        runtime.write_text(runtime.read_text() + "\n# local change\n")
        self.control("install", success=False)
        self.assertTrue(runtime.read_text().endswith("# local change\n"))
        self.assertTrue(self.read_state()["loaded"])

    def test_reinstall_after_pause_resumes_without_running(self):
        self.install()
        self.control("pause")
        self.control("install")
        self.assertTrue(self.read_state()["loaded"])
        self.assertFalse(self.read_state()["disabled"])
        self.assertEqual(self.read_state().get("runs", 0), 0)

    def test_legacy_install_is_backed_up_before_migration(self):
        self.install()
        (self.app / "loon-reconnect.sh").unlink()
        self.control("install", success=False)
        self.control("uninstall")
        self.control("install")
        self.assertTrue((self.app / "loon-reconnect.sh").is_file())
        backup, = list(self.backups.iterdir())
        self.assertTrue((backup / "scripts/reconnect.sh").is_file())
        self.assertFalse((backup / "scripts/loon-reconnect.sh").exists())

    def test_pause_resume_and_run(self):
        self.install()
        self.control("pause")
        state = self.read_state()
        self.assertTrue(state["disabled"])
        self.assertFalse(state["loaded"])
        self.control("resume")
        self.assertTrue(self.read_state()["loaded"])
        self.assertFalse(self.read_state()["disabled"])
        self.control("run")
        calls = [c for c in self.read_state()["calls"] if c[1] == "kickstart"]
        self.assertEqual(len(calls), 1)
        self.assertNotIn("-k", calls[0])

    def test_active_cycle_is_never_unloaded(self):
        self.install()
        state = self.read_state()
        state["running"] = True
        self.write_state(state)
        for action in ("pause", "uninstall"):
            self.control(action, success=False)
        self.assertTrue(self.read_state()["loaded"])
        self.assertFalse(self.read_state()["disabled"])
        self.assertFalse(self.backups.exists())
        self.assertTrue(self.plist.exists())

    def test_status_does_not_dump_environment(self):
        self.install()
        result = self.control("status")
        self.assertIn("21600", result.stdout)
        self.assertNotIn("must-not-print", result.stdout + result.stderr)

    def test_uninstall_preserves_all_files_in_backup(self):
        self.install()
        (self.logs / "reconnect.log").write_text("test log\n")
        script = (self.app / "reconnect.sh").read_bytes()
        plist = self.plist.read_bytes()
        self.control("uninstall")
        self.assertFalse(self.app.exists())
        self.assertFalse(self.logs.exists())
        self.assertFalse(self.plist.exists())
        backup, = list(self.backups.iterdir())
        self.assertEqual((backup / "scripts/reconnect.sh").read_bytes(), script)
        self.assertEqual((backup / (LABEL + ".plist")).read_bytes(), plist)
        self.assertEqual((backup / "logs/reconnect.log").read_text(), "test log\n")
        self.assertTrue(self.read_state()["disabled"])
        self.assertFalse(self.read_state()["loaded"])
        self.control("uninstall")
        self.assertEqual(len(list(self.backups.iterdir())), 1)

    def test_bootstrap_failure_is_paused_and_can_be_resumed(self):
        state = self.read_state()
        state["fail_bootstrap"] = True
        self.write_state(state)
        self.control("install", success=False)
        self.assertTrue(self.plist.exists())
        self.assertTrue(self.read_state()["disabled"])
        state = self.read_state()
        state["fail_bootstrap"] = False
        self.write_state(state)
        self.control("resume")
        self.assertTrue(self.read_state()["loaded"])
        self.assertFalse(self.read_state()["disabled"])

    def test_broken_runtime_can_still_be_paused_and_backed_up(self):
        self.install()
        (self.app / "reconnect.sh").write_text("#!/bin/sh\nif\n")
        self.control("resume", success=False)
        self.control("pause")
        self.control("uninstall")
        backup, = list(self.backups.iterdir())
        self.assertEqual((backup / "scripts/reconnect.sh").read_text(), "#!/bin/sh\nif\n")

    def test_missing_gui_or_root_or_non_macos_is_rejected(self):
        state = self.read_state()
        state["gui"] = False
        self.write_state(state)
        self.control("install", success=False)
        self.control("install", prelude="id() { printf '0\\n'; }", success=False)
        self.control("install", prelude="uname() { printf 'Linux\\n'; }", success=False)
        self.assertFalse(self.app.exists())

    def test_foreign_plist_and_symlinks_are_not_managed(self):
        self.plist.parent.mkdir(parents=True)
        self.plist.write_bytes(plistlib.dumps({"Label": "another.application"}))
        self.control("uninstall", success=False)
        self.assertTrue(self.plist.exists())
        self.assertEqual(self.read_state()["calls"][-1][1], "print")
        self.plist.unlink()
        self.app.parent.mkdir(parents=True)
        self.app.symlink_to(self.base / "unrelated")
        self.control("install", success=False)
        self.assertTrue(self.app.is_symlink())

    def test_runtime_sequence_and_failures(self):
        expected = [
            ["open", "-g", "loon://off"], ["sleep", "3"],
            ["open", "-g", "loon://on"], ["sleep", "10"],
            ["open", "-g", "loon://update?sub=all"],
        ]
        for failures in ([], ["loon://off"], ["loon://on"], ["loon://update?sub=all"]):
            with self.subTest(failures=failures):
                self.write_state({"calls": [], "fail_urls": failures})
                source = RUNTIME.read_text()
                # Fail before execution if the known command seams change.
                self.assertEqual(source.count("/usr/bin/open"), 1)
                self.assertEqual(source.count("/bin/sleep"), 2)
                for command, original in (("open", "/usr/bin/open"), ("sleep", "/bin/sleep")):
                    wrapper = self.base / ("fake_" + command)
                    invocation = [sys.executable, str(FIXTURE), str(self.state_path), command]
                    wrapper.write_text("#!/bin/sh\nexec " + shlex.join(invocation) + ' "$@"\n')
                    wrapper.chmod(0o700)
                    source = source.replace(original, shlex.quote(str(wrapper)))
                runtime = self.base / "reconnect-under-test.sh"
                runtime.write_text(source)
                result = subprocess.run(["/bin/sh", str(runtime)], text=True, capture_output=True)
                self.assertEqual(result.returncode, int(bool(failures)))
                self.assertEqual(self.read_state()["calls"], expected)
                self.assertEqual(result.stdout.count(" sent "), 3 - len(failures))
                self.assertEqual(result.stderr.count(" failed "), len(failures))


if __name__ == "__main__":
    unittest.main()
