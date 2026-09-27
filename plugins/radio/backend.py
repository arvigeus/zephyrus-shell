"""Small line-based Radio Browser API worker for the Radio module."""
import json
import hashlib
import os
import random
import re
import shutil
import socket
import sys
import threading
import tempfile
import uuid
from functools import lru_cache
from itertools import product
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, quote, urlsplit
from urllib.request import Request, urlopen
from concurrent.futures import ThreadPoolExecutor


PAGE_SIZE = 100
USER_AGENT = "ZephyrusShell/1.0 (Radio module)"
browse_sessions = {}
genre_variants = {}
output_lock = threading.Lock()
browse_lock = threading.Lock()
FAVICON_MAX_BYTES = 1024 * 1024

GENRE_SYNONYMS = {
    "rocknroll": "rock and roll",
    "rock n roll": "rock and roll",
    "rock and roll": "rock and roll",
    "hiphop": "hip hop",
    "r and b": "r&b",
    "r n b": "r&b",
    "rnb": "r&b",
    "rhythm and blues": "r&b",
    "drum n bass": "drum and bass",
    "drum and bass": "drum and bass",
    "dnb": "drum and bass",
    "lofi": "lo fi",
    "kpop": "k pop",
    "jpop": "j pop",
    "edm": "electronic dance music",
}
GENRE_LABELS = {
    "rock and roll": "Rock & Roll",
    "hip hop": "Hip-Hop",
    "r&b": "R&B",
    "drum and bass": "Drum and Bass",
    "lo fi": "Lo-Fi",
    "k pop": "K-Pop",
    "j pop": "J-Pop",
    "electronic dance music": "EDM",
}


class RadioError(Exception):
    pass


@lru_cache(maxsize=1)
def api_hosts():
    """Resolve the Radio Browser mirror pool and randomize the available mirrors."""
    hosts = set()
    try:
        addresses = socket.getaddrinfo("all.api.radio-browser.info", 443, type=socket.SOCK_STREAM)
        for address in addresses:
            try:
                hostname = socket.gethostbyaddr(address[4][0])[0].rstrip(".").lower()
            except (OSError, socket.herror):
                continue
            if hostname.endswith(".api.radio-browser.info") and hostname != "all.api.radio-browser.info":
                hosts.add(hostname)
    except OSError:
        pass
    choices = list(hosts)
    random.shuffle(choices)
    # The pool name remains a DNS-backed fallback if reverse lookup is unavailable.
    choices.append("all.api.radio-browser.info")
    return choices


def api_get(path, params=None):
    query = "?" + urlencode(params) if params else ""
    last_error = None
    for host in api_hosts()[:3]:
        request = Request(
            "https://" + host + path + query,
            headers={"User-Agent": USER_AGENT, "Accept": "application/json"},
        )
        try:
            with urlopen(request, timeout=8) as response:
                payload = response.read(8 * 1024 * 1024 + 1)
                if len(payload) > 8 * 1024 * 1024:
                    raise RadioError("Radio Browser returned too much data.")
                return json.loads(payload.decode("utf-8"))
        except (HTTPError, URLError, TimeoutError, OSError, ValueError) as error:
            last_error = error
    raise RadioError("Radio Browser is unavailable: " + (str(last_error) if last_error else "no API mirrors were found."))


def station_record(raw):
    if not isinstance(raw, dict):
        return None
    station_uuid = str(raw.get("stationuuid") or "").strip()
    name = str(raw.get("name") or "").strip()
    if not station_uuid or not name:
        return None
    return {
        "stationuuid": station_uuid,
        "name": name,
        "country": str(raw.get("country") or "").strip(),
        "countrycode": str(raw.get("countrycode") or "").strip().upper(),
        "tags": str(raw.get("tags") or "").strip(),
        "favicon": str(raw.get("favicon") or "").strip(),
        "homepage": str(raw.get("homepage") or "").strip(),
        "url": str(raw.get("url") or "").strip(),
        "url_resolved": str(raw.get("url_resolved") or "").strip(),
        "language": str(raw.get("language") or "").strip(),
        "codec": str(raw.get("codec") or "").strip(),
        "bitrate": safe_int(raw.get("bitrate")),
        "clickcount": safe_int(raw.get("clickcount")),
    }


def safe_int(value):
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def list_countries():
    rows = api_get("/json/countries", {"order": "name", "hidebroken": "true", "limit": 1000})
    if not isinstance(rows, list):
        raise RadioError("Radio Browser returned an invalid country list.")
    return [
        {"name": str(row.get("name") or "").strip(), "stationcount": safe_int(row.get("stationcount"))}
        for row in rows if isinstance(row, dict) and str(row.get("name") or "").strip()
    ]


