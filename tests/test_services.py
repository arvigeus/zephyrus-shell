import io
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import Mock, patch

from services.cache import JsonCache
from services.worker import serve
from services.mpv import MpvIpc


class WorkerTests(unittest.TestCase):
    def test_concurrent_replies_are_complete_lines(self):
        class InterleavingStream:
            def __init__(self):
                self.parts = []
            def write(self, value):
                midpoint = len(value) // 2
                self.parts.append(value[:midpoint])
                time.sleep(0.001)
                self.parts.append(value[midpoint:])
            def flush(self):
                pass
        output = InterleavingStream()
        requests = [{'id': index, 'op': 'read'} for index in range(24)]
        serve(lambda r: 'x' * 4000, workers=8,
              stream=io.StringIO('\n'.join(map(json.dumps, requests))), output=output)
        replies = [json.loads(line) for line in ''.join(output.parts).splitlines()]
        self.assertEqual(len(replies), 24)
        self.assertEqual({r['id'] for r in replies}, set(range(24)))

    def test_control_lane_remains_responsive_and_mutations_keep_order(self):
        slow_started = threading.Event()
        control_finished = threading.Event()
        order = []
        def handle(request):
            if request['op'] == 'browse':
                slow_started.set()
                if not control_finished.wait(2):
                    raise ValueError('Control blocked behind network')
            else:
                self.assertTrue(slow_started.wait(1))
                order.append(request['id'])
                control_finished.set()
            return request['id']
        requests = [{'id': 1, 'op': 'browse'}, {'id': 2, 'op': 'save'}, {'id': 3, 'op': 'save'}]
        output = io.StringIO()
        serve(handle, controls=('save',), workers=1, stream=io.StringIO('\n'.join(map(json.dumps, requests))), output=output)
        replies = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(order, [2, 3])
        self.assertEqual({r['id'] for r in replies}, {1, 2, 3})
        self.assertFalse(any('error' in r for r in replies))

    def test_every_superseded_request_settles_without_running(self):
        started, release = threading.Event(), threading.Event()
        executed = []
        def requests():
            yield json.dumps({'id': 0, 'op': 'hold'})
            self.assertTrue(started.wait(1))
            for i in range(1, 10):
                yield json.dumps({'id': i, 'op': 'browse'})
            release.set()
        def handle(request):
            if request['op'] == 'hold':
                started.set()
                release.wait(1)
            else:
                executed.append(request['id'])
            return {}
        output = io.StringIO()
        serve(handle, latest=('browse',), workers=1, stream=requests(), output=output)
        replies = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(executed, [9])
        self.assertEqual(len(replies), 10)
        self.assertEqual(len({r['id'] for r in replies}), 10)

    def test_invalid_input_does_not_kill_worker(self):
        output = io.StringIO()
        serve(lambda r: 'ok', stream=io.StringIO('[]\ninvalid\n{"id":1,"op":"init"}\n'), output=output)
        replies = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(len(replies), 3)
        self.assertEqual(next(r for r in replies if r['id'] == 1)['result'], 'ok')


class CacheTests(unittest.TestCase):
    def test_concurrent_identical_reads_make_one_provider_request(self):
        with tempfile.TemporaryDirectory() as root:
            cache = JsonCache('test', root)
            calls = []
            def fetch():
                calls.append(1)
                time.sleep(.03)
                return {'items': [1, 2]}
            with ThreadPoolExecutor(max_workers=8) as pool:
                results = list(pool.map(lambda _: cache.load('same', 60, fetch), range(16)))
            self.assertEqual(len(calls), 1)
            self.assertTrue(all(result == {'items': [1, 2]} for result in results))
            reopened = JsonCache('test', root)
            self.assertEqual(reopened.load('same', 60, lambda: self.fail('Unnecessary provider call')), results[0])

    def test_failure_is_not_cached_and_old_entries_are_evicted(self):
        with tempfile.TemporaryDirectory() as root:
            cache = JsonCache('test', root, limit=2)
            with self.assertRaises(ValueError):
                cache.load('bad', 60, lambda: (_ for _ in ()).throw(ValueError('offline')))
            self.assertEqual(cache.load('bad', 60, lambda: []), [])
            for key in ['a', 'b', 'c']:
                cache.put(key, key)
            self.assertIsNone(cache.get('a', 60))
            self.assertEqual(cache.get('c', 60), 'c')


class PlayerIpcTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.environment = patch.dict('os.environ', {'XDG_RUNTIME_DIR': self.temporary.name})
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.music = MpvIpc('music')
        self.path = self.music.directory() / ('mpv-' + 'a' * 16 + '.sock')

    def test_namespace_validation_and_cleanup_stay_owned(self):
        radio = MpvIpc('radio')
        self.path.touch()
        self.assertIsNone(radio.validate(self.path))
        self.assertFalse(radio.cleanup(self.path))
        self.assertTrue(self.path.exists())
        self.assertIsNone(self.music.validate(self.path.parent / 'arbitrary.sock'))
        self.assertTrue(self.music.cleanup(self.path))
        self.assertFalse(self.path.exists())

    def test_long_runtime_path_falls_back_to_private_short_directory(self):
        with patch.dict('os.environ', {'XDG_RUNTIME_DIR': '/tmp/' + 'long' * 30}), \
             patch('services.mpv.tempfile.gettempdir', return_value=self.temporary.name):
            self.assertEqual(self.music.directory().parent, Path(self.temporary.name))
        self.assertEqual(self.music.directory().stat().st_mode & 0o777, 0o700)

    def test_fragmented_reply_skips_events_and_preserves_false_values(self):
        client = Mock()
        client.recv.side_effect = [b'{"event":"idle"}\n{"request_id":1,',
                                   b'"error":"success","data":false}\n']
        with patch('services.mpv.socket.socket', return_value=client):
            self.assertIs(self.music.property(self.path, 'pause'), False)
        command = json.loads(client.sendall.call_args.args[0])
        self.assertEqual(command, {'request_id': 1, 'command': ['get_property', 'pause']})
        client.close.assert_called_once()

    def test_failures_settle_without_exposing_transport_errors(self):
        for reply in (b'[]\n', b'invalid\n', b'', b'{"request_id":1,"error":"failure"}\n',
                      b'x' * 65536):
            client = Mock()
            chunks = [reply[index:index + 4096] for index in range(0, len(reply), 4096)]
            client.recv.side_effect = chunks + [b'']
            with self.subTest(reply=reply[:40]), patch('services.mpv.socket.socket', return_value=client):
                self.assertFalse(self.music.send(self.path, ['cycle', 'pause']))
                client.close.assert_called_once()

    def test_modules_use_shared_transport_with_separate_players(self):
        from plugins.music import backend as music
        from plugins.radio import backend as radio
        for ipc in (music.player_ipc, radio.player_ipc):
            self.assertIsInstance(ipc, MpvIpc)
        with patch.object(music.player_ipc, 'send', return_value=True) as send:
            self.assertEqual(music.player_command({'ipcPath': str(self.path), 'action': 'volume', 'value': 140}),
                             {'sent': True})
            send.assert_called_once_with(self.path, ['set_property', 'volume', 100])
        with patch.object(radio.player_ipc, 'property') as read:
            self.assertEqual(radio.read_now_playing({'ipcPath': str(self.path)}), {'title': ''})
            read.assert_not_called()
