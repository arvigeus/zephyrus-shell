#!/usr/bin/env python3
"""Low-volume Open Library worker and Books-specific persistence boundary."""
from contextlib import contextmanager
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request


ROOT = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "zephyrus-shell"
CONFIG = ROOT / "books.json"
DATA = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "zephyrus-shell/books"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "zephyrus-shell/books"
BASE = "https://openlibrary.org"
PAGE_SIZE = 40
EDITION_PAGE_SIZE = 24
CATALOGUE_TTL = 6 * 60 * 60
SEARCH_TTL = 24 * 60 * 60
DETAIL_TTL = 30 * 24 * 60 * 60
FIELDS = ",".join((
    "key", "title", "author_name", "author_key", "first_publish_year", "cover_i",
    "cover_edition_key", "edition_count", "subject", "ratings_average", "ratings_count",
    "language", "ebook_access", "has_fulltext",
))
WORK_ID = re.compile(r"^(?:/works/)?(OL\d+W)$")
AUTHOR_ID = re.compile(r"^(?:/authors/)?(OL\d+A)$")


class BooksError(Exception):
    """A concise, safe error suitable for display in the UI."""


def _text(value):
    if isinstance(value, dict):
        value = value.get("value") or value.get("name") or ""
    if isinstance(value, list):
        return " ".join(filter(None, (_text(part) for part in value))).strip()
    return str(value).strip() if value is not None else ""


def _items(value):
    return value if isinstance(value, list) else []


def _merge_authors(*groups):
    """Merge sparse Work author references without losing their stable IDs."""
    authors = []
    for group in groups:
        for author in _items(group):
            if not isinstance(author, dict):
                continue
            raw_id = author.get("id") or author.get("key") or ""
            match = AUTHOR_ID.fullmatch(str(raw_id))
            identifier = match.group(1) if match else ""
            name = _text(author.get("name"))
            if not identifier and not name:
                continue
            normalized_name = " ".join(name.casefold().split())
            existing = next((candidate for candidate in authors if (
                (identifier and candidate["id"] == identifier)
                or (normalized_name and " ".join(candidate["name"].casefold().split()) == normalized_name
                    and (not identifier or not candidate["id"] or candidate["id"] == identifier))
            )), None)
            if existing is None:
                authors.append({"id": identifier, "name": name})
                continue
            if identifier and not existing["id"]:
                existing["id"] = identifier
            if name and not existing["name"]:
                existing["name"] = name
    return authors


def escape_search_term(value):
    """Keep free-text input literal within Open Library's Lucene query syntax."""
    return re.sub(r'([+\-&|!(){}\[\]^"~*?:\\/])', r'\\\1', str(value or ""))


def work_id(value):
    match = WORK_ID.fullmatch(str(value or ""))
    if not match:
        raise BooksError("This selection does not have a valid Open Library Work ID.")
    return match.group(1)


def author_id(value):
    match = AUTHOR_ID.fullmatch(str(value or ""))
    if not match:
        raise BooksError("This author does not have a valid Open Library ID.")
    return match.group(1)


def cover_urls(cover_id=None, edition_id=""):
    if cover_id not in (None, ""):
        key, value = "id", str(cover_id)
    elif edition_id:
        key, value = "olid", str(edition_id)
    else:
        return "", ""
    encoded = urllib.parse.quote(value, safe="")
    base = f"https://covers.openlibrary.org/b/{key}/{encoded}"
    return base + "-M.jpg?default=false", base + "-L.jpg?default=false"


