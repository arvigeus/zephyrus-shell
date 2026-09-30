from email.message import Message
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from pictures import backend as pictures


class WallpaperTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        environment = patch.dict(os.environ, {
            'XDG_CONFIG_HOME': str(self.root / 'config'),
            'XDG_DATA_HOME': str(self.root / 'data'),
        })
        environment.start()
        self.addCleanup(environment.stop)
        self.item = {'provider': 'wallhaven', 'id': 'abc123',
                     'path': 'https://w.wallhaven.cc/full/ab/wallhaven-abc123.png'}

    def cached_wallpaper(self):
        path = pictures.wallpaper_file(pictures.clean_item(self.item))
        path.write_bytes(b'cached image')
        return path

    def response(self, content=b'image'):
        response = io.BytesIO(content)
        response.headers = Message()
        response.headers['Content-Type'] = 'image/png'
        return response

    def test_set_updates_shell_setting_without_external_services(self):
        path = self.cached_wallpaper()
        with patch.object(pictures, 'apply_wallpaper') as external, \
             patch.object(pictures, 'urlopen') as network:
            result = pictures.run({'op': 'set', 'wallpaper': self.item})
        external.assert_not_called()
        network.assert_not_called()
        self.assertEqual(result['service'], 'Zephyrus Shell')
        setting = self.root / 'config/zephyrus-shell/wallpaper.json'
        self.assertEqual(json.loads(setting.read_text()), {'image': path.as_uri()})
        self.assertEqual(list(setting.parent.glob('.wallpaper-*')), [])

    def test_external_target_preserves_desktop_service_support(self):
        path = self.cached_wallpaper()
        with patch.object(pictures, 'apply_wallpaper', return_value='hyprpaper') as external:
            result = pictures.set_wallpaper({'wallpaper': self.item, 'target': 'desktop'})
        external.assert_called_once_with(path)
        self.assertEqual(result['service'], 'hyprpaper')
        self.assertFalse((self.root / 'config/zephyrus-shell/wallpaper.json').exists())

    def test_failed_setting_write_preserves_previous_wallpaper(self):
        path = self.cached_wallpaper()
        pictures.apply_shell_wallpaper(path)
        setting = self.root / 'config/zephyrus-shell/wallpaper.json'
        before = setting.read_bytes()
        with patch.object(pictures.os, 'replace', side_effect=OSError('write failed')):
            with self.assertRaises(OSError):
                pictures.apply_shell_wallpaper(self.root / 'other image.png')
        self.assertEqual(setting.read_bytes(), before)
        self.assertEqual(list(setting.parent.glob('.wallpaper-*')), [])

    def test_download_saves_original_and_cleans_temporary_file(self):
        item = pictures.clean_item(self.item)
        with patch.object(pictures, 'urlopen', return_value=self.response()) as request:
            path = pictures.download_wallpaper(item)
        self.assertEqual(path.read_bytes(), b'image')
        self.assertEqual(request.call_args.kwargs['timeout'], 10)
        self.assertEqual(list(path.parent.glob('*.download')), [])

    def test_slow_download_expires_even_while_receiving_data(self):
        item = pictures.clean_item(self.item)
        path = pictures.wallpaper_file(item)
        with patch.object(pictures, 'urlopen', return_value=self.response()), \
             patch.object(pictures.time, 'monotonic', side_effect=[0, 1, 61]):
            with self.assertRaisesRegex(ValueError, 'download timed out'):
                pictures.download_wallpaper(item)
        self.assertFalse(path.exists())
        self.assertEqual(list(path.parent.glob('*.download')), [])

    def test_invalid_target_does_not_download(self):
        with patch.object(pictures, 'download_wallpaper') as download:
            with self.assertRaisesRegex(ValueError, 'Unknown wallpaper target'):
                pictures.set_wallpaper({'wallpaper': self.item, 'target': 'invalid'})
        download.assert_not_called()

    def test_random_command_defaults_to_shell_and_can_target_external_desktop(self):
        item = pictures.clean_item(self.item)
        for target in ('shell', 'desktop'):
            argv = ['backend.py', '--random'] + (['--target=desktop'] if target == 'desktop' else [])
            with self.subTest(target=target), patch.object(pictures.sys, 'argv', argv), \
                 patch.object(pictures, 'random_wallpaper', return_value=item), \
                 patch.object(pictures, 'set_wallpaper', return_value={'service': 'test', 'path': '/image'}) as apply, \
                 patch('builtins.print'):
                self.assertEqual(pictures.command_line(), 0)
            apply.assert_called_once_with({'wallpaper': item, 'target': target})

    def test_repeated_wallpapers_update_lock_link_without_copying_image(self):
        first = self.cached_wallpaper()
        pictures.set_wallpaper({'wallpaper': self.item})
        link = self.root / 'config/zephyrus-shell/lock-wallpaper'
        self.assertTrue(link.is_symlink())
        self.assertEqual(link.resolve(), first)
        item = dict(self.item, id='def456')
        second = pictures.wallpaper_file(pictures.clean_item(item))
        second.write_bytes(b'new wallpaper')
        pictures.set_wallpaper({'wallpaper': item})
        self.assertEqual(link.resolve(), second)
        self.assertEqual(list(link.parent.glob('.lock-wallpaper-*')), [])

    def test_external_desktop_also_updates_lock_link(self):
        path = self.cached_wallpaper()
        with patch.object(pictures, 'apply_wallpaper', return_value='hyprpaper'):
            pictures.set_wallpaper({'wallpaper': self.item, 'target': 'desktop'})
        self.assertEqual((self.root / 'config/zephyrus-shell/lock-wallpaper').resolve(), path)
