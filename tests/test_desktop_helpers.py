import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


clipboard = module("clipboard_backend", "plugins/clipboard/backend.py")
screenshot = module("desktop_screenshot", "scripts/screenshot.py")


class ClipboardTests(unittest.TestCase):
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
            replies = [subprocess.CompletedProcess([], 0, directory + "\n", ""), subprocess.CompletedProcess([], 0)]
            with patch.object(screenshot.shutil, "which", return_value="/usr/bin/hyprshot"), patch.object(screenshot.subprocess, "run", side_effect=replies) as run:
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


if __name__ == "__main__":
    unittest.main()
