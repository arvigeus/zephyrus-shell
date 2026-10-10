"""Weather and Nextcloud for the center panel.

Without arguments this is the panel's JSON-lines worker. `backend.py weather` and
`backend.py calendar` print one cached snapshot for the bar and exit.
"""

import fcntl
import json
import os
import sys
import time
from contextlib import contextmanager
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from attention import nextcloud, weather
from services import nextcloud as accounts
from services.storage import atomic_write
from services.worker import serve

CONFIG = (
    Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    / "zephyrus-shell/attention.json"
)
CACHE = (
    Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "zephyrus-shell/weather.json"
)
CLOUD_CACHE = (
    Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "zephyrus-shell/nextcloud.json"
)
CLOUD_CACHE_AGE = 15 * 60
CLOUD_RETRY_AGE = 5 * 60


def configuration():
    try:
        data = json.loads(CONFIG.read_text())
    except FileNotFoundError:
        return {}
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError("attention.json could not be read. Check its JSON syntax.") from error
    if not isinstance(data, dict):
        raise ValueError("attention.json must contain a JSON object.")
    return data


@contextmanager
def cloud_cache_lock():
    """Short publication lock shared by the panel and one-shot bar reader."""
    CLOUD_CACHE.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(CLOUD_CACHE.with_suffix(".lock"), os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(descriptor, "r+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield lock


def cloud_revision():
    with cloud_cache_lock() as lock:
        return lock.read()


def invalidate_cloud_cache(clear=True):
    with cloud_cache_lock() as lock:
        revision = int(lock.read() or "0") + 1
        lock.seek(0)
        lock.truncate()
        lock.write(str(revision))
        lock.flush()
        if clear:
            CLOUD_CACHE.unlink(missing_ok=True)


@contextmanager
def cloud_mutation():
    # Fence both reads started before the write and reads started during it.
    # A failed write retains the last good offline snapshot.
    invalidate_cloud_cache(clear=False)
    succeeded = False
    try:
        yield
        succeeded = True
    finally:
        invalidate_cloud_cache(clear=succeeded)


def save_cloud_cache(data, revision):
    with cloud_cache_lock() as lock:
        if lock.read() != revision:
            return False
        atomic_write(CLOUD_CACHE, json.dumps(data))
        return True


def cloud_snapshot(cloud, start, end, refresh=False):
    key = [
        2,
        cloud.get("url"),
        cloud.get("username"),
        cloud.get("calendars"),
        cloud.get("task_lists"),
        start,
        end,
    ]
    revision = cloud_revision()
    now = time.time()
    cached = None
    try:
        cached = json.loads(CLOUD_CACHE.read_text())
        if (
            not isinstance(cached, dict)
            or cached.get("key") != key
            or not isinstance(cached.get("result"), dict)
            or any(
                not isinstance(cached.get(field, 0), (int, float))
                for field in ("fetched_at", "attempted_at")
            )
            or any(
                not isinstance(cached["result"].get(field), list)
                for field in ("events", "tasks", "calendars")
            )
        ):
            cached = None
    except (OSError, ValueError, AttributeError):
        cached = None
    if cached and not refresh:
        stale = now - cached.get("fetched_at", 0) >= CLOUD_CACHE_AGE
        refresh_due = stale and now - cached.get("attempted_at", 0) >= CLOUD_RETRY_AGE
        return {**cached["result"], "stale": stale, "refresh_due": refresh_due}
    try:
        result = nextcloud.snapshot(cloud, start=start, end=end)
    except nextcloud.NextcloudError:
        if cached:
            cached["attempted_at"] = now
            save_cloud_cache(cached, revision)
            return {**cached["result"], "stale": True, "refresh_due": False}
        raise
    data = {"state": "ready", **result}
    published = save_cloud_cache(
        {"key": key, "fetched_at": now, "attempted_at": now, "result": data}, revision
    )
    if not published:
        raise ValueError("Calendar changed during refresh. Refresh again.")
    return {**data, "stale": False, "refresh_due": False}


def handle(request):
    config = configuration()
    op = request["op"]
    if op == "weather":
        return weather.fetch(config.get("weather", {}), CACHE)
    account = accounts.load_account()
    options = config.get("calendar", {})
    if not isinstance(options, dict):
        raise ValueError("Calendar selection must be an object in attention.json.")
    cloud = {
        **(account or {}),
        **{key: options[key] for key in ("calendars", "task_lists") if key in options},
    }
    if op == "nextcloud":
        empty = {"events": [], "tasks": [], "calendars": [], "task_count": 0}
        if not account:
            return {"state": "unconfigured", **empty}
        try:
            accounts.credential(cloud)
        except accounts.CredentialMissing:
            return {"state": "needs_password", **empty}
        return cloud_snapshot(
            cloud, request.get("start"), request.get("end"), request.get("refresh", False)
        )
    if op == "complete_task":
        with cloud_mutation():
            nextcloud.Client(cloud).complete_task(request.get("task", {}))
        return {"completed": True}
    if op == "save_item":
        with cloud_mutation():
            result = nextcloud.Client(cloud).save_item(
                cloud, request.get("kind"), request.get("entry")
            )
        return result
    raise ValueError("Unknown attention request.")


def summary(kind):
    """One-shot snapshot for the bar; the calendar covers the current month."""
    try:
        if kind == "weather":
            return {"forecast": handle({"op": "weather"})}
        start = date.today().replace(day=1)
        end = date(start.year + (start.month == 12), start.month % 12 + 1, 1)
        request = {"op": "nextcloud", "start": start.isoformat(), "end": end.isoformat()}
        result = handle(request)
        if result.get("refresh_due"):
            result = handle({**request, "refresh": True})
        return {"cloud": result}
    except (ValueError, OSError) as error:
        return {"error": str(error)}


if __name__ == "__main__":
    if len(sys.argv) > 1:
        print(json.dumps(summary(sys.argv[1])))
    else:
        serve(
            handle,
            errors=(ValueError, OSError),
            latest=("nextcloud",),
            controls=("complete_task", "save_item"),
        )