def list_genres():
    rows = api_get("/json/tags", {"order": "stationcount", "reverse": "true", "hidebroken": "true", "limit": 2000})
    if not isinstance(rows, list):
        raise RadioError("Radio Browser returned an invalid genre list.")
    grouped = {}
    for row in rows:
        if not isinstance(row, dict):
            continue
        name = str(row.get("name") or "").strip()
        if not name:
            continue
        key = genre_key(name)
        count = safe_int(row.get("stationcount"))
        group = grouped.setdefault(key, {"stationcount": 0, "variants": []})
        group["stationcount"] = max(group["stationcount"], count)
        if name not in [variant["name"] for variant in group["variants"]]:
            group["variants"].append({"name": name, "stationcount": count})

    result = []
    genre_variants.clear()
    for key, group in grouped.items():
        variants = sorted(group["variants"], key=lambda item: (-item["stationcount"], item["name"].casefold()))
        label = GENRE_LABELS.get(key, variants[0]["name"])
        genre_variants[label] = [item["name"] for item in variants]
        result.append({"name": label, "stationcount": group["stationcount"], "variants": genre_variants[label]})
    return sorted(result, key=lambda item: (-item["stationcount"], item["name"].casefold()))


def genre_key(name):
    value = name.casefold().replace("&", " and ").replace("’", "'").replace("‘", "'")
    value = re.sub(r"['`\"]", "", value)
    value = re.sub(r"[^a-z0-9]+", " ", value).strip()
    value = re.sub(r"\s+", " ", value)
    return GENRE_SYNONYMS.get(value, value)


def station_search(query, country, offset, tags):
    params = {
        "order": "clickcount",
        "reverse": "true",
        "hidebroken": "true",
        "limit": PAGE_SIZE,
        "offset": offset,
    }
    if query:
        params["name"] = query
    if country:
        params["country"] = country
        params["countryExact"] = "true"
    if tags:
        params["tagList"] = ",".join(tags)

    rows = api_get("/json/stations/search", params)
    if not isinstance(rows, list):
        raise RadioError("Radio Browser returned an invalid station list.")
    items = [station for row in rows if (station := station_record(row)) is not None]
    return {"items": items, "nextOffset": offset + PAGE_SIZE if len(rows) == PAGE_SIZE else -1}


def browse_union(query, country, tag_filters, offset):
    key = json.dumps([query, country, tag_filters], ensure_ascii=False)
    session = None if offset == 0 else browse_sessions.get(key)
    if session is None:
        if offset != 0:
            raise RadioError("The genre result page expired. Search again to continue.")
        session = {
            "streams": [{"tags": tags, "offset": 0, "items": [], "cursor": 0, "done": False} for tags in tag_filters],
            "seen": set(),
            "returned": 0,
        }
        browse_sessions[key] = session
        while len(browse_sessions) > 8:
            del browse_sessions[next(iter(browse_sessions))]
    elif offset != session["returned"]:
        raise RadioError("The genre result page expired. Search again to continue.")

    def stream_has_item(stream):
        while stream["cursor"] >= len(stream["items"]) and not stream["done"]:
            result = station_search(query, country, stream["offset"], stream["tags"])
            stream["items"] = result["items"]
            stream["cursor"] = 0
            stream["done"] = result["nextOffset"] < 0
            if not stream["done"]:
                stream["offset"] = result["nextOffset"]
            if not stream["items"] and stream["done"]:
                return False
        return stream["cursor"] < len(stream["items"])

    items = []
    while len(items) < PAGE_SIZE:
        best_stream = None
        best_station = None
        for stream in session["streams"]:
            if not stream_has_item(stream):
                continue
            candidate = stream["items"][stream["cursor"]]
            if best_station is None or candidate["clickcount"] > best_station["clickcount"]:
                best_stream = stream
                best_station = candidate
        if best_station is None:
            break
        best_stream["cursor"] += 1
        if best_station["stationuuid"] in session["seen"]:
            continue
        session["seen"].add(best_station["stationuuid"])
        items.append(best_station)

    session["returned"] += len(items)
    has_more = any(stream["cursor"] < len(stream["items"]) or not stream["done"] for stream in session["streams"])
    return {"items": items, "nextOffset": session["returned"] if has_more else -1}


