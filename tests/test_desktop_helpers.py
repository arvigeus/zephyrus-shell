import importlib.util
import json
import os
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


clipboard = module("clipboard_backend", "clipboard/backend.py")
screenshot = module("desktop_screenshot", "scripts/screenshot.py")
with patch.dict(sys.modules, {"screenshot": screenshot}):
    recorder = module("desktop_recorder", "scripts/record-screen.py")


class ClipboardTests(unittest.TestCase):
    def test_fresh_database_is_empty_and_real_errors_are_reported(self):
        for diagnostic, empty in (
            (b"opening db: please store something first\n", True),
            (b"opening db: permission denied\n", False),
        ):

            def execute(args, diagnostic=diagnostic, **kwargs):
                kwargs["stderr"].write(diagnostic)
                return subprocess.CompletedProcess(args, 1, b"", None)

            with (
                patch.object(clipboard.shutil, "which", return_value="/usr/bin/cliphist"),
                patch.object(
                    clipboard.subprocess,
                    "run",
                    side_effect=execute,
                ),
            ):
                if empty:
                    self.assertEqual(clipboard.run({"op": "list"}), {"entries": []})
                else:
                    with self.assertRaisesRegex(ValueError, "permission denied"):
                        clipboard.run({"op": "list"})

    def test_list_ignores_invalid_rows_and_preserves_ids_and_previews(self):
        with patch.object(
            clipboard,
            "command",
            return_value=b"42\tHello\tWorld\n41\t[[ binary data: 12 KiB png ]]\ninvalid\n",
        ):
            entries = clipboard.run({"op": "list"})["entries"]
        self.assertEqual(
            entries,
            [
                {
                    "id": "42",
                    "preview": "Hello\tWorld",
                    "label": "Hello\tWorld",
                    "binary": False,
                    "image": False,
                },
                {
                    "id": "41",
                    "preview": "[[ binary data: 12 KiB png ]]",
                    "label": "Image",
                    "binary": True,
                    "image": True,
                },
            ],
        )

    def test_copy_keeps_binary_bytes_and_advertises_their_mime_type(self):
        data = b"\x89PNG\r\n\x1a\n\x00binary-image"
        with patch.object(
            clipboard, "command", side_effect=[b"42\tFixture\n", data, b""]
        ) as command:
            self.assertTrue(clipboard.run({"op": "copy", "entry_id": "42"})["copied"])
        self.assertEqual(command.call_args_list[1].args, ("cliphist", "decode"))
        self.assertEqual(command.call_args_list[1].kwargs["data"], b"42\tFixture\n")
        self.assertEqual(command.call_args_list[2].args, ("wl-copy", "--type", "image/png"))
        self.assertEqual(command.call_args_list[2].kwargs["data"], data)

    def test_copy_worker_settles_while_background_clipboard_owner_is_alive(self):
        data = b"\x89PNG\r\n\x1a\n\x00binary-image"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cliphist = root / "cliphist"
            cliphist.write_text(
                "#!/usr/bin/env python3\n"
                "import sys\n"
                "if sys.argv[1] == 'list':\n"
                "    sys.stdout.buffer.write(b'42\\tFixture\\n')\n"
                "elif sys.argv[1] == 'decode':\n"
                "    assert sys.stdin.buffer.read() == b'42\\tFixture\\n'\n"
                f"    sys.stdout.buffer.write(bytes.fromhex('{data.hex()}'))\n"
            )
            copy = root / "wl-copy"
            copy.write_text(
                "#!/usr/bin/env python3\n"
                "import os, sys, time\n"
                "from pathlib import Path\n"
                "root = Path(__file__).parent\n"
                "assert sys.argv[1:] == ['--type', 'image/png']\n"
                "(root / 'copied').write_bytes(sys.stdin.buffer.read())\n"
                "if os.fork() == 0:\n"
                "    deadline = time.monotonic() + 5\n"
                "    while not (root / 'release').exists() and time.monotonic() < deadline:\n"
                "        time.sleep(0.01)\n"
                "    os._exit(0)\n"
                "os._exit(0)\n"
            )
            for executable in (cliphist, copy):
                executable.chmod(0o755)
            worker = subprocess.Popen(
                [sys.executable, str(ROOT / "clipboard/backend.py")],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env={**os.environ, "PATH": directory + os.pathsep + os.environ["PATH"]},
            )
            try:
                output, errors = worker.communicate(
                    b'{"id":1,"op":"copy","entry_id":"42"}\n', timeout=2
                )
                self.assertEqual(worker.returncode, 0, errors.decode())
                self.assertEqual(json.loads(output), {"id": 1, "result": {"copied": True}})
                self.assertEqual((root / "copied").read_bytes(), data)
            finally:
                (root / "release").touch()
                if worker.poll() is None:
                    worker.kill()
                worker.communicate(timeout=5)

    def test_copy_failure_preserves_diagnostic(self):
        with patch.object(clipboard.shutil, "which", return_value=sys.executable):
            with self.assertRaisesRegex(ValueError, "Clipboard operation failed: unavailable seat"):
                clipboard.command(
                    "wl-copy",
                    "-c",
                    "import sys; sys.stderr.write('unavailable seat\\n'); sys.exit(1)",
                    data=b"Fixture",
                )

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

            with (
                patch.object(screenshot.shutil, "which", return_value="/usr/bin/hyprshot"),
                patch.object(screenshot.subprocess, "run", side_effect=execute) as run,
            ):
                result = screenshot.capture("output")
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
        ):
            with self.assertRaisesRegex(ValueError, "Install satty"):
                screenshot.capture("region", edit=True)
            run.assert_not_called()


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
