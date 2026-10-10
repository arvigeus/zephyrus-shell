import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / "scripts"))
import machine
import profiles


class SettingsTests(unittest.TestCase):
    def test_asus_profile_uses_the_existing_owner(self):
        def output(args, *unused):
            return (
                {
                    "systemctl": "active",
                    "list": "Quiet\nBalanced\nPerformance",
                    "get": "Active profile: Quiet",
                }.get(args[-1], "")
                if args[0] != "systemctl"
                else "active"
            )

        with (
            patch.object(machine.shutil, "which", return_value="/usr/bin/asusctl"),
            patch.object(machine, "command", side_effect=output) as command,
        ):
            self.assertEqual(machine.power_status()["profile"], "power-saver")
            machine.action("profile", "balanced")
            self.assertIn(
                unittest.mock.call(["asusctl", "profile", "set", "Balanced"], True),
                command.call_args_list,
            )
            self.assertFalse(
                any(c.args[0][0] == "powerprofilesctl" for c in command.call_args_list)
            )

    def test_never_disables_last_display(self):
        with patch.object(
            machine, "command", return_value=json.dumps([{"name": "eDP-1", "disabled": False}])
        ) as command:
            with self.assertRaisesRegex(ValueError, "at least one"):
                machine.action("display", json.dumps({"name": "eDP-1", "enabled": False}))
            self.assertEqual(command.call_count, 1)

    def test_charge_limit_bounds(self):
        for value in ["49", "101", "bad"]:
            with self.assertRaises(ValueError):
                machine.action("chargeLimit", value)

    def test_delayed_shutdown_uses_allowlisted_minutes(self):
        with patch.object(machine, "command") as command:
            for value in ("0", "14", "45", "301", "15; reboot"):
                with self.assertRaises(ValueError):
                    machine.action("schedule-poweroff", value)
            command.assert_not_called()
            machine.action("schedule-poweroff", "90")
            command.assert_called_once_with(["systemctl", "poweroff", "--when=+90min"], True, 60)

    def test_cancel_delayed_shutdown(self):
        with patch.object(machine, "command") as command:
            machine.action("cancel-poweroff", "")
            command.assert_called_once_with(["systemctl", "poweroff", "--when=cancel"], True, 60)

    def test_scheduled_shutdown_status_survives_unavailable_systemd(self):
        with (
            patch.object(machine.shutil, "which", return_value="/usr/bin/systemctl"),
            patch.object(
                machine.subprocess, "run", side_effect=subprocess.TimeoutExpired("systemctl", 5)
            ),
        ):
            self.assertEqual(machine.scheduled_shutdown(), "")

    def test_thumbnail_cleanup_only_removes_generated_previews(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.dict(os.environ, {"XDG_CACHE_HOME": directory}),
        ):
            cache = Path(directory)
            thumbnails = cache / "thumbnails" / "normal"
            thumbnails.mkdir(parents=True)
            (thumbnails / "preview.png").write_bytes(b"preview")
            (cache / "important.json").write_text("keep")
            with self.assertRaises(ValueError):
                machine.action("clean-thumbnails", "")
            machine.action("clean-thumbnails", "confirm")
            self.assertFalse((thumbnails / "preview.png").exists())
            self.assertEqual((cache / "important.json").read_text(), "keep")

    def test_thumbnail_cleanup_rejects_symlink_target(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.dict(os.environ, {"XDG_CACHE_HOME": directory}),
        ):
            outside = Path(directory) / "outside"
            outside.mkdir()
            (outside / "keep").write_text("keep")
            (Path(directory) / "thumbnails").symlink_to(outside, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "symlink"):
                machine.action("clean-thumbnails", "confirm")
            self.assertTrue((outside / "keep").exists())

    def test_profile_edits_persist(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(profiles, "FILE", Path(directory) / "profiles.json"),
        ):
            profiles.run("edit", json.dumps({"wifi": False, "brightness": 65}))
            data = profiles.load()
            active = next(p for p in data["profiles"] if p["name"] == data["active"])
            self.assertFalse(active["settings"]["wifi"])
            self.assertEqual(active["settings"]["brightness"], 65)
            for change in ({"gpu": "hybrid"}, {"shell": "true"}):
                with self.assertRaises(ValueError):
                    profiles.run("edit", json.dumps(change))

    def test_old_gpu_setting_does_not_block_profile_selection(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(profiles, "FILE", Path(directory) / "profiles.json"),
            patch.object(machine, "action") as action,
        ):
            data = profiles.load()
            data["profiles"][0]["settings"]["gpu"] = "hybrid"
            profiles.save(data)
            result = profiles.run("select", data["profiles"][0]["name"])
        self.assertEqual(result["error"], "")
        self.assertEqual(result["data"]["active"], data["profiles"][0]["name"])
        action.assert_called_once_with("profile", "power-saver")

    def test_profile_partial_failure_is_reported(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(profiles, "FILE", Path(directory) / "profiles.json"),
            patch.object(machine, "action", side_effect=RuntimeError("Unavailable")),
        ):
            result = profiles.run("select", "Quiet")
            self.assertIn("Unavailable", result["error"])
            self.assertEqual(result["data"]["active"], "Balanced")