def browse(args):
    query = str(args.get("query") or "").strip()
    country = str(args.get("country") or "").strip()
    tags = args.get("tags") or []
    if not isinstance(tags, list):
        tags = []
    tags = list(dict.fromkeys(str(tag).strip() for tag in tags if str(tag).strip()))
    try:
        offset = max(0, int(args.get("offset") or 0))
    except (TypeError, ValueError):
        offset = 0

    if not tags:
        return station_search(query, country, offset, [])

    if not genre_variants:
        list_genres()
    groups = [genre_variants.get(tag, [tag]) for tag in tags]
    tag_filters = [list(combo) for combo in product(*groups)]
    if len(tag_filters) > 32:
        raise RadioError("Choose fewer genres to search their spelling variations.")
    if len(tag_filters) == 1:
        return station_search(query, country, offset, tag_filters[0])
    return browse_union(query, country, tag_filters, offset)


def play(args):
    station_uuid = str(args.get("stationuuid") or "").strip()
    try:
        station_uuid = str(uuid.UUID(station_uuid))
    except (ValueError, AttributeError):
        raise RadioError("The selected station has an invalid ID.")

    result = api_get("/json/url/" + quote(station_uuid, safe=""))
    stream_url = str(result.get("url") or "").strip() if isinstance(result, dict) else ""
    match = re.match(r"^https?://", stream_url, re.IGNORECASE)
    if not match:
        raise RadioError("Radio Browser did not return a playable HTTP stream.")

    mpv = shutil.which("mpv")
    ffplay = shutil.which("ffplay")
    ipc_path = ""
    if mpv:
        try:
            ipc_path = str(metadata_socket_dir() / ("mpv-" + uuid.uuid4().hex[:16] + ".sock"))
        except OSError:
            pass
        command = [mpv, "--no-video", "--really-quiet"]
        if ipc_path:
            command.append("--input-ipc-server=" + ipc_path)
        command.extend(["--", stream_url])
    elif ffplay:
        command = [ffplay, "-nodisp", "-loglevel", "error", "-autoexit", stream_url]
    else:
        raise RadioError("Install mpv or ffplay to play radio streams.")
    return {"url": stream_url, "command": command, "ipcPath": ipc_path}


def metadata_socket_dir():
    runtime_root = Path(os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir())
    user_id = str(os.getuid() if hasattr(os, "getuid") else os.getpid())
    directory = runtime_root / ("zs-radio-" + user_id)
    probe_path = directory / ("mpv-" + ("a" * 16) + ".sock")
    if len(os.fsencode(str(probe_path))) >= 100:
        directory = Path(tempfile.gettempdir()) / ("zs-radio-" + user_id)
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        directory.chmod(0o700)
    except OSError:
        pass
    return directory


def valid_metadata_socket(args):
    value = str(args.get("ipcPath") or "").strip()
    if not value:
        return None
    path = Path(value)
    try:
        expected_dir = metadata_socket_dir().resolve()
        if path.parent.resolve() != expected_dir or not re.fullmatch(r"mpv-[a-f0-9]{16}\.sock", path.name):
            return None
    except OSError:
        return None
    return path


def ipc_property(ipc_path, property_name):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(0.35)
    try:
        client.connect(str(ipc_path))
        request = json.dumps({"command": ["get_property", property_name], "request_id": 1}) + "\n"
        client.sendall(request.encode("utf-8"))
        response = bytearray()
        while len(response) < 65536 and b"\n" not in response:
            chunk = client.recv(4096)
            if not chunk:
                break
            response.extend(chunk)
        line = bytes(response).split(b"\n", 1)[0]
        if not line:
            return None
        reply = json.loads(line.decode("utf-8"))
        if reply.get("error") != "success":
            return None
        return reply.get("data")
    except (OSError, ValueError, TypeError):
        return None
    finally:
        client.close()


def metadata_title(metadata):
    if not isinstance(metadata, dict):
        return ""
    normalized = {re.sub(r"[^a-z0-9]", "", str(key).casefold()): value for key, value in metadata.items()}
    title = ""
    for key in ("icytitle", "streamtitle", "nowplaying", "title", "song"):
        value = normalized.get(key)
        if isinstance(value, (str, int, float)) and str(value).strip():
            title = str(value).strip()
            break
    artist = ""
    for key in ("artist", "icyartist", "performer"):
        value = normalized.get(key)
        if isinstance(value, (str, int, float)) and str(value).strip():
            artist = str(value).strip()
            break
    if artist and title and artist.casefold() not in title.casefold():
        return artist + " - " + title
    return title