def normalize_work(doc):
    """Return the small, stable Work record used by catalogue delegates."""
    doc = doc if isinstance(doc, dict) else {}
    key = doc.get("key") or doc.get("id") or ""
    match = WORK_ID.fullmatch(str(key))
    if not match:
        return None

    raw_names = _items(doc.get("author_name"))
    raw_keys = _items(doc.get("author_key"))
    authors = []
    for index, value in enumerate(raw_names):
        name = _text(value)
        key_value = raw_keys[index] if index < len(raw_keys) else ""
        key_match = AUTHOR_ID.fullmatch(str(key_value or ""))
        authors = _merge_authors(authors, [{"id": key_match.group(1) if key_match else "", "name": name}])
    for item in _items(doc.get("authors")):
        author = item.get("author", item) if isinstance(item, dict) else {}
        if isinstance(author, dict):
            authors = _merge_authors(authors, [author])

    cover_id = doc.get("cover_i", doc.get("coverId"))
    if cover_id in (None, ""):
        covers = _items(doc.get("covers"))
        cover_id = next((cover for cover in covers if cover not in (None, "")), None)
    cover_edition = doc.get("cover_edition_key") or doc.get("coverEditionKey") or ""
    small, large = cover_urls(cover_id, cover_edition)
    subjects = [name for name in (_text(value) for value in _items(doc.get("subject", doc.get("subjects"))) if _text(value))]
    languages = []
    for value in _items(doc.get("language", doc.get("languages"))):
        language = str(value or "").rsplit("/", 1)[-1].lower()
        if language and language not in languages:
            languages.append(language)
    average = doc.get("ratings_average", doc.get("ratingAverage"))
    try:
        average = round(float(average), 1) if average not in (None, "") else None
        if average is not None and (not math.isfinite(average) or not 0 <= average <= 5):
            average = None
    except (TypeError, ValueError):
        average = None
    count = doc.get("ratings_count", doc.get("ratingCount"))
    try:
        count = int(count) if count not in (None, "") else 0
        count = max(0, count)
    except (TypeError, ValueError):
        count = 0
    first_year = doc.get("first_publish_year") or doc.get("firstPublishYear")
    try:
        first_year = int(first_year) if first_year not in (None, "") else None
    except (TypeError, ValueError):
        first_year = None
    try:
        editions = int(doc.get("edition_count") or doc.get("editionCount") or 0)
    except (TypeError, ValueError):
        editions = 0

    record = {
        "id": match.group(1),
        "title": _text(doc.get("title")) or "Untitled work",
        "authors": authors[:12],
        "firstPublishYear": first_year,
        "coverId": str(cover_id) if cover_id not in (None, "") else "",
        "coverEditionKey": str(cover_edition) if cover_edition else str(doc.get("coverEditionKey") or ""),
        "coverSmall": small or str(doc.get("coverSmall") or ""),
        "coverLarge": large or str(doc.get("coverLarge") or ""),
        "subjects": subjects[:12],
        "subjectCount": len(subjects),
        "editionCount": editions,
        "languages": languages[:8],
        "ratingAverage": average,
        "ratingCount": count,
        "ebookAccess": _text(doc.get("ebook_access") or doc.get("ebookAccess")),
        "hasFulltext": bool(doc.get("has_fulltext", doc.get("hasFulltext", False))),
        "description": _text(doc.get("description")),
        "openLibraryUrl": f"https://openlibrary.org/works/{match.group(1)}",
    }
    return record


def normalize_edition(doc):
    if not isinstance(doc, dict):
        return None
    key = str(doc.get("key") or "")
    match = re.fullmatch(r"(?:/books/)?(OL\d+M)", key)
    if not match:
        return None
    cover_id = next((cover for cover in _items(doc.get("covers")) if cover not in (None, "")), None)
    cover, _ = cover_urls(cover_id)
    languages = []
    for language in _items(doc.get("languages")):
        code = language.get("key", "") if isinstance(language, dict) else language
        normalized = str(code or "").rsplit("/", 1)[-1].lower()
        if normalized:
            languages.append(normalized)
    publishers = [name for name in (_text(item) for item in _items(doc.get("publishers"))) if name]
    isbn = [str(value) for field in ("isbn_13", "isbn_10") for value in _items(doc.get(field)) if value]
    publish_date = _text(doc.get("publish_date"))
    year_match = re.search(r"\b(?:1[0-9]{3}|20[0-9]{2}|21[0-9]{2})\b", publish_date)
    pages = doc.get("number_of_pages")
    try:
        pages = int(pages) if pages not in (None, "") else None
    except (TypeError, ValueError):
        pages = None
    return {
        "id": match.group(1),
        "title": _text(doc.get("title")) or "Untitled edition",
        "year": int(year_match.group(0)) if year_match else None,
        "publishDate": publish_date,
        "languages": list(dict.fromkeys(languages))[:5],
        "publishers": publishers[:3],
        "isbn": list(dict.fromkeys(isbn))[:4],
        "format": _text(doc.get("physical_format") or doc.get("format")),
        "pages": pages,
        "cover": cover,
        "ebookAccess": _text(doc.get("ebook_access")),
    }


