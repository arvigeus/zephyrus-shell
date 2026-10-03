"""Apple Music catalog and configurable playback providers for mpv."""

import base64
from concurrent.futures import ThreadPoolExecutor
import html
from html.parser import HTMLParser
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path
from threading import Lock
from functools import lru_cache

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from services.cache import JsonCache
from services.mpv import MpvIpc
from media.local import LocalLibrary, safe_name, xdg_dir
from scripts.open_browser import browser_argv


APPLE_API = "https://api.music.apple.com/v1/catalog"
USER_AGENT = (
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)
MAX_RESPONSE_BYTES = 12 * 1024 * 1024
SEARCH_PAGE_SIZE = 25
SEARCH_MAX_LIMIT = 500
_apple_token = ""
_apple_token_expires = 0.0
_apple_token_lock = Lock()
_music_config = None
_artist_artwork_cache = {}
_artist_biography_cache = {}
_artist_biography_lock = Lock()
_lyrics_cooldowns = {}
_lyrics_cooldown_lock = Lock()
_download_processes = set()
_download_processes_lock = Lock()


class MusicError(Exception):
    pass


def music_config():
    global _music_config
    if _music_config is not None:
        return _music_config
    config_root = os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config")
    path = Path(config_root) / "zephyrus-shell" / "music.json"
    try:
        parsed = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        parsed = {}
    except (OSError, ValueError) as error:
        raise MusicError("The Music configuration file could not be read.") from error
    if not isinstance(parsed, dict):
        raise MusicError("The Music configuration must contain a JSON object.")
    storefront = str(parsed.get("storefront") or "us").strip().lower()
    if not re.fullmatch(r"[a-z]{2}", storefront):
        raise MusicError("The Apple Music storefront must be a two-letter country code.")
    default_playlist = parse_playlist_id(parsed.get("default_playlist"))
    providers = parsed.get("providers") or []
    if not isinstance(providers, list):
        raise MusicError("Music providers must be a JSON array.")
    providers = [item for item in providers[:12] if isinstance(item, dict)]
    for provider in providers:
        download = provider.get("download")
        if download is None:
            continue
        if not isinstance(download, dict) or any(
            key in download and not isinstance(download[key], str)
            for key in ("track", "album")
        ):
            raise MusicError("A Music provider download must contain optional track and album URL templates or 'stream'.")
        if any(
            str(download.get(key) or "").strip() == "stream"
            for key in ("track", "album")
        ) and (not provider.get("search_url") or not provider.get("stream_url")):
            raise MusicError("Stream downloads require the provider's search_url and stream_url.")
    lyrics_providers = parsed.get("lyrics_providers")
    if lyrics_providers is None:
        lyrics_providers = [{"name": "LRCLIB", "base_url": "https://lrclib.net/api"}]
    if not isinstance(lyrics_providers, list):
        raise MusicError("Music lyrics_providers must be a JSON array.")
    _music_config = {
        "storefront": storefront,
        "catalog_token": str(parsed.get("catalog_token") or "").strip(),
        "default_playlist": default_playlist,
        "providers": providers,
        "lyrics_providers": [item for item in lyrics_providers[:8] if isinstance(item, dict)],
    }
    return _music_config


def request_body(url, headers=None, timeout=24):
    request_headers = {"Accept": "application/json", "User-Agent": USER_AGENT}
    for name, value in (headers or {}).items():
        name = str(name).strip()
        value = str(value).strip()
        if name and value and not any(char in name + value for char in "\r\n"):
            request_headers[name] = value
    request = urllib.request.Request(url, headers=request_headers)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read(MAX_RESPONSE_BYTES + 1)
            if len(body) > MAX_RESPONSE_BYTES:
                raise MusicError("A configured music endpoint returned an oversized response.")
            return body
    except urllib.error.HTTPError as error:
        if error.code in (502, 503, 504):
            raise MusicError("A configured music endpoint is temporarily unavailable.") from error
        raise MusicError("A configured music endpoint returned HTTP " + str(error.code) + ".") from error
    except urllib.error.URLError as error:
        raise MusicError("Could not connect to a configured music endpoint.") from error
    except TimeoutError as error:
        raise MusicError("A configured music endpoint timed out.") from error


