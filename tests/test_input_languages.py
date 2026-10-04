"""Load the real keyboard Lua module without a compositor or input daemon."""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("lua"), "Lua interpreter is not installed")
class InputLanguagesTest(unittest.TestCase):
    def test_installed_defaults_and_session_override_order(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / "config/zephyrus-shell"
            config.mkdir(parents=True)
            (config / "input-method.lua").write_text(
                'hl.config({input={kb_layout="us,bg",kb_variant=",phonetic"}})\n'
            )
            runtime = root / "runtime/zephyrus-shell"
            runtime.mkdir(parents=True)
            (runtime / "input-language-session.lua").write_text(
                'hl.config({input={kb_layout="us"}})\n'
            )
            env = dict(
                os.environ,
                XDG_CONFIG_HOME=str(root / "config"),
                XDG_RUNTIME_DIR=str(root / "runtime"),
                HYPRLAND_INSTANCE_SIGNATURE="session",
            )
            script = "hl={config=function(c) print(c.input.kb_layout) end}; dofile(arg[1])"
            command = ["lua", "-", str(ROOT / "hyprland/input-method.lua")]
            result = subprocess.run(command, input=script, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), ["us,bg", "us,bg", "us"])
            env["HYPRLAND_INSTANCE_SIGNATURE"] = "new-session"
            result = subprocess.run(command, input=script, env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), ["us,bg", "us,bg"])
