import json
from pathlib import Path
import tempfile
import unittest

from scripts import open_browser


class BrowserTests(unittest.TestCase):
    def test_command_selection_and_literal_url_argument(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'browser.json'
            url = 'https://example.org/?q=$(touch /tmp/unwanted)'
            self.assertEqual(open_browser.browser_argv('games', url, path), ['xdg-open', url])
            path.write_text(json.dumps({'command':'firefox --kiosk',
                                        'modules':{'games':['/tmp/game-browser','--private']}}))
            self.assertEqual(open_browser.browser_argv('movies', url, path),
                             ['firefox', '--kiosk', url])
            self.assertEqual(open_browser.browser_argv('games', url, path),
                             ['/tmp/game-browser', '--private', url])
            self.assertEqual(open_browser.browser_argv('games', url, path, override='chromium --app'),
                             ['chromium', '--app', url])
