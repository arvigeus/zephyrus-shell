import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


clipboard = module("clipboard_backend", "clipboard/backend.py")
screenshot = module("desktop_screenshot", "scripts/screenshot.py")
with patch.dict(sys.modules, {"screenshot": screenshot}):
    recorder = module("desktop_recorder", "scripts/record-screen.py")


class ClipboardTests(unittest.TestCase):
    def test_fresh_database_is_empty_and_real_errors_are_reported(self):
        for diagnostic, empty in ((b"opening db: please store something first\n", True),
                                  (b"opening db: permission denied\n", False)):
            with patch.object(clipboard.shutil, "which", return_value="/usr/bin/cliphist"), \
                    patch.object(clipboard.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, b"", diagnostic)):
                if empty:
                    self.assertEqual(clipboard.run({"op": "list"}), {"entries": []})
                else:
                    with self.assertRaisesRegex(ValueError, "permission denied"):
                        clipboard.run({"op": "list"})

    def test_list_ignores_invalid_rows_and_preserves_ids_and_previews(self):
        with patch.object(clipboard, "command", return_value=b"42\tHello\tWorld\n41\t[[ binary data: 12 KiB png ]]\ninvalid\n"):
            entries = clipboard.run({"op": "list"})["entries"]
        self.assertEqual(entries, [{"id": "42", "preview": "Hello\tWorld", "binary": False},
                                   {"id": "41", "preview": "[[ binary data: 12 KiB png ]]", "binary": True}])

    def test_copy_keeps_binary_bytes_and_advertises_their_mime_type(self):
        data = b"\x89PNG\r\n\x1a\n\x00binary-image"
        with patch.object(clipboard, "command", side_effect=[b"42\tFixture\n", data, b""]) as command:
            self.assertTrue(clipboard.run({"op": "copy", "entry_id": "42"})["copied"])
        self.assertEqual(command.call_args_list[1].args, ("cliphist", "decode"))
        self.assertEqual(command.call_args_list[1].kwargs["data"], b"42\tFixture\n")
        self.assertEqual(command.call_args_list[2].args, ("wl-copy", "--type", "image/png"))
        self.assertEqual(command.call_args_list[2].kwargs["data"], data)

    def test_invalid_identifier_cannot_trigger_a_command(self):
        with patch.object(clipboard, "command") as command:
            for identifier in ("42\n41", "--help", "", "2;rm", "hello"):
                with self.assertRaises(ValueError):
                    clipboard.run({"op": "delete", "entry_id": identifier})
            command.assert_not_called()

    def test_utf8_text_and_unknown_binary_are_not_confused(self):
        self.assertEqual(clipboard.mime_type("こんにちは".encode()), "text/plain;charset=utf-8")
        self.assertEqual(clipboard.mime_type(b"\xff\x00other"), "application/octet-stream")

    def test_missing_tools_return_actionable_setup_state(self):
        with patch.object(clipboard.shutil, "which", return_value=None):
            with self.assertRaisesRegex(ValueError, "desktop utilities"):
                clipboard.run({"op": "list"})


