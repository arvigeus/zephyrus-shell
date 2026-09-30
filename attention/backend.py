"""Weather and Nextcloud worker for the center panel."""

import json
import os
from pathlib import Path
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from attention import nextcloud, weather
from services.worker import serve
from services import nextcloud as accounts


CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "zephyrus-shell/attention.json"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "zephyrus-shell/weather.json"
CLOUD_CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "zephyrus-shell/nextcloud.json"
CLOUD_CACHE_AGE = 15 * 60
CLOUD_RETRY_AGE = 5 * 60


def configuration():
    try:
        data = json.loads(CONFIG.read_text())
    except FileNotFoundError as error:
        raise ValueError("Create attention.json to configure weather and calendar selection.") from error
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError("attention.json could not be read. Check its JSON syntax.") from error
    if not isinstance(data, dict):
        raise ValueError("attention.json must contain a JSON object.")
    return data


def save_cloud_cache(data):
    CLOUD_CACHE.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", dir=CLOUD_CACHE.parent, delete=False) as temporary:
        os.fchmod(temporary.fileno(), 0o600)
        json.dump(data, temporary)
        temporary_path = Path(temporary.name)
    temporary_path.replace(CLOUD_CACHE)


def cloud_snapshot(cloud, start, end, refresh=False):
    key = [2, cloud.get("url"), cloud.get("username"), cloud.get("calendars"), cloud.get("task_lists"), start, end]
    now = time.time()
    cached = None
    try:
        cached = json.loads(CLOUD_CACHE.read_text())
        if cached.get("key") != key:
            cached = None
    except (OSError, ValueError, AttributeError):
        pass
    if cached and not refresh:
        stale = now - cached.get("fetched_at", 0) >= CLOUD_CACHE_AGE
        refresh_due = stale and now - cached.get("attempted_at", 0) >= CLOUD_RETRY_AGE
        return {**cached["result"], "stale": stale, "refresh_due": refresh_due}
    try:
        result = nextcloud.snapshot(cloud, start=start, end=end)
    except nextcloud.NextcloudError:
        if cached:
            cached["attempted_at"] = now
            save_cloud_cache(cached)
            return {**cached["result"], "stale": True, "refresh_due": False}
        raise
    data = {"state": "ready", **result}
    save_cloud_cache({"key": key, "fetched_at": now, "attempted_at": now, "result": data})
    return {**data, "stale": False, "refresh_due": False}


def handle(request):
    config = configuration()
    op = request["op"]
    if op == "weather":
        return weather.fetch(config.get("weather", {}), CACHE)
    account = accounts.load_account()
    options = config.get("calendar", config.get("nextcloud", {}))
    if not isinstance(options, dict):
        raise ValueError("Calendar selection must be an object in attention.json.")
    cloud = {**(account or {}), **{key: options[key] for key in ("calendars", "task_lists") if key in options}}
    if op == "nextcloud":
        if not account:
            return {"state": "unconfigured", "events": [], "tasks": [], "calendars": [], "task_count": 0}
        try:
            accounts.credential(cloud)
        except accounts.CredentialMissing:
            return {"state": "needs_password", "events": [], "tasks": [], "calendars": [], "task_count": 0}
        return cloud_snapshot(cloud, request.get("start"), request.get("end"), request.get("refresh", False))
    if op == "complete_task":
        nextcloud.Client(cloud).complete_task(request.get("task", {}))
        CLOUD_CACHE.unlink(missing_ok=True)
        return {"completed": True}
    if op == "save_item":
        result = nextcloud.Client(cloud).save_item(cloud, request.get("kind"), request.get("entry"))
        CLOUD_CACHE.unlink(missing_ok=True)
        return result
    raise ValueError("Unknown attention request.")


if __name__ == "__main__":
    serve(handle, errors=(ValueError, OSError), latest=("weather", "nextcloud"),
          controls=("complete_task", "save_item"))
