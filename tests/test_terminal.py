import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from modules.terminal import backend


class TerminalConfigTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.environment = patch.dict(os.environ, {"XDG_CONFIG_HOME": self.directory.name})
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.path = Path(self.directory.name) / "zephyrus-shell/terminal.json"
        self.path.parent.mkdir()

    def test_missing_config_creates_empty_commands(self):
        result = backend.configuration()
        self.assertEqual(result, {"path": str(self.path), "commands": []})
        self.assertEqual(json.loads(self.path.read_text()), {"commands": []})

    def test_reload_preserves_shell_syntax_and_does_not_execute(self):
        marker = Path(self.directory.name) / "must-not-exist"
        command = f"printf '%s\\n' '$HOME'; touch '{marker}'"
        self.path.write_text(json.dumps({"commands": [{"name": " Example ", "command": command}]}))
        self.assertEqual(
            backend.configuration()["commands"], [{"name": "Example", "command": command}]
        )
        self.assertFalse(marker.exists())
        self.path.write_text('{"commands": []}')
        self.assertEqual(backend.configuration()["commands"], [])

    def test_bad_config_is_not_overwritten(self):
        for raw in (
            "{broken",
            "[]",
            '{"commands":{}}',
            '{"commands":[{"name":"Missing"}]}',
            '{"commands":[{"name":"", "command":"pwd"}]}',
        ):
            with self.subTest(raw=raw):
                self.path.write_text(raw)
                with self.assertRaises(ValueError):
                    backend.configuration()
                self.assertEqual(self.path.read_text(), raw)

    def test_control_characters_are_rejected(self):
        for control in ("\0", "\x1b", "\r"):
            self.path.write_text(
                json.dumps({"commands": [{"name": "Invalid", "command": "pwd" + control}]})
            )
            with self.assertRaisesRegex(ValueError, "control"):
                backend.configuration()