class ScreenshotTests(unittest.TestCase):
    def test_screen_capture_uses_xdg_pictures_and_active_output(self):
        with tempfile.TemporaryDirectory(prefix="screens with spaces ") as directory:
            def execute(command, **kwargs):
                if command[0] == "xdg-user-dir":
                    return subprocess.CompletedProcess(command, 0, directory + "\n", "")
                (Path(command[4]) / command[6]).write_bytes(b"PNG fixture")
                return subprocess.CompletedProcess(command, 0)
            with patch.object(screenshot.shutil, "which", return_value="/usr/bin/hyprshot"), patch.object(screenshot.subprocess, "run", side_effect=execute) as run:
                result = screenshot.capture("output", dismiss=False)
            command = run.call_args_list[1].args[0]
            self.assertEqual(command[:3], ["/usr/bin/hyprshot", "-m", "output"])
            self.assertEqual(command[-2:], ["-m", "active"])
            self.assertEqual(command[4], str(Path(directory) / "Screenshots"))
            self.assertEqual(result.parent, Path(directory) / "Screenshots")

    def test_overlay_is_released_before_interactive_selection(self):
        replies = [subprocess.CompletedProcess([], 0), subprocess.CompletedProcess([], 1, "", ""), subprocess.CompletedProcess([], 1)]
        with tempfile.TemporaryDirectory() as directory, patch.object(screenshot.Path, "home", return_value=Path(directory)), \
                patch.object(screenshot.shutil, "which", return_value="hyprshot"), \
                patch.object(screenshot.subprocess, "run", side_effect=replies) as run, patch.object(screenshot.time, "sleep") as wait:
            self.assertIsNone(screenshot.capture("region"))
            self.assertEqual(run.call_args_list[0].args[0][-1], "desktop")
            wait.assert_called_once_with(0.35)

    def test_annotation_replaces_helper_and_keeps_paths_as_arguments(self):
        with tempfile.TemporaryDirectory(prefix="edited captures ") as directory:
            def execute(command, **kwargs):
                if command[0] == "xdg-user-dir":
                    return subprocess.CompletedProcess(command, 0, directory + "\n", "")
                (Path(command[4]) / command[6]).write_bytes(b"PNG fixture")
                return subprocess.CompletedProcess(command, 0)
            with patch.object(screenshot.shutil, "which", side_effect=lambda name: "/usr/bin/" + name), \
                    patch.object(screenshot.subprocess, "run", side_effect=execute) as run, \
                    patch.object(screenshot.os, "execv") as launch:
                image = screenshot.capture("window", dismiss=False, edit=True, active=True)
            command = run.call_args_list[1].args[0]
            self.assertIn("active", command)
            self.assertIn("--silent", command)
            self.assertEqual(launch.call_args.args, ("/usr/bin/satty", ["/usr/bin/satty", "--config",
                str(ROOT / "config/satty.toml"), "--filename", str(image), "--output-filename", str(image)]))

    def test_cancelled_capture_never_opens_editor_even_if_helper_exits_zero(self):
        with tempfile.TemporaryDirectory() as directory:
            for status in (0, 1):
                replies = [subprocess.CompletedProcess([], 0, directory + "\n", ""), subprocess.CompletedProcess([], status)]
                with patch.object(screenshot.shutil, "which", side_effect=lambda name: name), \
                        patch.object(screenshot.subprocess, "run", side_effect=replies), patch.object(screenshot.os, "execv") as launch:
                    self.assertIsNone(screenshot.capture("region", dismiss=False, edit=True))
                    launch.assert_not_called()

    def test_missing_editor_does_not_dismiss_shell_or_capture(self):
        with patch.object(screenshot.shutil, "which", side_effect=lambda name: "hyprshot" if name == "hyprshot" else None), \
                patch.object(screenshot.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "Install satty"):
                screenshot.capture("region", edit=True)
            run.assert_not_called()


class RecorderTests(unittest.TestCase):
    def test_native_app_owns_lifetime_after_shell_is_dismissed(self):
        events = []
        with patch.object(recorder.shutil, "which", return_value="/usr/bin/kooha"), \
                patch.object(recorder, "dismiss_shell", side_effect=lambda: events.append("dismiss")), \
                patch.object(recorder.os, "execv", side_effect=lambda *args: events.append(args)):
            recorder.record()
        self.assertEqual(events, ["dismiss", ("/usr/bin/kooha", ["/usr/bin/kooha"])])

    def test_missing_recorder_leaves_shell_open(self):
        with patch.object(recorder.shutil, "which", return_value=None), patch.object(recorder, "dismiss_shell") as dismiss:
            with self.assertRaisesRegex(ValueError, "Install kooha"):
                recorder.record()
            dismiss.assert_not_called()


if __name__ == "__main__":
    unittest.main()
