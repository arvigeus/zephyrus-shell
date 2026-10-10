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
        with patch.object(clipboard, "command", side_effect=[data, b""]) as command:
            self.assertTrue(clipboard.run({"op": "copy", "entry_id": "42"})["copied"])
        self.assertEqual(command.call_args_list[0].args, ("cliphist", "decode"))
        self.assertEqual(command.call_args_list[0].kwargs["data"], b"42\t\n")
        self.assertEqual(command.call_args_list[1].args, ("wl-copy", "--type", "image/png"))
        self.assertEqual(command.call_args_list[1].kwargs["data"], data)

    def test_copy_worker_settles_while_background_clipboard_owner_is_alive(self):
        data = b"\x89PNG\r\n\x1a\n\x00binary-image"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cliphist = root / "cliphist"
            cliphist.write_text(
                "#!/usr/bin/env python3\n"
                "import sys\n"
                "if sys.argv[1] == 'decode':\n"
                "    assert sys.stdin.buffer.read() == b'42\\t\\n'\n"
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
                for op in ("delete", "copy", "thumbnail"):
                    with self.assertRaises(ValueError):
                        clipboard.run({"op": op, "entry_id": identifier})
            command.assert_not_called()

    def test_utf8_text_and_unknown_binary_are_not_confused(self):
        self.assertEqual(clipboard.mime_type("こんにちは".encode()), "text/plain;charset=utf-8")
        self.assertEqual(clipboard.mime_type(b"\xff\x00other"), "application/octet-stream")

    def test_missing_tools_return_actionable_setup_state(self):
        with patch.object(clipboard.shutil, "which", return_value=None):
            with self.assertRaisesRegex(ValueError, "desktop utilities"):
                clipboard.run({"op": "list"})
