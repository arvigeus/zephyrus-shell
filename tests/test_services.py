import io
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch

from services.cache import JsonCache
from services.worker import serve


class WorkerTests(unittest.TestCase):
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
