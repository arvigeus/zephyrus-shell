"""Bounded JSON-lines workers with separate read and ordered control lanes.

Replies are always emitted, including superseded requests, so clients can release
callbacks. Mutations are never superseded and execute in arrival order.
"""
from concurrent.futures import ThreadPoolExecutor
import json
import sys
import threading


def serve(handle, *, errors=(ValueError,), latest=(), controls=(), background=(), workers=3,
          stream=None, output=None, capacity=64, scope=None):
    stream, output = stream or sys.stdin, output or sys.stdout
    write_lock = threading.Lock()
    state_lock = threading.Lock()
    newest = {}
    scope = scope or (lambda request: request["op"])
    slots = threading.BoundedSemaphore(capacity)

    def emit(response):
        with write_lock:
            output.write(json.dumps(response, ensure_ascii=False) + "\n")
            output.flush()

    def execute(request):
        try:
            with state_lock:
                superseded = request['op'] in latest and newest.get(scope(request)) != request['id']
            if superseded:
                emit({'id': request['id'], 'error': 'Request superseded.'})
                return
            try:
                response = {'id': request['id'], 'result': handle(request)}
            except errors as error:
                response = {'id': request['id'], 'error': str(error)}
            except Exception:
                response = {'id': request['id'], 'error': 'The request could not be completed. Try again.'}
            emit(response)
        finally:
            slots.release()

    with ThreadPoolExecutor(max_workers=workers, thread_name_prefix='catalogue') as reads, \
         ThreadPoolExecutor(max_workers=1, thread_name_prefix='control') as writes, \
         ThreadPoolExecutor(max_workers=2, thread_name_prefix='artwork') as images:
        for line in stream:
            try:
                request = json.loads(line)
                if not isinstance(request, dict) or not isinstance(request.get('op'), str) or 'id' not in request:
                    raise ValueError()
            except (ValueError, TypeError):
                emit({'id': None, 'error': 'Invalid worker request.'})
                continue
            if not slots.acquire(blocking=False):
                emit({'id': request['id'], 'error': 'Too many pending requests. Try again shortly.'})
                continue
            with state_lock:
                newest[scope(request)] = request['id']
            (writes if request['op'] in controls else images if request['op'] in background else reads).submit(execute, request)