def read_now_playing(args):
    ipc_path = valid_metadata_socket(args)
    if not ipc_path:
        return {"title": ""}
    title = metadata_title(ipc_property(ipc_path, "metadata"))
    if not title:
        media_title = ipc_property(ipc_path, "media-title")
        if isinstance(media_title, str):
            title = media_title.strip()
    return {"title": title}


def cleanup_metadata(args):
    ipc_path = valid_metadata_socket(args)
    if ipc_path:
        try:
            ipc_path.unlink(missing_ok=True)
        except OSError:
            pass
    return {"cleaned": bool(ipc_path)}


def favorite_path():
    config_root = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return config_root / "zephyrus-shell" / "radio-favorites.json"


def clean_favorite(raw):
    if not isinstance(raw, dict):
        return None
    base = station_record(raw)
    if not base:
        return None
    variants = raw.get("variants") if isinstance(raw.get("variants"), list) else []
    base["variants"] = [station for item in variants if (station := station_record(item)) is not None]
    base["groupKey"] = str(raw.get("groupKey") or "")
    return base


def load_favorites():
    path = favorite_path()
    try:
        values = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    if not isinstance(values, list):
        return []
    return [favorite for raw in values if (favorite := clean_favorite(raw)) is not None]


def save_favorites(args):
    values = args.get("favorites")
    if not isinstance(values, list):
        raise RadioError("Invalid favorites list.")
    favorites = [favorite for raw in values[:1000] if (favorite := clean_favorite(raw)) is not None]
    path = favorite_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(favorites, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)
    return {"saved": len(favorites)}


def image_extension(_content_type, body):
    if body.startswith(b"\x89PNG\r\n\x1a\n"):
        return ".png"
    if body.startswith(b"\xff\xd8\xff"):
        return ".jpg"
    if body.startswith((b"GIF87a", b"GIF89a")):
        return ".gif"
    if body.startswith(b"BM"):
        return ".bmp"
    return ""


def fetch_favicon(args):
    url = str(args.get("url") or "").strip()
    parsed = urlsplit(url)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        return {"source": ""}
    digest = hashlib.sha256(url.encode("utf-8")).hexdigest()
    cache_root = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "zephyrus-shell" / "radio" / "favicons"
    try:
        cache_root.mkdir(parents=True, exist_ok=True)
        for cached in cache_root.glob(digest + ".*"):
            if cached.is_file() and cached.suffix in (".png", ".jpg", ".gif", ".bmp"):
                try:
                    if image_extension("", cached.read_bytes()) == cached.suffix:
                        return {"source": cached.as_uri()}
                except OSError:
                    pass
                cached.unlink(missing_ok=True)
            if cached.is_file() and cached.suffix not in (".tmp",):
                cached.unlink(missing_ok=True)
        request = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "image/*"})
        with urlopen(request, timeout=3) as response:
            content_type = response.headers.get_content_type().lower()
            if not content_type.startswith("image/") or content_type == "image/svg+xml":
                return {"source": ""}
            body = response.read(FAVICON_MAX_BYTES + 1)
        if len(body) > FAVICON_MAX_BYTES:
            return {"source": ""}
        extension = image_extension(content_type, body)
        if not extension:
            return {"source": ""}
        cached = cache_root / (digest + extension)
        temporary = cache_root / (digest + ".tmp")
        temporary.write_bytes(body)
        temporary.replace(cached)
        return {"source": cached.as_uri()}
    except (HTTPError, URLError, TimeoutError, OSError, ValueError):
        return {"source": ""}


def handle(request):
    op = request.get("op")
    args = request if isinstance(request, dict) else {}
    if op == "countries":
        return list_countries()
    if op == "genres":
        return list_genres()
    if op == "browse":
        with browse_lock:
            return browse(args)
    if op == "play":
        return play(args)
    if op == "metadata":
        return read_now_playing(args)
    if op == "metadata-cleanup":
        return cleanup_metadata(args)
    if op == "favorites-load":
        return load_favorites()
    if op == "favorites-save":
        return save_favorites(args)
    if op == "favicon":
        return fetch_favicon(args)
    raise RadioError("Unknown Radio operation.")


def emit(response):
    with output_lock:
        print(json.dumps(response, ensure_ascii=False), flush=True)


def run_request(request):
    try:
        response = {"id": request.get("id"), "result": handle(request)}
    except Exception as error:
        response = {"id": request.get("id"), "error": str(error)}
    emit(response)


def main():
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from services.worker import serve
    serve(handle, errors=(RadioError,), background=("favicon",), latest=("browse", "play"), controls=("metadata", "metadata-cleanup", "favorites-save", "favorites-load"))


if __name__ == "__main__":
    main()
