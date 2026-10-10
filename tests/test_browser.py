import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from scripts import open_browser


class BrowserTests(unittest.TestCase):
    def test_command_selection_and_literal_url_argument(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "browser.json"
            url = "https://example.org/?q=$(touch /tmp/unwanted)"
            self.assertEqual(open_browser.browser_argv("games", url, path), ["xdg-open", url])
            path.write_text(
                json.dumps(
                    {
                        "command": "firefox --kiosk",
                        "modules": {"games": ["/tmp/game-browser", "--private"]},
                    }
                )
            )
            self.assertEqual(
                open_browser.browser_argv("movies", url, path), ["firefox", "--kiosk", url]
            )
            self.assertEqual(
                open_browser.browser_argv("games", url, path),
                ["/tmp/game-browser", "--private", url],
            )


class ChromiumLauncherTests(unittest.TestCase):
    launcher = Path(__file__).resolve().parents[1] / "scripts/browser-chromium.sh"

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(
            os.environ,
            XDG_CONFIG_HOME=str(self.root / "config"),
            XDG_CACHE_HOME=str(self.root / "cache"),
        )
        self.env.pop("ZEPHYRUS_ADBLOCK_DIR", None)
        self.extension_base = (
            self.root / "config/chromium/Default/Extensions/ddkjiahejlhfcafbddmgiahcphecmpfh"
        )
        for version in ("1.9_0", "1.10_0"):
            extension = self.extension_base / version
            extension.mkdir(parents=True)
            (extension / "manifest.json").write_text("{}")
        (self.extension_base / "99.0_0").mkdir()  # Ignore incomplete installs.
        self.log = self.root / "arguments.json"
        browser = self.root / "fake chromium"
        browser.write_text("""#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
profile = Path(next(arg.split('=', 1)[1] for arg in sys.argv if arg.startswith('--user-data-dir=')))
assert profile.is_dir()
assert not list(profile.iterdir())
(profile / 'cookie').write_text('temporary')
Path(os.environ['BROWSER_TEST_LOG']).write_text(json.dumps(sys.argv[1:]))
sys.exit(int(os.environ.get('BROWSER_TEST_EXIT', 0)))
""")
        browser.chmod(0o700)
        self.env.update(ZEPHYRUS_CHROMIUM=str(browser), BROWSER_TEST_LOG=str(self.log))

    def run_launcher(self, *args):
        return subprocess.run(
            [str(self.launcher), *args], env=self.env, capture_output=True, text=True, timeout=5
        )

    def test_fresh_profile_literal_url_newest_extension_and_cleanup(self):
        url = "https://example.org/?q=$(touch /tmp/unwanted)&name=two words"
        profiles = []
        for _ in range(2):
            result = self.run_launcher(url)
            self.assertEqual(result.returncode, 0, result.stderr)
            args = json.loads(self.log.read_text())
            profile = Path(args[0].split("=", 1)[1])
            profiles.append(profile)
            self.assertFalse(profile.exists())
            self.assertEqual(
                args[1:],
                [
                    "--load-extension=" + str(self.extension_base / "1.10_0"),
                    "--disable-extensions-except=" + str(self.extension_base / "1.10_0"),
                    "--app=" + url,
                    "--start-fullscreen",
                    "--no-first-run",
                ],
            )
        self.assertNotEqual(*profiles)

    def test_extension_override_and_cleanup_on_browser_failure(self):
        extension = self.root / "custom extension"
        extension.mkdir()
        (extension / "manifest.json").write_text("{}")
        self.env.update(ZEPHYRUS_ADBLOCK_DIR=str(extension), BROWSER_TEST_EXIT="7")
        result = self.run_launcher("https://example.org")
        self.assertEqual(result.returncode, 7, result.stderr)
        args = json.loads(self.log.read_text())
        self.assertIn("--load-extension=" + str(extension), args)
        self.assertFalse(Path(args[0].split("=", 1)[1]).exists())

    def test_invalid_arguments_or_missing_extension_do_not_launch(self):
        for args in ((), ("",), ("one", "two")):
            self.assertEqual(self.run_launcher(*args).returncode, 2)
        self.env["ZEPHYRUS_ADBLOCK_DIR"] = str(self.root / "missing")
        result = self.run_launcher("https://example.org")
        self.assertEqual(result.returncode, 1)
        self.assertIn("uBlock Origin Lite not found", result.stderr)
        self.assertFalse(self.log.exists())
        self.assertFalse((self.root / "cache").exists())