def request_json(url, headers=None):
    try:
        return json.loads(request_body(url, headers).decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        raise MusicError("A configured music endpoint returned unreadable JSON.") from error


class AppleArtistPageParser(HTMLParser):
    """Read Apple's serialized artist page payload without parsing the full DOM."""

    def __init__(self):
        super().__init__()
        self.capturing = False
        self.payload = []

    def handle_starttag(self, tag, attrs):
        if tag.lower() == "script" and dict(attrs).get("id") == "serialized-server-data":
            self.capturing = True

    def handle_endtag(self, tag):
        if tag.lower() == "script" and self.capturing:
            self.capturing = False

    def handle_data(self, data):
        if self.capturing:
            self.payload.append(data)


def clean_artist_biography(value):
    text = html.unescape(str(value or ""))
    text = re.sub(r"<br\s*/?>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"</(?:p|div|h[1-6]|li)\s*>", "\n\n", text, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]*>", "", text)
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n[ \t]*\n(?:[ \t]*\n)+", "\n\n", text)
    return text.strip()


def apple_artist_page_biography(artist_id, artist_url):
    """Fetch the artist's public Apple Music page bio when catalog data omits it."""
    try:
        parsed = urllib.parse.urlsplit(str(artist_url or ""))
    except ValueError:
        return ""
    path_parts = [part for part in parsed.path.split("/") if part]
    if (
        parsed.scheme != "https"
        or parsed.hostname != "music.apple.com"
        or "artist" not in path_parts
        or str(artist_id) not in path_parts
    ):
        return ""

    cache_key = str(artist_id)
    with _artist_biography_lock:
        cached = _artist_biography_cache.get(cache_key)
    if cached:
        return cached

    try:
        page = request_body(
            urllib.parse.urlunsplit(parsed),
            {"Accept": "text/html,application/xhtml+xml"},
            timeout=12,
        ).decode("utf-8", errors="replace")
        parser = AppleArtistPageParser()
        parser.feed(page)
        payload = json.loads("".join(parser.payload))
    except (MusicError, json.JSONDecodeError, ValueError):
        return ""

    biographies = []

    def collect_bios(value):
        if isinstance(value, dict):
            bio = value.get("bio")
            if isinstance(bio, str):
                cleaned = clean_artist_biography(bio)
                if cleaned:
                    biographies.append(cleaned)
            for nested in value.values():
                collect_bios(nested)
        elif isinstance(value, list):
            for nested in value:
                collect_bios(nested)

    collect_bios(payload)
    biography = max(biographies, key=len, default="")
    if biography:
        with _artist_biography_lock:
            _artist_biography_cache[cache_key] = biography
    return biography


def decode_expiration(token):
    try:
        payload = token.split(".")[1]
        payload += "=" * (-len(payload) % 4)
        data = json.loads(base64.urlsafe_b64decode(payload.encode("ascii")))
        return float(data.get("exp") or 0)
    except (IndexError, ValueError, TypeError, UnicodeEncodeError):
        return 0.0


def apple_token():
    global _apple_token, _apple_token_expires
    with _apple_token_lock:
        now = time.time()
        if _apple_token and now < _apple_token_expires:
            return _apple_token
        configured = music_config()["catalog_token"]
        if not configured:
            raise MusicError("Set catalog_token in music.json to browse the Apple Music catalog.")
        if configured.lower().startswith(("https://", "http://")):
            body = request_body(configured).decode("utf-8").strip()
            try:
                data = json.loads(body)
            except json.JSONDecodeError:
                data = body
            if isinstance(data, dict):
                token = str(data.get("dev_token") or data.get("token") or "").strip()
                try:
                    endpoint_ttl = int(data.get("cache_ttl_seconds") or 300)
                except (TypeError, ValueError):
                    endpoint_ttl = 300
            else:
                token = str(data or "").strip()
                endpoint_ttl = 300
        else:
            token = configured.removeprefix("Bearer ").strip()
            endpoint_ttl = 21600
        if not token:
            raise MusicError("The configured catalog token source returned no token.")
        expiration = decode_expiration(token)
        if not expiration:
            ttl = max(60, endpoint_ttl)
            expiration = now + min(ttl, 21600)
        _apple_token = token
        _apple_token_expires = max(now + 30, expiration - 60)
        return token


@lru_cache(maxsize=1)
def catalog_cache():
    return JsonCache("music-catalogue")


def apple_url(path, params=None):
    storefront = music_config()["storefront"]
    url = APPLE_API + "/" + storefront + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    return catalog_cache().load(url, 900, lambda: request_json(url, {"Authorization": "Bearer " + apple_token()}))


def apple_artist_song_cursor(artist_id, cursor):
    """Follow only Apple's cursor for the selected artist's top-songs view."""
    storefront = music_config()["storefront"]
    url = urllib.parse.urljoin(APPLE_API + "/", str(cursor or ""))
    parsed = urllib.parse.urlsplit(url)
    expected = f"/v1/catalog/{storefront}/artists/{artist_id}/view/top-songs"
    if parsed.scheme != "https" or parsed.netloc != "api.music.apple.com" or parsed.path != expected:
        raise MusicError("The catalogue returned an invalid song page.")
    return catalog_cache().load(url, 900, lambda: request_json(url, {"Authorization": "Bearer " + apple_token()}))


def safe_catalog_id(value):
    value = str(value or "").strip()
    if not re.fullmatch(r"[0-9]{1,32}", value):
        raise MusicError("The selected catalog item has an invalid ID.")
    return value


def parse_playlist_id(value):
    if value is None or value == "":
        return ""
    if not isinstance(value, str):
        raise MusicError("default_playlist must be an Apple Music playlist ID or URL.")
    value = value.strip()
    if not value:
        return ""
    if "://" in value:
        parsed = urllib.parse.urlsplit(value)
        if parsed.scheme != "https" or parsed.netloc != "music.apple.com":
            raise MusicError("default_playlist must be an Apple Music playlist ID or URL.")
        parts = parsed.path.strip("/").split("/")
        value = parts[-1] if parts else ""
    if not re.fullmatch(r"pl\.[A-Za-z0-9._-]{1,120}", value):
        raise MusicError("default_playlist must be an Apple Music playlist ID or URL.")
    return value


def safe_playlist_id(value):
    value = str(value or "").strip()
    if not re.fullmatch(r"pl\.[A-Za-z0-9._-]{1,120}", value):
        raise MusicError("The configured Apple Music playlist ID is invalid.")
    return value


def safe_stream_id(value):
    value = str(value or "").strip()
    if not value or len(value) > 256 or any(char in value for char in "\r\n\x00"):
        raise MusicError("The playback provider returned an invalid track ID.")
    return value


def normalized(value):
    value = unicodedata.normalize("NFKD", str(value or ""))
    value = "".join(char for char in value if not unicodedata.combining(char))
    value = value.casefold()
    value = re.sub(r"\b(feat|featuring|ft)\.?\s+.*$", "", value)
    value = re.sub(r"[^a-z0-9]+", " ", value)
    return " ".join(value.split())


def clean_duration(value):
    try:
        duration = float(value or 0)
    except (TypeError, ValueError):
        return 0
    if duration > 1000:
        duration /= 1000
    return max(0, int(round(duration)))


def raw_artists(item):
    names = item.get("artistNames")
    if isinstance(names, list) and names:
        return [str(name).strip() for name in names if str(name).strip()]
    artists = item.get("artists")
    if isinstance(artists, list):
        return [
            str(artist.get("name") or artist.get("displayName") or "").strip()
            for artist in artists
            if isinstance(artist, dict) and (artist.get("name") or artist.get("displayName"))
        ]
    artist = item.get("artistName") or item.get("artist")
    return [str(artist).strip()] if artist else []


def normalize_track(item, source="apple"):
    if not isinstance(item, dict):
        return None
    artists = raw_artists(item)
    artist_records = item.get("artists") if isinstance(item.get("artists"), list) else []
    first_artist = next((value for value in artist_records if isinstance(value, dict)), {})
    track_id = str(item.get("trackId") or item.get("id") or "")
    release_id = str(item.get("releaseId") or item.get("albumId") or "")
    release = item.get("release")
    release_title = release.get("title") if isinstance(release, dict) else ""
    artwork = str(item.get("artwork") or item.get("cover") or "")
    album_title = (
        item.get("albumTitle")
        or item.get("releaseTitle")
        or item.get("albumName")
        or release_title
        or ""
    )
    return {
        "kind": "song",
        "id": track_id or str(item.get("id") or ""),
        "trackId": track_id if source != "apple" else "",
        "source": source,
        "title": str(item.get("title") or item.get("name") or "Unknown Title"),
        "artist": artists[0] if artists else "Unknown Artist",
        "artists": artists,
        "artistIds": [str(value) for value in item.get("artistIds", []) if value],
        "album": str(album_title or "Unknown Album"),
        "albumId": release_id,
        "cover": artwork,
        "albumCover": artwork or str((release or {}).get("artwork") or "") if isinstance(release, dict) else artwork,
        "artistCover": str(
            item.get("artistArtwork") or item.get("artistAvatar")
            or first_artist.get("avatar") or first_artist.get("picture") or first_artist.get("artwork") or ""
        ),
        "duration": clean_duration(item.get("duration") or item.get("durationInMillis")),
        "isrc": str(item.get("isrc") or ""),
        "genreNames": list(item.get("genreNames") or item.get("genres") or []),
        "releaseDate": str(item.get("releaseDate") or ""),
        "playable": item.get("playable") is not False,
    }


def normalize_artist(item, source="apple"):
    if not isinstance(item, dict):
        return None
    artist_id = str(item.get("artistId") or item.get("id") or "")
    raw_genres = item.get("genres") or item.get("genreNames") or []
    genres = [
        str(value.get("name") or value.get("displayName") or "")
        if isinstance(value, dict) else str(value)
        for value in raw_genres
    ]
    raw_notes = item.get("editorialNotes") or {}
    editorial_notes = {}
    if isinstance(raw_notes, dict):
        for field in ("name", "tagline", "short", "standard"):
            value = str(raw_notes.get(field) or "").strip()
            value = html.unescape(value)
            value = re.sub(r"<br\s*/?>", "\n", value, flags=re.IGNORECASE)
            value = re.sub(r"</(?:p|div|h[1-6])\s*>", "\n\n", value, flags=re.IGNORECASE)
            value = re.sub(r"<[^>]*>", "", value).strip()
            if value:
                editorial_notes[field] = html.unescape(value)
    return {
        "kind": "artist",
        "id": artist_id,
        "source": source,
        "name": str(item.get("displayName") or item.get("name") or "Unknown Artist"),
        "cover": str(item.get("avatar") or item.get("picture") or ""),
        "genres": [value for value in genres if value],
        "biography": str(item.get("bio") or item.get("biography") or ""),
        "editorialNotes": editorial_notes,
        "url": str(item.get("url") or ""),
    }


def normalize_album(item, source="apple"):
    if not isinstance(item, dict):
        return None
    album_id = str(item.get("releaseId") or item.get("id") or "")
    artists = raw_artists(item)
    artist_records = item.get("artists") if isinstance(item.get("artists"), list) else []
    return {
        "kind": "album",
        "id": album_id,
        "source": source,
        "title": str(item.get("title") or item.get("name") or "Unknown Album"),
        "artist": artists[0] if artists else str(item.get("artistName") or "Unknown Artist"),
        "artists": artists,
        "artistIds": [str(value) for value in item.get("artistIds", []) if value],
        "artistCovers": [
            str(value.get("avatar") or value.get("picture") or "")
            for value in artist_records if isinstance(value, dict)
        ],
        "cover": str(item.get("artwork") or item.get("cover") or ""),
        "releaseDate": str(item.get("releaseDate") or ""),
        "releaseType": str(item.get("releaseType") or item.get("type") or ""),
    }


def apple_cover(attributes):
    artwork = attributes.get("artwork") or {}
    url = artwork.get("url") or ""
    return (
        str(url)
        .replace("{w}", "640")
        .replace("{h}", "640")
        .replace("{f}", "jpg")
    )


def normalize_apple(item, kind):
    if not isinstance(item, dict):
        return None
    attributes = item.get("attributes") or {}
    item_id = str(item.get("id") or "")
    relationships = item.get("relationships") or {}
    album_relations = (relationships.get("albums") or {}).get("data") or []
    artist_relations = (relationships.get("artists") or {}).get("data") or []
    album_id = str(album_relations[0].get("id") or "") if album_relations else ""
    artist_ids = [str(value.get("id") or "") for value in artist_relations if value.get("id")]
    if kind == "songs":
        row = normalize_track(
            {
                "id": item_id,
                "title": attributes.get("name"),
                "artistName": attributes.get("artistName"),
                "albumName": attributes.get("albumName"),
                "artwork": apple_cover(attributes),
                "durationInMillis": attributes.get("durationInMillis"),
                "isrc": attributes.get("isrc"),
                "genreNames": attributes.get("genreNames") or [],
                "albumId": album_id,
                "artistIds": artist_ids,
                "releaseDate": attributes.get("releaseDate"),
            },
            source="apple",
        )
        if row:
            row["appleId"] = item_id
            row["albumId"] = album_id
            row["url"] = str(attributes.get("url") or "")
        return row
    if kind == "albums":
        row = normalize_album(
            {
                "id": item_id,
                "title": attributes.get("name"),
                "artistName": attributes.get("artistName"),
                "artwork": apple_cover(attributes),
                "releaseDate": attributes.get("releaseDate"),
                "genreNames": attributes.get("genreNames") or [],
                "artistIds": artist_ids,
            },
            source="apple",
        )
        if row:
            row["appleId"] = item_id
        return row
    if kind == "artists":
        row = normalize_artist(
            {
                "id": item_id,
                "name": attributes.get("name"),
                "avatar": apple_cover(attributes),
                "genreNames": attributes.get("genreNames") or [],
                "editorialNotes": attributes.get("editorialNotes") or {},
                "url": attributes.get("url") or "",
            },
            source="apple",
        )
        if row:
            row["appleId"] = item_id
        return row
    return None


def add_artist_artwork(artists):
    missing = []
    for artist in artists:
        artist_id = str(artist.get("id") or "")
        if artist.get("cover") or not re.fullmatch(r"[0-9]{1,32}", artist_id):
            continue
        if artist_id in _artist_artwork_cache:
            artist["cover"] = _artist_artwork_cache[artist_id]
        else:
            missing.append(artist_id)

    if missing:
        ids = list(dict.fromkeys(missing))[:25]
        try:
            raw_artists = apple_url("/artists", {"ids": ",".join(ids)}).get("data") or []
        except MusicError:
            return artists
        covers = {}
        for raw in raw_artists:
            record = normalize_apple(raw, "artists")
            if record:
                covers[record["id"]] = record.get("cover") or ""
        if len(_artist_artwork_cache) + len(ids) > 4096:
            _artist_artwork_cache.clear()
        for artist_id in ids:
            _artist_artwork_cache[artist_id] = covers.get(artist_id, "")
        for artist in artists:
            artist_id = str(artist.get("id") or "")
            if not artist.get("cover") and artist_id in covers:
                artist["cover"] = covers[artist_id]
    return artists


def genre_matches(resource, genre_name):
    names = resource.get("genreNames") or []
    wanted = normalized(genre_name)
    return any(normalized(name) == wanted for name in names)


def apple_search_page(query, category, offset=0):
    params = {
        "term": query,
        "types": category,
        "limit": SEARCH_PAGE_SIZE,
        "offset": max(0, int(offset)),
    }
    data = apple_url("/search", params).get("results") or {}
    result = data.get(category) or {}
    raw_items = result.get("data") or []
    items = [item for raw in raw_items if (item := normalize_apple(raw, category))]
    return items, len(raw_items), bool(result.get("next"))


def load_genres():
    data = apple_url("/genres", {"limit": 100})
    options = []
    seen = set()
    for item in data.get("data", []):
        attributes = item.get("attributes") or {}
        genre_id = str(item.get("id") or "")
        name = str(attributes.get("name") or "").strip()
        if not genre_id or not name or normalized(name) == "music" or genre_id in seen:
            continue
        seen.add(genre_id)
        options.append({"id": genre_id, "name": name})
    options.sort(key=lambda item: item["name"].casefold())
    return options


def chart_page(category, genre_id="", offset=0, limit=SEARCH_PAGE_SIZE):
    if category not in ("songs", "albums"):
        return [], 0, False
    params = {"types": category, "chart": "most-played", "limit": limit}
    if genre_id:
        params["genre"] = safe_catalog_id(genre_id)
    if offset:
        params["offset"] = max(0, int(offset))
    data = apple_url("/charts", params).get("results") or {}
    items = []
    has_more = False
    raw_count = 0
    for chart in data.get(category, []) or []:
        raw_items = chart.get("data", []) or []
        raw_count += len(raw_items)
        items.extend(item for raw in raw_items if (item := normalize_apple(raw, category)))
        has_more = has_more or bool(chart.get("next"))
    return items, raw_count, has_more


def apple_playlist_page(playlist_id, offset=0, limit=SEARCH_PAGE_SIZE):
    playlist_id = safe_playlist_id(playlist_id)
    params = {"limit": min(100, max(1, int(limit)))}
    if offset:
        params["offset"] = max(0, int(offset))
    response = apple_url("/playlists/" + playlist_id + "/tracks", params)
    raw_items = response.get("data") or []
    items = [item for raw in raw_items if (item := normalize_apple(raw, "songs"))]
    cursor = str(response.get("next") or "")
    return items, len(raw_items), bool(cursor), cursor


def apple_playlist_cursor(playlist_id, cursor):
    playlist_id = safe_playlist_id(playlist_id)
    storefront = music_config()["storefront"]
    url = urllib.parse.urljoin(APPLE_API + "/", str(cursor or ""))
    parsed = urllib.parse.urlsplit(url)
    expected = f"/v1/catalog/{storefront}/playlists/{playlist_id}/tracks"
    if (parsed.scheme != "https" or parsed.netloc != "api.music.apple.com"
            or parsed.path != expected or parsed.username or parsed.password):
        raise MusicError("The Apple Music playlist returned an invalid page link.")
    response = catalog_cache().load(
        url, 900, lambda: request_json(url, {"Authorization": "Bearer " + apple_token()})
    )
    raw_items = response.get("data") or []
    items = [item for raw in raw_items if (item := normalize_apple(raw, "songs"))]
    next_cursor = str(response.get("next") or "")
    return items, len(raw_items), bool(next_cursor), next_cursor


def playlist_results():
    playlist_id = music_config().get("default_playlist") or ""
    if not playlist_id:
        return chart_results()
    songs, raw_count, has_more, cursor = apple_playlist_page(playlist_id, limit=SEARCH_PAGE_SIZE)
    artists = []
    albums = []
    seen_artists = set()
    seen_albums = set()
    for song in songs:
        artist_name = str(song.get("artist") or "").strip()
        artist_key = normalized(artist_name)
        if artist_name and artist_key not in seen_artists:
            seen_artists.add(artist_key)
            artist_ids = song.get("artistIds") or []
            artists.append({
                "kind": "artist",
                "id": artist_ids[0] if artist_ids else "apple-name:" + artist_key,
                "source": "apple",
                "name": artist_name,
                "cover": song.get("artistCover") or "",
                "genres": song.get("genreNames") or [],
            })
        album_name = str(song.get("album") or "").strip()
        album_key = str(song.get("albumId") or "") or (normalized(album_name) + "|" + artist_key)
        if album_name and album_key not in seen_albums:
            seen_albums.add(album_key)
            albums.append({
                "kind": "album",
                "id": str(song.get("albumId") or "name:" + album_key),
                "source": "apple",
                "title": album_name,
                "artist": artist_name or "Unknown Artist",
                "artists": song.get("artists") or [artist_name],
                "artistIds": song.get("artistIds") or [],
                "artistCovers": [song.get("artistCover") or ""],
                "cover": song.get("albumCover") or song.get("cover") or "",
                "releaseDate": song.get("releaseDate") or "",
            })
    next_offset = raw_count
    return {
        "artists": artists,
        "albums": albums,
        "songs": songs,
        "paging": {
            "artists": {"limit": len(artists), "hasMore": False},
            "albums": {"limit": len(albums), "hasMore": False},
            "songs": {"limit": next_offset, "hasMore": has_more and next_offset < SEARCH_MAX_LIMIT,
                      "cursor": cursor},
        },
        "playlistId": playlist_id,
    }


def chart_results(genre_id="", kind="all"):
    params = {"types": "songs,albums", "chart": "most-played", "limit": SEARCH_PAGE_SIZE}
    if genre_id:
        params["genre"] = safe_catalog_id(genre_id)
    charts = (apple_url("/charts", params).get("results") or {})

    def chart_items(category):
        items = []
        raw_count = 0
        has_more = False
        for chart in charts.get(category, []) or []:
            raw_items = chart.get("data", []) or []
            raw_count += len(raw_items)
            items.extend(item for raw in raw_items if (item := normalize_apple(raw, category)))
            has_more = has_more or bool(chart.get("next"))
        return items, raw_count, has_more

    songs, song_count, songs_more = chart_items("songs")
    albums, album_count, albums_more = chart_items("albums")
    artists = []
    seen = set()
    for resource in songs + albums:
        name = str(resource.get("artist") or "").strip()
        key = normalized(name)
        if not name or key in seen:
            continue
        seen.add(key)
        artists.append({
            "kind": "artist",
            "id": "apple-name:" + key,
            "source": "apple",
            "name": name,
            "cover": "",
            "genres": [],
        })
    return {
        "artists": artists,
        "albums": albums,
        "songs": songs,
        "paging": {
            "artists": {"limit": len(artists), "hasMore": False},
            "albums": {"limit": album_count, "hasMore": albums_more},
            "songs": {"limit": song_count, "hasMore": songs_more},
        },
    }


def search_page(args):
    query = str(args.get("query") or "").strip()
    category = str(args.get("category") or "songs").strip().lower()
    if category not in ("artists", "albums", "songs"):
        raise MusicError("Unknown music result type.")
    genre_id = str(args.get("genreId") or "").strip()
    genre_name = str(args.get("genreName") or "").strip()
    offset = max(0, int(args.get("offset") or 0))
    page_limit = min(SEARCH_MAX_LIMIT, max(SEARCH_PAGE_SIZE, int(args.get("limit") or SEARCH_PAGE_SIZE)))
    if not query:
        playlist_id = music_config().get("default_playlist") or ""
        if playlist_id and not genre_id:
            if category != "songs" or offset >= page_limit:
                return {"category": category, "items": [], "hasMore": False,
                        "limit": min(page_limit, offset), "nextOffset": offset}
            cursor = str(args.get("cursor") or "")
            if cursor:
                items, raw_count, has_more, next_cursor = apple_playlist_cursor(playlist_id, cursor)
            else:
                items, raw_count, has_more, next_cursor = apple_playlist_page(
                    playlist_id, offset, min(SEARCH_PAGE_SIZE, page_limit - offset)
                )
            next_offset = offset + raw_count
            return {
                "category": category,
                "items": items,
                "hasMore": has_more and page_limit < SEARCH_MAX_LIMIT,
                "limit": min(page_limit, next_offset),
                "nextOffset": next_offset,
                "cursor": next_cursor,
            }
        items, raw_count, has_more = chart_page(category, genre_id, offset, SEARCH_PAGE_SIZE)
        next_offset = offset + raw_count
        return {
            "category": category,
            "items": items,
            "hasMore": has_more and next_offset < SEARCH_MAX_LIMIT,
            "limit": min(page_limit, next_offset),
            "nextOffset": next_offset,
        }

    items, raw_count, has_more = apple_search_page(query, category, offset)
    if category == "artists":
        items = add_artist_artwork(items)
    if genre_id and genre_name:
        items = [item for item in items if genre_matches(item, genre_name)]
    next_offset = offset + raw_count
    return {
        "category": category,
        "items": items,
        "hasMore": has_more and page_limit < SEARCH_MAX_LIMIT,
        "limit": min(page_limit, next_offset),
        "nextOffset": next_offset,
    }


def search(args):
    query = str(args.get("query") or "").strip()
    kind = str(args.get("kind") or "all").strip().lower()
    genre_id = str(args.get("genreId") or "").strip()
    genre_name = str(args.get("genreName") or "").strip()
    if not query:
        if music_config().get("default_playlist") and not genre_id:
            return playlist_results()
        return chart_results(genre_id, kind)

    categories = ("songs",) if kind == "songs" else ("artists", "albums", "songs")
    page_args = {"query": query, "genreId": genre_id, "genreName": genre_name}
    pages = {}
    failures = []
    with ThreadPoolExecutor(max_workers=len(categories)) as pool:
        futures = {
            category: pool.submit(search_page, {**page_args, "category": category, "limit": SEARCH_PAGE_SIZE})
            for category in categories
        }
        for category, future in futures.items():
            try:
                pages[category] = future.result()
            except MusicError as error:
                failures.append(str(error))
                pages[category] = {"items": [], "hasMore": False, "limit": 0}
    if not any(page.get("items") for page in pages.values()) and failures:
        raise MusicError(failures[0])
    results = {category: pages.get(category, {}).get("items", []) for category in ("artists", "albums", "songs")}
    results["paging"] = {
        category: {
            "limit": pages.get(category, {}).get("limit", 0),
            "hasMore": pages.get(category, {}).get("hasMore", False),
        }
        for category in ("artists", "albums", "songs")
    }
    return results


def find_apple_artists(name):
    data = apple_url(
        "/search",
        {"term": name, "types": "artists", "limit": 25},
    ).get("results") or {}
    candidates = (data.get("artists") or {}).get("data") or []
    wanted = normalized(name)
    exact = [
        item for item in candidates
        if normalized((item.get("attributes") or {}).get("name")) == wanted
    ]
    if exact:
        candidates = exact[:1]
    else:
        matches = []
        for item in candidates:
            attributes = item.get("attributes") or {}
            candidate_name = normalized(attributes.get("name"))
            if len(candidate_name) < 3:
                continue
            pattern = r"(?<![a-z0-9])" + re.escape(candidate_name) + r"(?![a-z0-9])"
            match = re.search(pattern, wanted)
            if match:
                matches.append((match.start(), item))
        candidates = [item for _, item in sorted(matches, key=lambda pair: pair[0])]

    records = []
    seen = set()
    for item in candidates:
        artist = normalize_apple(item, "artists")
        if artist and artist["id"] not in seen:
            records.append(artist)
            seen.add(artist["id"])
    return add_artist_artwork(records)


def apple_artist_albums(artist_id, offset=0, limit=25):
    artist_id = safe_catalog_id(artist_id)
    offset = max(0, int(offset))
    limit = min(25, max(1, int(limit)))
    data = apple_url(
        "/artists/" + artist_id + "/albums",
        {"limit": limit, "offset": offset},
    )
    raw_albums = data.get("data") or []
    return {
        "items": [item for raw in raw_albums if (item := normalize_apple(raw, "albums"))],
        "offset": offset + len(raw_albums),
        "hasMore": bool(data.get("next")),
    }


def tracks_for_album(album, all_pages=False):
    album_id = safe_catalog_id(album.get("id"))
    songs = []
    offset = 0
    while True:
        data = apple_url("/albums/" + album_id + "/tracks", {"limit": 100, "offset": offset})
        raw_items = data.get("data") or []
        for raw in raw_items:
            song = normalize_apple(raw, "songs")
            if not song:
                continue
            song["albumId"] = album_id
            song["album"] = album.get("title") or song.get("album") or "Unknown Album"
            song["albumCover"] = album.get("cover") or song.get("albumCover") or ""
            if not song.get("cover"):
                song["cover"] = song["albumCover"]
            if not song.get("artistIds"):
                song["artistIds"] = album.get("artistIds") or []
            if not song.get("releaseDate"):
                song["releaseDate"] = album.get("releaseDate") or ""
            songs.append(song)
        if all_pages and data.get("next") and len(songs) >= 1000:
            raise MusicError("This album has more tracks than one download can save.")
        if not all_pages or not data.get("next") or not raw_items:
            break
        offset += len(raw_items)
    return songs


def catalog_artist_records(artist_ids, artist_names=None):
    ids = []
    for value in artist_ids or []:
        value = str(value or "").strip()
        if re.fullmatch(r"[0-9]{1,32}", value) and value not in ids:
            ids.append(value)
    if ids:
        try:
            data = apple_url("/artists", {"ids": ",".join(ids[:25])}).get("data") or []
            records = [item for raw in data if (item := normalize_apple(raw, "artists"))]
            if records:
                return records
        except MusicError:
            pass
    records = []
    seen = set()
    for name in artist_names or []:
        for artist in find_apple_artists(str(name or "")):
            if artist["id"] not in seen:
                records.append(artist)
                seen.add(artist["id"])
    return records


def unique_songs(songs):
    output = []
    seen = set()
    for song in songs:
        key = str(song.get("id") or "")
        if key and key not in seen:
            output.append(song)
            seen.add(key)
    return output


def artist_details(item):
    artist_id = str(item.get("id") or "")
    if str(item.get("source") or "") != "apple" or not re.fullmatch(r"[0-9]{1,32}", artist_id):
        matches = find_apple_artists(str(item.get("name") or ""))
        match = matches[0] if matches else None
        artist_id = str(match.get("id") or "") if match else ""
    artist_id = safe_catalog_id(artist_id)
    artist_data = apple_url("/artists/" + artist_id).get("data") or []
    artist = normalize_apple(artist_data[0], "artists") if artist_data else item
    album_page = apple_artist_albums(artist_id)
    warning = ""
    try:
        top = apple_url("/artists/" + artist_id + "/view/top-songs", {"limit": 25})
        songs = [song for raw in top.get("data", []) if (song := normalize_apple(raw, "songs"))]
    except MusicError:
        songs = []
        top = {}
        warning = "Top songs could not load. Select an album to browse its tracks."
    return {
        "artist": artist, "genres": artist.get("genres") or [],
        "biography": artist.get("biography") or "", "albums": album_page["items"],
        "albumPaging": {"artistId": artist_id, "offset": album_page["offset"], "hasMore": album_page["hasMore"]},
        "songPaging": {"artistId": artist_id, "cursor": top.get("next") or "",
                       "albumOffset": 0, "hasMore": bool(top.get("next") or album_page["items"])},
        "songs": unique_songs(songs), "trackWarning": warning,
    }


def artist_songs_page(args):
    artist_id = safe_catalog_id(args.get("artistId"))
    cursor = str(args.get("cursor") or "")
    album_offset = max(0, int(args.get("albumOffset") or 0))
    if cursor:
        page = apple_artist_song_cursor(artist_id, cursor)
        next_cursor = str(page.get("next") or "")
        songs = [song for raw in page.get("data", []) if (song := normalize_apple(raw, "songs"))]
        return {"items": unique_songs(songs), "cursor": next_cursor,
                "albumOffset": album_offset, "hasMore": True}
    # The top-songs view is a ranking, not the artist's full catalogue. Fetch a
    # small album batch only when the Songs pane actually reaches its end.
    page = apple_artist_albums(artist_id, offset=album_offset, limit=2)
    albums = page["items"]
    with ThreadPoolExecutor(max_workers=min(2, len(albums) or 1)) as pool:
        futures = [pool.submit(tracks_for_album, album) for album in albums]
        songs = []
        failures = 0
        for future in futures:
            try:
                songs.extend(future.result())
            except MusicError:
                failures += 1
    if failures and not songs:
        raise MusicError("Album tracks could not load. Reopen the artist to retry.")
    return {"items": unique_songs(songs), "cursor": "",
            "albumOffset": page["offset"], "hasMore": page["hasMore"],
            "trackWarning": "Some album tracks could not load." if failures else ""}


def artist_info(item):
    if not isinstance(item, dict):
        raise MusicError("Invalid artist for information lookup.")
    artist_id = str(item.get("id") or "")
    artist_name = str(item.get("name") or "").strip()
    if str(item.get("source") or "") != "apple" or not re.fullmatch(r"[0-9]{1,32}", artist_id):
        matches = find_apple_artists(artist_name)
        wanted_name = normalized(artist_name)
        match = next(
            (artist for artist in matches if normalized(artist.get("name")) == wanted_name),
            matches[0] if matches else None,
        )
        artist_id = str(match.get("id") or "") if match else ""
    if not re.fullmatch(r"[0-9]{1,32}", artist_id):
        fallback = normalize_artist(item, source=str(item.get("source") or "apple")) or item
        return {"artist": fallback, "available": False}
    artist_data = apple_url(
        "/artists/" + safe_catalog_id(artist_id),
        {"extend": "editorialNotes"},
    ).get("data") or []
    artist = normalize_apple(artist_data[0], "artists") if artist_data else None
    if not artist:
        fallback = normalize_artist(item, source=str(item.get("source") or "apple")) or item
        return {"artist": fallback, "available": False}
    if not artist.get("biography"):
        biography = apple_artist_page_biography(artist_id, artist.get("url"))
        if biography:
            artist["biography"] = biography
    has_info = bool(
        artist.get("genres") or artist.get("cover") or artist.get("url")
        or artist.get("biography") or artist.get("editorialNotes")
    )
    return {"artist": artist, "available": has_info}


def artist_albums_page(args):
    artist_id = safe_catalog_id(args.get("artistId"))
    offset = max(0, int(args.get("offset") or 0))
    page = apple_artist_albums(artist_id, offset=offset)
    return {**page, "songs": [], "trackWarning": ""}


def album_details(item, include_tracks=True):
    album_id = str(item.get("id") or "")
    if str(item.get("source") or "") != "apple" or not re.fullmatch(r"[0-9]{1,32}", album_id):
        query = " ".join(part for part in (str(item.get("artist") or ""), str(item.get("title") or "")) if part)
        matches = (apple_url("/search", {"term": query, "types": "albums", "limit": 25})
                   .get("results", {}).get("albums", {}).get("data", []))
        wanted_title = normalized(item.get("title"))
        wanted_artist = normalized(item.get("artist"))
        match = next((raw for raw in matches
                      if normalized((raw.get("attributes") or {}).get("name")) == wanted_title
                      and (not wanted_artist or normalized((raw.get("attributes") or {}).get("artistName")) == wanted_artist)), None)
        album_id = str(match.get("id") or "") if match else ""
    album_id = safe_catalog_id(album_id)
    album_data = apple_url("/albums/" + album_id).get("data") or []
    album = normalize_apple(album_data[0], "albums") if album_data else item
    artists = catalog_artist_records(album.get("artistIds"), album.get("artists")) if include_tracks else []
    return {"album": album, "artists": artists,
            "songs": tracks_for_album(album) if include_tracks else []}


def song_artists(args):
    song = args.get("song") or {}
    return catalog_artist_records(song.get("artistIds"), song.get("artists") or [song.get("artist")])


def score_candidate(wanted, candidate):
    wanted_isrc = str(wanted.get("isrc") or "").strip().casefold()
    candidate_isrc = str(candidate.get("isrc") or "").strip().casefold()
    if wanted_isrc and candidate_isrc == wanted_isrc:
        return 1000
    wanted_title = normalized(wanted.get("title"))
    candidate_title = normalized(candidate.get("title"))
    if not wanted_title or not candidate_title:
        return 0
    if wanted_title == candidate_title:
        score = 100
    elif wanted_title in candidate_title or candidate_title in wanted_title:
        score = 60
    else:
        return 0
    artist = normalized(wanted.get("artist"))
    candidate_artists = [normalized(value) for value in raw_artists(candidate)]
    if artist and artist in candidate_artists:
        score += 80
    elif artist and any(artist in value or value in artist for value in candidate_artists):
        score += 35
    return score


def value_at_path(value, path):
    current = value
    for part in str(path or "").split("."):
        if isinstance(current, dict):
            current = current.get(part)
        elif isinstance(current, list) and part.isdigit() and int(part) < len(current):
            current = current[int(part)]
        else:
            return None
    return current


def provider_template(provider, template_name, values, require_values=False):
    template = str(value_at_path(provider, template_name) or "").strip()
    if not template:
        return ""
    substitutions = {
        "base_url": str(provider.get("base_url") or "").rstrip("/"),
        **{key: str(value or "") for key, value in values.items()},
    }
    placeholders = re.findall(r"\{([^{}]+)\}", template)
    if any(key not in substitutions for key in placeholders):
        raise MusicError("A provider URL template has an unknown placeholder.")
    if require_values and any(not substitutions[key] for key in placeholders):
        raise MusicError("This download URL needs metadata that is missing from the selected item.")
    for key, value in substitutions.items():
        encoded = value if key == "base_url" else urllib.parse.quote(value, safe="")
        template = template.replace("{" + key + "}", encoded)
    if re.search(r"\{[^{}]+\}", template):
        raise MusicError("A provider URL template has an unknown placeholder.")
    try:
        parsed = urllib.parse.urlparse(template)
        parsed.port  # Reject malformed port numbers.
        valid = parsed.scheme in ("http", "https") and parsed.hostname and not re.search(r"\s", template)
    except ValueError:
        valid = False
    if not valid:
        raise MusicError("A provider URL must use a valid HTTP or HTTPS address.")
    return template


def download_provider(kind):
    for provider in music_config()["providers"]:
        download = provider.get("download") or {}
        if isinstance(download, dict) and str(download.get(kind) or "").strip():
            return provider
    return None


def download_capabilities():
    return {kind: download_provider(kind) is not None for kind in ("track", "album")}


def download_url(kind, item):
    if kind not in ("track", "album") or not isinstance(item, dict):
        raise MusicError("Choose a song or album to download.")
    provider = download_provider(kind)
    if provider is None:
        raise MusicError("No download provider is configured for this item.")
    if provider["download"][kind].strip() == "stream":
        raise MusicError("This provider saves streams instead of opening a download URL.")
    title = str(item.get("title") or "").strip()
    artist = str(item.get("artist") or "").strip()
    item_id = str(item.get("id") or "").strip()
    if kind == "album" and item_id.startswith("name:"):
        item_id = ""  # Album rows inferred from a song may have a temporary name key.
    album_id = item.get("albumId") if kind == "track" else item_id
    values = {
        "id": item_id,
        "track_id": item_id if kind == "track" else "",
        "album_id": str(album_id or "").strip(),
        "title": title,
        "artist": artist,
        "album": str(item.get("album") or (title if kind == "album" else "")).strip(),
        "isrc": str(item.get("isrc") or "").strip() if kind == "track" else "",
        "query": " ".join(value for value in (artist, title) if value),
    }
    return provider_template(provider, "download." + kind, values, require_values=True)


def save_stream_track(track, provider, directory):
    title = str(track.get("title") or "").strip()
    artist = str(track.get("artist") or "").strip()
    album = str(track.get("album") or "").strip()
    release_date = str(track.get("releaseDate") or "").strip()[:10]
    if not (title and artist and album and re.fullmatch(r"\d{4}-\d{2}-\d{2}", release_date)):
        raise MusicError("A song needs a title, artist, album, and full release date to save to Music.")
    stem = f"{safe_name(title)} - {safe_name(artist)} - {safe_name(album)} ({release_date})"
    resolved = resolve_track(track, providers=[provider], local_first=False)
    headers = provider_headers(provider)
    command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y"]
    if not any(name.lower() == "user-agent" for name in headers):
        command += ["-user_agent", USER_AGENT]
    if headers:
        command += ["-headers", "".join(f"{name}: {value}\r\n" for name, value in headers.items())]
    command += ["-i", resolved["url"], "-map", "0:a:0", "-c:a", "copy", "-f", "matroska"]
    directory.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix=".zephyrus-music-", suffix=".mka", dir=directory, delete=False) as output:
        temporary = Path(output.name)
    process = None
    try:
        try:
            process = subprocess.Popen(command + [str(temporary)], stdin=subprocess.DEVNULL,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        except FileNotFoundError as error:
            raise MusicError("Install ffmpeg to save music streams.") from error
        with _download_processes_lock:
            _download_processes.add(process)
        try:
            process.communicate(timeout=1800)
        except subprocess.TimeoutExpired as error:
            process.kill()
            process.communicate()
            raise MusicError("Saving this music stream timed out.") from error
        if process.returncode != 0 or temporary.stat().st_size == 0:
            raise MusicError("The configured provider's stream could not be saved.")
        for number in range(1, 1001):
            suffix = "" if number == 1 else f" ({number})"
            target = directory / (stem + suffix + ".mka")
            try:
                os.link(temporary, target)
                return str(target)
            except FileExistsError:
                continue
        raise MusicError("Too many copies of this song already exist in Music.")
    finally:
        if process is not None:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            with _download_processes_lock:
                _download_processes.discard(process)
        temporary.unlink(missing_ok=True)


def stop_downloads(signum, frame):
    with _download_processes_lock:
        processes = list(_download_processes)
    for process in processes:
        if process.poll() is None:
            process.terminate()
    raise SystemExit(0)


def save_stream_download(kind, item, provider):
    if kind not in ("track", "album") or not isinstance(item, dict):
        raise MusicError("Choose a song or album to download.")
    if not shutil.which("ffmpeg"):
        raise MusicError("Install ffmpeg to save music streams.")
    directory = xdg_dir("XDG_MUSIC_DIR", "Music")
    if kind == "track":
        try:
            path = save_stream_track(item, provider, directory)
        except OSError as error:
            raise MusicError("Could not write the music download.") from error
        return {"saved": 1, "failed": 0, "path": path}

    details = album_details(item, include_tracks=False)
    album = details.get("album") or item
    tracks = tracks_for_album(album, all_pages=True)
    if not tracks:
        raise MusicError("No tracks were found for this album.")
    try:
        directory.mkdir(parents=True, exist_ok=True)
    except OSError as error:
        raise MusicError("Could not write the music download.") from error
    saved = 0
    first_failure = None
    for track in tracks:
        try:
            save_stream_track(track, provider, directory)
            saved += 1
        except (MusicError, OSError) as error:
            if first_failure is None:
                first_failure = error
            continue
    if not saved:
        if isinstance(first_failure, MusicError):
            raise first_failure
        raise MusicError("Could not write the music download.")
    return {"saved": saved, "failed": len(tracks) - saved, "path": str(directory)}


def open_download(args):
    kind = args.get("kind")
    provider = download_provider(kind)
    if provider is None:
        raise MusicError("No download provider is configured for this item.")
    if provider["download"][kind].strip() == "stream":
        return save_stream_download(kind, args.get("item"), provider)
    url = download_url(kind, args.get("item"))
    try:
        subprocess.Popen(
            browser_argv("music", url), stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except (OSError, ValueError) as error:
        raise MusicError("Could not open the download URL.") from error
    return {"started": True}


def provider_headers(provider):
    values = provider.get("headers") or {}
    if not isinstance(values, dict):
        return {}
    headers = {}
    for name, value in values.items():
        name = str(name).strip()
        value = str(value).strip()
        if name and value and not any(char in name + value for char in "\r\n"):
            headers[name] = value
    return headers


def lyrics_provider_url(provider, song):
    base_url = str(provider.get("base_url") or "https://lrclib.net/api").strip().rstrip("/")
    if base_url.endswith("/get"):
        endpoint = base_url
    else:
        endpoint = base_url + "/get"
    parsed = urllib.parse.urlparse(endpoint)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise MusicError("A lyrics provider URL must use HTTP or HTTPS.")
    params = {
        "track_name": str(song.get("title") or "").strip(),
        "artist_name": str(song.get("artist") or "").strip(),
    }
    album = str(song.get("album") or "").strip()
    duration = clean_duration(song.get("duration"))
    if album and album.casefold() != "unknown album":
        params["album_name"] = album
    if duration:
        params["duration"] = str(duration)
    return endpoint + "?" + urllib.parse.urlencode(params)


def lyrics_provider_headers(provider):
    headers = provider_headers(provider)
    if not any(name.lower() == "lrclib-client" for name in headers):
        headers["Lrclib-Client"] = "Zephyrus Shell Music"
    api_key = str(provider.get("api_key") or "").strip()
    if api_key:
        header_name = str(provider.get("api_key_header") or "Authorization").strip()
        prefix = str(provider.get("api_key_prefix", "Bearer "))
        if header_name and not any(char in header_name + api_key + prefix for char in "\r\n"):
            headers[header_name] = prefix + api_key
    return headers


def lyrics_request_json(url, headers=None):
    host = urllib.parse.urlparse(url).netloc.lower()
    now = time.time()
    with _lyrics_cooldown_lock:
        retry_at = _lyrics_cooldowns.get(host, 0)
    if now < retry_at:
        raise MusicError("The lyrics provider is rate-limited; try again later.")

    request_headers = {"Accept": "application/json", "User-Agent": USER_AGENT}
    request_headers.update(headers or {})
    request = urllib.request.Request(url, headers=request_headers)
    try:
        with urllib.request.urlopen(request, timeout=16) as response:
            body = response.read(MAX_RESPONSE_BYTES + 1)
            if len(body) > MAX_RESPONSE_BYTES:
                raise MusicError("A lyrics provider returned an oversized response.")
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        if error.code == 429:
            try:
                retry_after = max(1, int(error.headers.get("Retry-After") or 60))
            except (TypeError, ValueError):
                retry_after = 60
            with _lyrics_cooldown_lock:
                _lyrics_cooldowns[host] = time.time() + retry_after
            raise MusicError("The lyrics provider is rate-limited; try again later.") from error
        if error.code in (502, 503, 504):
            raise MusicError("A lyrics provider is temporarily unavailable.") from error
        raise MusicError("A lyrics provider returned HTTP " + str(error.code) + ".") from error
    except urllib.error.URLError as error:
        raise MusicError("Could not connect to a lyrics provider.") from error
    except TimeoutError as error:
        raise MusicError("A lyrics provider timed out.") from error
    try:
        return json.loads(body.decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        raise MusicError("A lyrics provider returned unreadable JSON.") from error


def lyrics_from_response(response):
    if not isinstance(response, dict):
        return ""
    plain = str(response.get("plainLyrics") or "").strip()
    if plain:
        return plain
    synced = str(response.get("syncedLyrics") or "")
    lines = []
    for line in synced.splitlines():
        text = re.sub(r"\[(?:\d{1,2}:)?\d{1,2}:\d{2}(?:[.:]\d{1,3})?\]", "", line).strip()
        if text:
            lines.append(text)
    return "\n".join(lines).strip()


def fetch_lyrics(args):
    song = args.get("song") or {}
    if not isinstance(song, dict):
        raise MusicError("Invalid song for lyrics lookup.")
    if not str(song.get("title") or "").strip() or not str(song.get("artist") or "").strip():
        return {"available": False, "lyrics": "", "provider": ""}
    providers = music_config()["lyrics_providers"]
    if not providers:
        raise MusicError("No lyrics provider is configured.")
    failures = []
    for index, provider in enumerate(providers):
        try:
            response = lyrics_request_json(
                lyrics_provider_url(provider, song),
                lyrics_provider_headers(provider),
            )
        except MusicError as error:
            failures.append(error)
            continue
        lyrics = lyrics_from_response(response)
        if lyrics:
            return {
                "available": True,
                "lyrics": lyrics,
                "provider": str(provider.get("name") or "Lyrics provider " + str(index + 1)),
            }
    if failures:
        raise failures[-1]
    return {"available": False, "lyrics": "", "provider": ""}


def provider_results(provider, wanted, query):
    url = provider_template(provider, "search_url", {
        "query": query,
        "artist": wanted.get("artist") or "",
        "title": wanted.get("title") or "",
        "isrc": wanted.get("isrc") or "",
        "limit": 30,
    })
    if not url:
        return []
    response = request_json(url, provider_headers(provider))
    raw_items = value_at_path(response, provider.get("results_path", "tracks"))
    if not isinstance(raw_items, list):
        return []
    candidates = []
    id_field = provider.get("track_id_field", "trackId")
    title_field = provider.get("track_title_field", "title")
    artist_field = provider.get("track_artist_field", "artistName")
    artists_field = provider.get("track_artists_field", "artistNames")
    isrc_field = provider.get("track_isrc_field", "isrc")
    for raw in raw_items:
        if not isinstance(raw, dict):
            continue
        artists = value_at_path(raw, artists_field)
        if not artists:
            artists = value_at_path(raw, "artists") or value_at_path(raw, "artistNames")
        artist = value_at_path(raw, artist_field) or value_at_path(raw, "artistName") or value_at_path(raw, "artist")
        candidate = {
            "id": value_at_path(raw, id_field) or value_at_path(raw, "id"),
            "title": value_at_path(raw, title_field) or value_at_path(raw, "name"),
            "artist": artist,
            "artists": artists if isinstance(artists, list) else [],
            "artistNames": artists if isinstance(artists, list) and all(isinstance(v, str) for v in artists) else [],
            "isrc": value_at_path(raw, isrc_field),
        }
        if not candidate["artistNames"] and not candidate["artists"] and artist:
            candidate["artistNames"] = [str(artist)]
        candidates.append(candidate)
    return candidates


def resolve_track(track, providers=None, local_first=True):
    local_data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "zephyrus-shell/media"
    if local_first:
        local_files = LocalLibrary(local_data).files({**track, "kind": "music"})
        if local_files:
            return {"url": local_files[0]["path"], "headers": {}}
    providers = music_config()["providers"] if providers is None else providers
    if not providers:
        raise MusicError("No playback providers are configured in music.json.")
    title = str(track.get("title") or "").strip()
    artist = str(track.get("artist") or "").strip()
    isrc = str(track.get("isrc") or "").strip()
    if not title or not artist:
        raise MusicError("This song does not have enough information to find a stream.")
    queries = ([isrc] if isrc else []) + [" ".join((artist, title))]
    provider_errors = 0
    for provider in providers:
        if not provider.get("search_url") or not provider.get("stream_url"):
            continue
        for query in queries:
            try:
                candidates = provider_results(provider, track, query)
            except MusicError:
                provider_errors += 1
                continue
            ranked = sorted(candidates, key=lambda item: score_candidate(track, item), reverse=True)
            if not ranked or score_candidate(track, ranked[0]) < 120:
                continue
            stream_id = safe_stream_id(ranked[0].get("id"))
            stream_url = provider_template(provider, "stream_url", {
                "id": stream_id,
                "track_id": stream_id,
                "query": query,
                "artist": artist,
                "title": title,
                "isrc": isrc,
            })
            return {"url": stream_url, "headers": provider_headers(provider)}
    if provider_errors:
        raise MusicError("The configured playback providers could not resolve this song.")
    raise MusicError("No configured playback provider found a confident match for this song.")


player_ipc = MpvIpc("music")


def start_player(args):
    track = args.get("track")
    if not isinstance(track, dict):
        raise MusicError("No song was selected.")
    mpv = shutil.which("mpv")
    if not mpv:
        raise MusicError("Install mpv to play music.")
    resolved = resolve_track(track)
    ipc_path = str(player_ipc.directory() / ("mpv-" + uuid.uuid4().hex[:16] + ".sock"))
    stream_url = resolved["url"]
    title = str(track.get("title") or "Music").replace("\n", " ").strip()
    provider_headers_value = resolved.get("headers") or {}
    header_fields = ",".join(
        name + ": " + value
        for name, value in provider_headers_value.items()
        if name.lower() not in ("referer", "user-agent")
    )
    referer = next(
        (value for name, value in provider_headers_value.items() if name.lower() == "referer"),
        "",
    )
    command = [
        mpv,
        "--no-video",
        "--really-quiet",
        "--no-terminal",
        "--input-ipc-server=" + ipc_path,
        "--force-media-title=" + title,
    ]
    if header_fields:
        command.append("--http-header-fields=" + header_fields)
    if referer:
        command.append("--referrer=" + referer)
    configured_user_agent = next(
        (value for name, value in provider_headers_value.items() if name.lower() == "user-agent"),
        USER_AGENT,
    )
    command.extend(("--user-agent=" + configured_user_agent, "--", stream_url))
    return {"command": command, "ipcPath": ipc_path}


def player_state(args):
    path = player_ipc.validate(args.get("ipcPath"))
    if not path:
        return {"position": 0, "duration": 0, "paused": True, "volume": 0}
    position = player_ipc.property(path, "time-pos")
    duration = player_ipc.property(path, "duration")
    paused = player_ipc.property(path, "pause")
    volume = player_ipc.property(path, "volume")
    return {
        "position": float(position or 0),
        "duration": float(duration or 0),
        "paused": bool(paused),
        "volume": float(volume if volume is not None else 70),
    }


def player_command(args):
    path = player_ipc.validate(args.get("ipcPath"))
    if not path:
        return {"sent": False}
    action = str(args.get("action") or "")
    if action == "toggle-pause":
        command = ["cycle", "pause"]
    elif action == "pause":
        command = ["set_property", "pause", bool(args.get("value"))]
    elif action == "seek":
        command = ["seek", max(0, float(args.get("value") or 0)), "absolute"]
    elif action == "volume":
        command = ["set_property", "volume", min(100, max(0, float(args.get("value") or 0)))]
    else:
        raise MusicError("Unknown player command.")
    return {"sent": player_ipc.send(path, command)}


def cleanup_player(args):
    return {"cleaned": player_ipc.cleanup(args.get("ipcPath"))}


def favorite_path():
    config_root = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return config_root / "zephyrus-shell" / "music-favorites.json"


def clean_favorite(item):
    if not isinstance(item, dict):
        return None
    kind = str(item.get("kind") or "")
    item_id = str(item.get("id") or "")
    if kind not in ("artist", "album", "song") or not item_id:
        return None
    fields = (
        ("kind", "id", "source", "name", "cover", "genres", "biography")
        if kind == "artist"
        else (
            "kind", "id", "source", "title", "artist", "artists", "artistIds", "artistCovers",
            "cover", "releaseDate", "releaseType",
        )
        if kind == "album"
        else (
            "kind", "id", "trackId", "source", "title", "artist", "artists", "album",
            "albumId", "cover", "albumCover", "artistCover", "duration", "isrc", "genreNames", "playable",
        )
    )
    cleaned = {}
    for field in fields:
        if field not in item:
            continue
        value = item[field]
        if isinstance(value, str):
            cleaned[field] = value[:2000]
        elif isinstance(value, (int, float, bool)):
            cleaned[field] = value
        elif isinstance(value, list):
            cleaned[field] = [str(entry)[:1000] for entry in value[:100]]
    return cleaned


def favorites_load():
    try:
        items = json.loads(favorite_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return []
    if not isinstance(items, list):
        return []
    records = [record for item in items if (record := clean_favorite(item))]
    artist_records = [
        record for record in records
        if record.get("kind") == "artist"
        and record.get("source") == "apple"
        and not record.get("cover")
        and re.fullmatch(r"[0-9]{1,32}", str(record.get("id") or ""))
    ][:25]
    add_artist_artwork(artist_records)
    return records


def favorites_save(args):
    items = args.get("favorites")
    if not isinstance(items, list):
        raise MusicError("Invalid favorites list.")
    cleaned = [record for item in items[:5000] if (record := clean_favorite(item))]
    path = favorite_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(cleaned, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)
    return {"saved": len(cleaned)}


def dispatch(args):
    operation = args.get("op")
    if operation == "local-songs":
        local_data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "zephyrus-shell/media"
        return [{**item, "kind": "song", "source": "local"} for item in LocalLibrary(local_data).list("music")]
    if operation == "search":
        return search(args)
    if operation == "search-page":
        return search_page(args)
    if operation == "genres":
        return load_genres()
    if operation == "artist":
        return artist_details(args.get("artist") or {})
    if operation == "artist-info":
        return artist_info(args.get("artist") or {})
    if operation == "artist-albums-page":
        return artist_albums_page(args)
    if operation == "artist-songs-page":
        return artist_songs_page(args)
    if operation == "album":
        return album_details(args.get("album") or {})
    if operation == "song-artists":
        return song_artists(args)
    if operation == "lyrics":
        return fetch_lyrics(args)
    if operation == "download-capabilities":
        return download_capabilities()
    if operation == "download":
        return open_download(args)
    if operation == "play":
        return start_player(args)
    if operation == "player-state":
        return player_state(args)
    if operation == "player-command":
        return player_command(args)
    if operation == "player-cleanup":
        return cleanup_player(args)
    if operation == "favorites-load":
        return favorites_load()
    if operation == "favorites-save":
        return favorites_save(args)
    raise MusicError("Unknown Music operation.")


def main():
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from services.worker import serve
    signal.signal(signal.SIGTERM, stop_downloads)
    serve(dispatch, errors=(MusicError,), latest=("search", "search-page", "artist", "artist-info", "album", "lyrics", "play"), controls=("player-command", "player-state", "player-cleanup", "favorites-save", "favorites-load"), scope=lambda r: (r["op"], r.get("category", "")))


if __name__ == "__main__":
    main()
