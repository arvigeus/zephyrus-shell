import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from services import idle


class IdlePolicyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.runtime = Path(self.temporary.name)
        self.environment = patch.dict(
            os.environ,
            {"XDG_RUNTIME_DIR": str(self.runtime), "HYPRLAND_INSTANCE_SIGNATURE": "session-one"},
        )
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def test_pause_survives_shell_recreation_but_not_a_new_session(self):
        with patch.object(idle.subprocess, "run") as restart:
            self.assertTrue(idle.set_paused(True)["paused"])
            self.assertTrue(idle.state()["paused"])
            with patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "session-two"}):
                self.assertFalse(idle.state()["paused"])
            self.assertFalse(idle.set_paused(False)["paused"])
        self.assertEqual(restart.call_count, 2)
        self.assertEqual(
            restart.call_args.args[0], ["systemctl", "--user", "restart", "hypridle.service"]
        )

    def test_paused_profile_keeps_blanking_manual_lock_and_resume_only(self):
        normal = idle.configuration(False)
        self.assertEqual(normal, (idle.ROOT / "hyprland/hypridle.conf").read_text())
        self.assertIn("inhibit_sleep = 3", normal)
        self.assertIn("before_sleep_cmd = loginctl lock-session", normal)
        self.assertIn("timeout = 1800", normal)
        paused = idle.configuration(True)
        self.assertNotIn("before_sleep_cmd", paused)
        self.assertNotIn("on-timeout = loginctl lock-session", paused)
        self.assertNotIn("on-timeout = systemctl", paused)
        self.assertIn("inhibit_sleep = 1", paused)
        self.assertIn("lock_cmd = pgrep -x hyprlock >/dev/null || hyprlock", paused)
        self.assertIn("timeout = 360", paused)
        self.assertIn("zephyrus.wake_displays()", paused)

    def test_lid_locks_only_when_pause_is_off(self):
        with patch.object(idle.subprocess, "run") as command:
            idle.lock_on_lid()
            command.assert_called_once_with(["loginctl", "lock-session"], check=True, timeout=8)
            idle.set_paused(True)
            command.reset_mock()
            idle.lock_on_lid()
            command.assert_not_called()

    def test_failed_restart_rolls_back_pause_and_restore(self):
        for previous in (False, True):
            directory = idle.session_directory()
            directory.mkdir(parents=True, exist_ok=True)
            marker = directory / "unlocked"
            if previous:
                marker.touch()
            else:
                marker.unlink(missing_ok=True)
            failure = subprocess.CalledProcessError(1, ["systemctl"])
            with patch.object(idle.subprocess, "run", side_effect=[failure, None]) as restart:
                with self.assertRaisesRegex(ValueError, "Could not change"):
                    idle.set_paused(not previous)
                self.assertEqual(restart.call_count, 2)
            self.assertEqual(idle.state()["paused"], previous)

    def test_real_launcher_writes_transient_profile_and_executes_hypridle(self):
        with patch.object(idle.os, "execvp") as execute:
            idle.run_idle()
            path = Path(execute.call_args.args[1][-1])
            self.assertTrue(path.is_relative_to(self.runtime))
            self.assertIn("inhibit_sleep = 3", path.read_text())
            (idle.session_directory() / "unlocked").touch()
            idle.run_idle()
            self.assertIn("inhibit_sleep = 1", path.read_text())

    def test_missing_or_invalid_session_cannot_create_a_pause(self):
        for signature in ("", "../escape"):
            with patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": signature}):
                self.assertFalse(idle.state()["available"])
                with self.assertRaises(ValueError):
                    idle.set_paused(True)

    def test_real_cli_reads_runtime_state_without_writing_personal_config(self):
        cli = ["python3", str(idle.ROOT / "scripts/idle.py"), "get"]
        first = json.loads(subprocess.check_output(cli))
        self.assertEqual(first, {"available": True, "paused": False})
        self.assertEqual(list(self.runtime.iterdir()), [])