def normalize_author(doc, requested_id):
    doc = doc if isinstance(doc, dict) else {}
    identifier = author_id(requested_id)
    photos = _items(doc.get("photos"))
    image = ""
    if photos:
        image = f"https://covers.openlibrary.org/a/id/{urllib.parse.quote(str(photos[0]), safe='')}-M.jpg?default=false"
    return {
        "id": identifier,
        "name": _text(doc.get("name")) or "Unknown author",
        "biography": _text(doc.get("bio")),
        "birthDate": _text(doc.get("birth_date")),
        "deathDate": _text(doc.get("death_date")),
        "image": image,
        "openLibraryUrl": f"https://openlibrary.org/authors/{identifier}",
    }


class BooksBackend:
    def __init__(self, config=CONFIG, data=DATA, cache=CACHE, request=None):
        self.config_path = Path(config)
        self.data = Path(data)
        self.cache = Path(cache)
        self.data.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.cache.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.data_db = self.data / "library.sqlite"
        self.cache_db = self.cache / "cache.sqlite"
        self._write_lock = threading.RLock()
        self._rate_lock = threading.Lock()
        self._last_request = 0.0
        self._request_override = request
        with self.db(self.data_db) as db:
            db.execute("CREATE TABLE IF NOT EXISTS favorites (work_id TEXT PRIMARY KEY, value TEXT NOT NULL, updated REAL NOT NULL)")
        with self.db(self.cache_db) as db:
            db.execute("CREATE TABLE IF NOT EXISTS cache (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated REAL NOT NULL)")

    @contextmanager
    def db(self, path):
        connection = sqlite3.connect(path, timeout=20)
        try:
            with connection:
                yield connection
        finally:
            connection.close()

    def contact(self):
        if not self.config_path.exists():
            return ""
        try:
            config = json.loads(self.config_path.read_text())
        except (OSError, ValueError):
            raise BooksError("Cannot read books.json. Check the JSON syntax.") from None
        if not isinstance(config, dict):
            raise BooksError("books.json must contain a JSON object.")
        contact = config.get("contact", "")
        if not isinstance(contact, str) or "\n" in contact or "\r" in contact:
            raise BooksError("The optional contact in books.json must be a single line of text.")
        return contact.strip()

    def _request_interval(self):
        return 0.36 if self.contact() else 1.02

    def request(self, path, params=None):
        if self._request_override:
            return self._request_override(path, params or {})
        interval = self._request_interval()
        with self._rate_lock:
            wait = self._last_request + interval - time.monotonic()
            if wait > 0:
                time.sleep(wait)
            self._last_request = time.monotonic()
        url = BASE + path
        if params:
            url += "?" + urllib.parse.urlencode({key: value for key, value in params.items() if value is not None}, doseq=True)
        contact = self.contact()
        user_agent = "Zephyrus Shell Books/1.0" + (f" ({contact})" if contact else "")
        request = urllib.request.Request(url, headers={"User-Agent": user_agent, "Accept": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=18) as response:
                payload = json.load(response)
                if not isinstance(payload, dict):
                    raise BooksError("Open Library returned an unexpected response.")
                return payload
        except urllib.error.HTTPError as error:
            code = error.code
            error.close()
            if code == 429:
                raise BooksError("Open Library is busy. Wait a moment, then retry.") from None
            if code == 404:
                raise BooksError("Open Library does not have this record.") from None
            if code == 422:
                raise BooksError("Open Library could not interpret this search. Adjust the query or filters.") from None
            raise BooksError(f"Open Library returned HTTP {code}. Try again later.") from None
        except (OSError, ValueError):
            raise BooksError("Cannot reach Open Library. Check your connection and retry.") from None

    def get_cache(self, key, ttl=None):
        with self.db(self.cache_db) as db:
            row = db.execute("SELECT value, updated FROM cache WHERE key=?", (key,)).fetchone()
        if not row or (ttl is not None and time.time() - row[1] >= ttl):
            return None
        try:
            return json.loads(row[0])
        except ValueError:
            return None

    def get_any_cache(self, key):
        return self.get_cache(key)

    def put_cache(self, key, value):
        with self._write_lock, self.db(self.cache_db) as db:
            db.execute("INSERT OR REPLACE INTO cache VALUES (?,?,?)", (key, json.dumps(value, ensure_ascii=False), time.time()))
        return value

    def _stored_favorites(self):
        with self.db(self.data_db) as db:
            rows = db.execute("SELECT work_id,value FROM favorites").fetchall()
        records = []
        for identifier, payload in rows:
            try:
                book = json.loads(payload)
            except ValueError:
                continue
            book = merge_book(book, {})
            book["favorite"] = True
            records.append(book)
        return records

    def _is_favorite(self, identifier):
        with self.db(self.data_db) as db:
            row = db.execute("SELECT 1 FROM favorites WHERE work_id=?", (work_id(identifier),)).fetchone()
        return bool(row)

    def _save_favorite(self, book, favorite):
        normalized = normalize_work(book)
        if not normalized:
            raise BooksError("This selection does not have a valid Open Library Work ID.")
        identifier = normalized["id"]
        cached = self.get_any_cache("work:" + identifier)
        if isinstance(cached, dict):
            normalized = merge_book(normalized, cached)
        with self._write_lock, self.db(self.data_db) as db:
            row = db.execute("SELECT value FROM favorites WHERE work_id=?", (identifier,)).fetchone()
            if row:
                try:
                    normalized = merge_book(json.loads(row[0]), normalized)
                except ValueError:
                    pass
            if favorite:
                normalized["favorite"] = True
                db.execute("INSERT OR REPLACE INTO favorites VALUES (?,?,?)", (identifier, json.dumps(normalized, ensure_ascii=False), time.time()))
            else:
                db.execute("DELETE FROM favorites WHERE work_id=?", (identifier,))
        return {"favorite": bool(favorite)}

    def browse(self, request):
        query = str(request.get("query") or "").strip()
        filters = request.get("filters") if isinstance(request.get("filters"), dict) else {}
        offset = max(0, int(request.get("offset") or 0))
        if request.get("favorites"):
            terms = query.casefold()
            items = self._stored_favorites()
            if terms:
                items = [book for book in items if terms in " ".join([book.get("title", ""), *[a.get("name", "") for a in book.get("authors", [])]]).casefold()]
            return {"items": items, "next": "", "total": len(items)}

        key = browse_cache_key(query, filters, offset)
        ttl = SEARCH_TTL if query or any(value for value in filters.values()) else CATALOGUE_TTL
        cached = self.get_cache(key, ttl)
        if cached and not request.get("refresh"):
            return cached
        stale = self.get_any_cache(key)
        try:
            result = self._fetch_browse(query, filters, offset)
            return self.put_cache(key, result)
        except BooksError:
            if stale:
                return stale | {"warning": "Open Library is temporarily unavailable. Showing saved results."}
            raise

    def _fetch_browse(self, query, filters, offset):
        clauses = []
        if query:
            clauses.append(f"({escape_search_term(query)})")
        else:
            clauses.append("*:*" )
        subject = str(filters.get("subject") or "").strip()
        if subject:
            quoted = subject.replace("\\", "\\\\").replace('"', '\\"')
            clauses.append(f'subject:"{quoted}"')
        language = str(filters.get("language") or "").strip().lower()
        if language:
            if not re.fullmatch(r"[a-z]{3}", language):
                raise BooksError("Use a three-letter ISO 639-2 code for language, such as eng or spa.")
            clauses.append(f"language:{language}")
        low, high = str(filters.get("minYear") or "").strip(), str(filters.get("maxYear") or "").strip()
        if low or high:
            for value in (low, high):
                if value and not re.fullmatch(r"\d{4}", value):
                    raise BooksError("Publication years must be four digits.")
            clauses.append(f"first_publish_year:[{low or '*'} TO {high or '*'}]")
        sort = str(filters.get("sort") or ("relevance" if query else "trending"))
        sort_value = {"trending": "trending", "newest": "new", "oldest": "old", "relevance": ""}.get(sort)
        if sort_value is None:
            sort, sort_value = "trending", "trending"
        params = {
            "q": " AND ".join(clauses),
            "fields": FIELDS,
            "limit": PAGE_SIZE,
            "offset": offset,
        }
        if sort_value:
            params["sort"] = sort_value
        payload = self.request("/search.json", params)
        docs = payload.get("docs") if isinstance(payload, dict) else []
        items = []
        for doc in docs if isinstance(docs, list) else []:
            book = normalize_work(doc)
            if book:
                items.append(book)
        try:
            total = int(payload.get("num_found", payload.get("numFound", 0)))
        except (TypeError, ValueError):
            total = 0
        next_offset = offset + PAGE_SIZE if len(docs or []) >= PAGE_SIZE and offset + len(docs or []) < total else None
        return {"items": items, "next": str(next_offset) if next_offset is not None else "", "total": total}

    def snapshot(self, request):
        if request.get("favorites"):
            return self.browse(request)
        query = str(request.get("query") or "").strip()
        filters = request.get("filters") if isinstance(request.get("filters"), dict) else {}
        offset = max(0, int(request.get("offset") or 0))
        return self.get_any_cache(browse_cache_key(query, filters, offset))

    def details(self, request):
        selected = request.get("book") or {}
        identifier = work_id(selected.get("id"))
        key = "work:" + identifier
        cached = self.get_cache(key, DETAIL_TTL)
        if cached and not request.get("refresh"):
            return merge_book(normalize_work(selected) or {}, cached)
        stale = self.get_any_cache(key)
        try:
            payload = self.request(f"/works/{identifier}.json")
            details = normalize_work(payload | {"key": identifier}) or {}
            details["description"] = _text(payload.get("description"))
            details["first_sentence"] = _text(payload.get("first_sentence"))
            details["workType"] = _text((payload.get("type") or {}).get("key", "")).rsplit("/", 1)[-1]
            details = merge_book(normalize_work(selected) or {}, details)
            result = self.put_cache(key, details)
            if self._is_favorite(identifier):
                self._save_favorite(result, True)
            return result
        except BooksError:
            if stale:
                return merge_book(normalize_work(selected) or {}, stale) | {"warning": "Showing saved book details."}
            raise

    def author_details(self, request):
        person = request.get("author") or {}
        identifier = author_id(person.get("id"))
        key = "author:" + identifier
        cached = self.get_cache(key, DETAIL_TTL)
        if cached and not request.get("refresh"):
            return cached
        stale = self.get_any_cache(key)
        try:
            result = normalize_author(self.request(f"/authors/{identifier}.json"), identifier)
            return self.put_cache(key, result)
        except BooksError:
            if stale:
                return stale | {"warning": "Showing saved author details."}
            raise

    def author_works(self, request):
        person = request.get("author") or {}
        identifier = author_id(person.get("id"))
        offset = max(0, int(request.get("offset") or 0))
        def with_author(result):
            known = self.get_any_cache("author:" + identifier) or person
            name = _text(known.get("name")) or _text(person.get("name"))
            context = [{"id": identifier, "name": name}]
            return result | {"items": [book | {"authors": _merge_authors(book.get("authors"), context)}
                                        for book in result.get("items", [])]}
        key = f"author-works:{identifier}:{offset}"
        cached = self.get_cache(key, SEARCH_TTL)
        if cached and not request.get("refresh"):
            return with_author(cached)
        stale = self.get_any_cache(key)
        try:
            payload = self.request(f"/authors/{identifier}/works.json", {"limit": PAGE_SIZE, "offset": offset})
            rows = payload.get("entries", payload.get("docs", []))
            rows = rows if isinstance(rows, list) else []
            items = [book for book in (normalize_work(row) for row in rows) if book]
            size = payload.get("size", payload.get("numFound", payload.get("num_found", 0)))
            try:
                size = int(size)
            except (TypeError, ValueError):
                size = 0
            count = len(rows) if isinstance(rows, list) else 0
            has_more = offset + count < size if size else count >= PAGE_SIZE
            next_offset = offset + count if count and has_more else None
            return self.put_cache(key, with_author({"items": items, "next": str(next_offset) if next_offset is not None else "", "total": size}))
        except BooksError:
            if stale:
                return with_author(stale) | {"warning": "Showing saved author works."}
            raise

    def editions(self, request):
        identifier = work_id((request.get("book") or {}).get("id"))
        offset = max(0, int(request.get("offset") or 0))
        key = f"editions:{identifier}:{offset}"
        cached = self.get_cache(key, DETAIL_TTL)
        if cached and not request.get("refresh"):
            return cached
        stale = self.get_any_cache(key)
        try:
            payload = self.request(f"/works/{identifier}/editions.json", {"limit": EDITION_PAGE_SIZE, "offset": offset})
            rows = payload.get("entries", payload.get("docs", []))
            rows = rows if isinstance(rows, list) else []
            items = [edition for edition in (normalize_edition(row) for row in rows) if edition]
            size = payload.get("size", payload.get("numFound", payload.get("num_found", 0)))
            try:
                size = int(size)
            except (TypeError, ValueError):
                size = 0
            count = len(rows) if isinstance(rows, list) else 0
            has_more = offset + count < size if size else count >= EDITION_PAGE_SIZE
            next_offset = offset + count if count and has_more else None
            return self.put_cache(key, {"items": items, "next": str(next_offset) if next_offset is not None else "", "total": size})
        except BooksError:
            if stale:
                return stale | {"warning": "Showing saved editions."}
            raise

    def personal(self, request):
        identifier = work_id((request.get("book") or {}).get("id"))
        return {"favorite": self._is_favorite(identifier)}

    def handle(self, request):
        op = request.get("op", "")
        if op == "init":
            contact = self.contact()
            return {"pageSize": PAGE_SIZE, "contactConfigured": bool(contact)}
        if op == "snapshot":
            return self.snapshot(request)
        if op == "browse":
            return self.browse(request)
        if op == "details":
            return self.details(request)
        if op == "authorDetails":
            return self.author_details(request)
        if op == "authorWorks":
            return self.author_works(request)
        if op == "editions":
            return self.editions(request)
        if op == "personal":
            return self.personal(request)
        if op == "save":
            return self._save_favorite(request.get("book") or {}, bool(request.get("favorite")))
        raise BooksError("Unknown Books request.")


def merge_book(base, update):
    """Merge hydrated Work fields without erasing useful catalogue metadata."""
    result = dict(base or {})
    result["authors"] = _merge_authors(result.get("authors"))
    for key, value in (update or {}).items():
        if key == "authors" and isinstance(value, list):
            result["authors"] = _merge_authors(result.get("authors"), value)[:12]
            continue
        if key in ("editionCount", "ratingCount") and value == 0 and result.get(key, 0) > 0:
            continue
        if key == "hasFulltext" and value is False and result.get(key) is True:
            continue
        if value not in (None, "", [], {}):
            result[key] = value
    if result.get("id"):
        result["id"] = work_id(result["id"])
        result["openLibraryUrl"] = f"https://openlibrary.org/works/{result['id']}"
    return result


def browse_cache_key(query, filters, offset):
    query_text = str(query or "").strip()
    safe_filters = {key: str(value) for key, value in sorted((filters or {}).items()) if value not in (None, "")}
    if not safe_filters.get("sort"):
        safe_filters["sort"] = "relevance" if query_text else "trending"
    return "browse:" + json.dumps([query_text, safe_filters, int(offset)], sort_keys=True, ensure_ascii=False)


def main():
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from services.worker import serve
    backend = BooksBackend()
    serve(backend.handle, errors=(BooksError,), latest=("browse", "details", "authorDetails", "authorWorks", "editions", "personal"), controls=("save",))


if __name__ == "__main__":
    main()
