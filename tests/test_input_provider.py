"""Exercise the public input provider command and standalone XKB fallback."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class InputProviderTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / "config/zephyrus-shell"
        self.config.mkdir(parents=True)
        self.env = dict(os.environ, XDG_CONFIG_HOME=str(self.root / "config"))
        self.tools = self.root / "bin"
        self.tools.mkdir()
        self.provider = self.tools / "input provider"
        self.provider.write_text(
            "#!/usr/bin/env python3\nimport json,sys\n"
            "print(json.dumps({'available':True,'secondary':'vi','language':'vi','args':sys.argv[1:]}))\n"
        )
        self.provider.chmod(0o755)
        # No actual compositor or host-installed provider can be contacted.
        (self.tools / "python3").symlink_to(sys.executable)
        (self.tools / "timeout").write_text('#!/bin/sh\nshift 2\nexec "$@"\n')
        (self.tools / "timeout").chmod(0o755)
        (self.tools / "hyprctl").write_text(
            "#!/usr/bin/env python3\nimport json,sys\n"
            "print(json.dumps({'keyboards':[{'main':True,'layout':'us,bg','active_layout_index':0}]}))\n"
        )
        (self.tools / "hyprctl").chmod(0o755)
        self.env["PATH"] = str(self.tools)

    def configure(self, command):
        (self.config / "input-language.json").write_text(json.dumps({"command": command}))

    def invoke(self, *args):
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts/input-language.py"), *args],
            env=self.env,
            capture_output=True,
            text=True,
        )
        return result.returncode, json.loads(result.stdout)

    def test_provider_is_only_used_when_configured(self):
        code, result = self.invoke("status")
        self.assertEqual(code, 0)
        self.assertIn("keyboards", result)
        self.configure([str(self.provider)])
        code, result = self.invoke("status", "laptop")
        self.assertEqual(code, 0)
        self.assertEqual(result["args"], ["status", "laptop"])
        self.assertTrue(result["available"])

    def test_command_arguments_remain_literal(self):
        self.configure([str(self.provider), "literal $(command) with spaces"])
        code, result = self.invoke("select", "vi")
        self.assertEqual(code, 0)
        self.assertEqual(result["args"], ["literal $(command) with spaces", "select", "vi"])

    def test_missing_provider_keeps_xkb_and_hides_vietnamese(self):
        self.configure(["missing-input-provider"])
        code, result = self.invoke("select", "bg")
        self.assertEqual(code, 0)
        self.assertIn("keyboards", result)
        code, result = self.invoke("select", "vi")
        self.assertEqual(code, 1)
        self.assertFalse(result["available"])

    def test_bad_config_reports_an_error_without_launching_provider(self):
        for value in ({"command": "shell text"}, {"command": []}, {"command": [42]}, None):
            with self.subTest(value=value):
                (self.config / "input-language.json").write_text(json.dumps(value))
                code, result = self.invoke("status")
                self.assertEqual(code, 1)
                self.assertFalse(result["available"])
                self.assertIn("array", result["error"])

    def test_invalid_selection_does_not_reach_provider(self):
        self.configure([str(self.provider)])
        code, result = self.invoke("select", "other")
        self.assertEqual(code, 1)
        self.assertIn("selection", result["error"])
