"""Catalogue record normalization, identity validation, and playback matching.

These functions do not fetch data, start players, or read configuration.
"""

import html
import re
import unicodedata
import urllib.parse


class MusicError(Exception):
    pass


def clean_artist_biography(value):
    text = html.unescape(str(value or ""))
    text = re.sub(r"<br\s*/?>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(r"</(?:p|div|h[1-6]|li)\s*>", "\n\n", text, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]*>", "", text)
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n[ \t]*\n(?:[ \t]*\n)+", "\n\n", text)
    return text.strip()


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
        "albumCover": artwork or str((release or {}).get("artwork") or "")
        if isinstance(release, dict)
        else artwork,
        "artistCover": str(
            item.get("artistArtwork")
            or item.get("artistAvatar")
            or first_artist.get("avatar")
            or first_artist.get("picture")
            or first_artist.get("artwork")
            or ""
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
        if isinstance(value, dict)
        else str(value)
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
            for value in artist_records
            if isinstance(value, dict)
        ],
        "cover": str(item.get("artwork") or item.get("cover") or ""),
        "releaseDate": str(item.get("releaseDate") or ""),
        "releaseType": str(item.get("releaseType") or item.get("type") or ""),
    }


def apple_cover(attributes):
    artwork = attributes.get("artwork") or {}
    url = artwork.get("url") or ""
    return str(url).replace("{w}", "640").replace("{h}", "640").replace("{f}", "jpg")


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
            "kind",
            "id",
            "source",
            "title",
            "artist",
            "artists",
            "artistIds",
            "artistCovers",
            "cover",
            "releaseDate",
            "releaseType",
        )
        if kind == "album"
        else (
            "kind",
            "id",
            "trackId",
            "source",
            "title",
            "artist",
            "artists",
            "album",
            "albumId",
            "cover",
            "albumCover",
            "artistCover",
            "duration",
            "isrc",
            "genreNames",
            "playable",
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
