import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


screenshot = module("desktop_screenshot", "scripts/screenshot.py")
with patch.dict(sys.modules, {"screenshot": screenshot}):
    recorder = module("desktop_recorder", "scripts/record-screen.py")


class ScreenshotTests(unittest.TestCase):
    def test_delayed_area_waits_before_hyprshot_frozen_selection_and_editor(self):
        events = []
        with tempfile.TemporaryDirectory(prefix="delayed area ") as directory:

            def execute(command, **kwargs):
                if command[0] == "xdg-user-dir":
                    return subprocess.CompletedProcess(command, 0, directory + "\n", "")
                events.append("frozen selection and capture")
                self.assertEqual(command[:3], ["/usr/bin/hyprshot", "-m", "region"])
                self.assertIn("--freeze", command)
                self.assertIn("--silent", command)
                self.assertNotIn("active", command)
                (Path(command[4]) / command[6]).write_bytes(b"PNG fixture")
                return subprocess.CompletedProcess(command, 0)

            with (
                patch.object(
                    screenshot.shutil, "which", side_effect=lambda name: "/usr/bin/" + name
                ),
                patch.object(screenshot.subprocess, "run", side_effect=execute),
                patch.object(
                    screenshot.time, "sleep", side_effect=lambda delay: events.append(delay)
                ),
                patch.object(
                    screenshot.os, "execv", side_effect=lambda *args: events.append("editor")
                ),
            ):
                self.assertIsNotNone(screenshot.capture("region", edit=True, delay=5))
            self.assertEqual(events, [5, "frozen selection and capture", "editor"])

    def test_cancelled_delayed_selection_never_opens_editor(self):
        with tempfile.TemporaryDirectory() as directory:
            for status in (0, 1):
                with (
                    self.subTest(status=status),
                    patch.object(screenshot.shutil, "which", side_effect=lambda name: name),
                    patch.object(
                        screenshot.subprocess,
                        "run",
                        side_effect=[
                            subprocess.CompletedProcess([], 0, directory + "\n", ""),
                            subprocess.CompletedProcess([], status),
                        ],
                    ) as run,
                    patch.object(screenshot.time, "sleep") as sleep,
                    patch.object(screenshot.os, "execv") as editor,
                ):
                    self.assertIsNone(screenshot.capture("region", edit=True, delay=5))
                    self.assertEqual(run.call_count, 2)
                    sleep.assert_called_once_with(5)
                    editor.assert_not_called()

    def test_missing_hyprpicker_fails_before_delayed_selection(self):
        with (
            patch.object(
                screenshot.shutil,
                "which",
                side_effect=lambda name: None if name == "hyprpicker" else name,
            ),
            patch.object(screenshot.subprocess, "run") as run,
            patch.object(screenshot.time, "sleep") as sleep,
        ):
            with self.assertRaisesRegex(ValueError, "Install hyprpicker"):
                screenshot.capture("region", edit=True, delay=5)
            run.assert_not_called()
            sleep.assert_not_called()

    def test_delayed_screen_capture_waits_before_capture_and_annotation(self):
        events = []
        with tempfile.TemporaryDirectory() as directory:

            def execute(command, **kwargs):
                if command[0] == "xdg-user-dir":
                    return subprocess.CompletedProcess(command, 0, directory + "\n", "")
                events.append("capture")
                self.assertEqual(command[:3], ["/usr/bin/hyprshot", "-m", "output"])
                self.assertEqual(command[7:9], ["-m", "active"])
                (Path(command[4]) / command[6]).write_bytes(b"PNG fixture")
                return subprocess.CompletedProcess(command, 0)

            with (
                patch.object(
                    screenshot.shutil, "which", side_effect=lambda name: "/usr/bin/" + name
                ),
                patch.object(screenshot.subprocess, "run", side_effect=execute),
                patch.object(
                    screenshot.time, "sleep", side_effect=lambda delay: events.append(delay)
                ),
                patch.object(
                    screenshot.os, "execv", side_effect=lambda *args: events.append("editor")
                ),
            ):
                self.assertIsNotNone(screenshot.capture("output", edit=True, delay=5))
            self.assertEqual(events, [5, "capture", "editor"])

    def test_invalid_delays_fail_without_waiting_or_capturing(self):
        for delay in (-1, float("nan"), float("inf")):
            with (
                self.subTest(delay=delay),
                patch.object(screenshot.time, "sleep") as sleep,
                patch.object(screenshot.subprocess, "run") as run,
            ):
                with self.assertRaisesRegex(ValueError, "delay"):
                    screenshot.capture("output", delay=delay)
                sleep.assert_not_called()
                run.assert_not_called()

    def test_screen_capture_uses_xdg_pictures_and_active_output(self):
        with tempfile.TemporaryDirectory(prefix="screens with spaces ") as directory:

            def execute(command, **kwargs):
                if command[0] == "xdg-user-dir":
                    return subprocess.CompletedProcess(command, 0, directory + "\n", "")
                (Path(command[4]) / command[6]).write_bytes(b"PNG fixture")
                return subprocess.CompletedProcess(command, 0)

            with (
                patch.object(screenshot.shutil, "which", return_value="/usr/bin/hyprshot"),
                patch.object(screenshot.subprocess, "run", side_effect=execute) as run,
                patch.object(screenshot.time, "sleep") as sleep,
            ):
                result = screenshot.capture("output")
            sleep.assert_not_called()
            command = run.call_args_list[1].args[0]
            self.assertEqual(command[:3], ["/usr/bin/hyprshot", "-m", "output"])
            self.assertEqual(command[-2:], ["-m", "active"])
            self.assertEqual(command[4], str(Path(directory) / "Screenshots"))
            self.assertEqual(result.parent, Path(directory) / "Screenshots")

    def test_interactive_selection_keeps_shell_surfaces_open(self):
        replies = [
            subprocess.CompletedProcess([], 0, "", ""),
            subprocess.CompletedProcess([], 1, "", ""),
        ]
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(screenshot.Path, "home", return_value=Path(directory)),
            patch.object(screenshot.shutil, "which", return_value="hyprshot"),
            patch.object(screenshot.subprocess, "run", side_effect=replies) as run,
        ):
            self.assertIsNone(screenshot.capture("region"))
            self.assertEqual(run.call_args_list[0].args[0], ["xdg-user-dir", "PICTURES"])
            self.assertEqual(run.call_args_list[1].args[0][:3], ["hyprshot", "-m", "region"])

    def test_annotation_replaces_helper_and_keeps_paths_as_arguments(self):
        with tempfile.TemporaryDirectory(prefix="edited captures ") as directory:

            def execute(command, **kwargs):
                if command[0] == "xdg-user-dir":
                    return subprocess.CompletedProcess(command, 0, directory + "\n", "")
                (Path(command[4]) / command[6]).write_bytes(b"PNG fixture")
                return subprocess.CompletedProcess(command, 0)

            with (
                patch.object(
                    screenshot.shutil, "which", side_effect=lambda name: "/usr/bin/" + name
                ),
                patch.object(screenshot.subprocess, "run", side_effect=execute) as run,
                patch.object(screenshot.os, "execv") as launch,
            ):
                image = screenshot.capture("window", edit=True, active=True)
            command = run.call_args_list[1].args[0]
            self.assertIn("active", command)
            self.assertIn("--silent", command)
            self.assertEqual(
                launch.call_args.args,
                (
                    "/usr/bin/satty",
                    [
                        "/usr/bin/satty",
                        "--config",
                        str(ROOT / "config/satty.toml"),
                        "--filename",
                        str(image),
                        "--output-filename",
                        str(image),
                    ],
                ),
            )

    def test_cancelled_capture_never_opens_editor_even_if_helper_exits_zero(self):
        with tempfile.TemporaryDirectory() as directory:
            for status in (0, 1):
                replies = [
                    subprocess.CompletedProcess([], 0, directory + "\n", ""),
                    subprocess.CompletedProcess([], status),
                ]
                with (
                    patch.object(screenshot.shutil, "which", side_effect=lambda name: name),
                    patch.object(screenshot.subprocess, "run", side_effect=replies),
                    patch.object(screenshot.os, "execv") as launch,
                ):
                    self.assertIsNone(screenshot.capture("region", edit=True))
                    launch.assert_not_called()

    def test_missing_editor_stops_before_capture(self):
        with (
            patch.object(
                screenshot.shutil,
                "which",
                side_effect=lambda name: "hyprshot" if name == "hyprshot" else None,
            ),
            patch.object(screenshot.subprocess, "run") as run,
            patch.object(screenshot.time, "sleep") as sleep,
        ):
            with self.assertRaisesRegex(ValueError, "Install satty"):
                screenshot.capture("output", edit=True, delay=5)
            run.assert_not_called()
            sleep.assert_not_called()


class RecorderTests(unittest.TestCase):
    def test_native_app_launch_keeps_shell_surfaces_open(self):
        events = []
        with (
            patch.object(recorder.shutil, "which", return_value="/usr/bin/kooha"),
            patch.object(recorder.os, "execv", side_effect=lambda *args: events.append(args)),
        ):
            recorder.record()
        self.assertEqual(events, [("/usr/bin/kooha", ["/usr/bin/kooha"])])

    def test_missing_recorder_leaves_shell_open(self):
        with patch.object(recorder.shutil, "which", return_value=None):
            with self.assertRaisesRegex(ValueError, "Install kooha"):
                recorder.record()


if __name__ == "__main__":
    unittest.main()
