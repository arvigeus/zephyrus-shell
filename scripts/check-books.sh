#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
books_test_root=$(mktemp -d)
trap 'rm -rf -- "$books_test_root"' EXIT
export XDG_CONFIG_HOME="$books_test_root/config" XDG_DATA_HOME="$books_test_root/data" XDG_CACHE_HOME="$books_test_root/cache"
export XDG_DOCUMENTS_DIR="$books_test_root/documents"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
mkdir -p "$XDG_CONFIG_HOME/zephyrus-shell" tests/artifacts
python3 - <<'PY'
import sys
from pathlib import Path

sys.path.insert(0, "books")
from backend import BooksBackend, browse_cache_key

backend = BooksBackend()
art_root = backend.cache
art = []
colors = [("#173540", "#cda989"), ("#302c4c", "#eaa2a1"), ("#4c3326", "#dfbd6c")]
for index, (background, accent) in enumerate(colors):
    cover = art_root / f"fixture-{index}.svg"
    cover.write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="600" height="900">'
        f'<rect width="600" height="900" fill="{background}"/>'
        f'<path d="M70 110h460v680H70z" fill="none" stroke="{accent}" stroke-width="12"/>'
        f'<circle cx="300" cy="360" r="118" fill="{accent}" opacity=".8"/>'
        f'<path d="M110 650h380M150 700h300" stroke="{accent}" stroke-width="15"/></svg>'
    )
    art.append(cover.as_uri())

def book(identifier, title, author=None, image="", year=None, description=""):
    authors = [{"id": author[0], "name": author[1]}] if author else []
    return {
        "id": identifier, "title": title, "authors": authors,
        "firstPublishYear": year, "coverId": "", "coverEditionKey": "",
        "coverSmall": image, "coverLarge": image, "subjects": ["Computing", "History"],
        "subjectCount": 2, "editionCount": 8, "languages": ["eng", "fre"],
        "ratingAverage": 4.3, "ratingCount": 12, "ebookAccess": "public",
        "hasFulltext": True, "description": description,
        "openLibraryUrl": f"https://openlibrary.org/works/{identifier}",
    }

ada = ("OL1A", "Ada Lovelace")
items = [
    book("OL100W", "The Example Book", ada, art[0], 1843, "A fixture synopsis for the selected work."),
    book("OL101W", "A Work without a Cover", None, "", 1901),
    book("OL102W", "Letters and Logic", ada, art[1], 1912),
    book("OL103W", "Notes from a Library", None, art[2], 1930),
]
backend.put_cache(browse_cache_key("", {}, 0), {"items": items, "next": "", "total": len(items)})
for item in items:
    backend.put_cache("work:" + item["id"], item)
backend.put_cache("author:OL1A", {
    "id": "OL1A", "name": "Ada Lovelace", "biography": "Fixture mathematician and writer.",
    "birthDate": "10 December 1815", "deathDate": "27 November 1852",
    "image": art[1], "openLibraryUrl": "https://openlibrary.org/authors/OL1A",
})
backend.put_cache("author-works:OL1A:0", {
    "items": [book("OL200W", "Notes on the Analytical Engine", ada, art[2], 1843)],
    "next": "", "total": 1,
})
backend.put_cache("editions:OL100W:0", {
    "items": [{
        "id": "OL100M", "title": "The Example Book", "year": 2001,
        "publishDate": "2001, revised printing", "languages": ["eng"],
        "publishers": ["Example Press"], "isbn": ["9780000000001"],
        "format": "Hardcover", "pages": 312, "cover": art[0], "ebookAccess": "public",
    }],
    "next": "", "total": 1,
})
from media.local import LocalLibrary
from media.backend import DATA
local_book = art_root / "local-book.epub"
local_book.write_bytes(b"local book fixture")
LocalLibrary(DATA).add({"kind": "book", "id": "OL100W", "title": "The Example Book",
                       "author": "Ada Lovelace"}, local_book, move=True)
PY
timeout 25s dbus-run-session quickshell -p "$PWD/books-smoke.qml" --no-color > "$books_test_root/log" 2>&1 || { cat "$books_test_root/log"; exit 1; }
cat "$books_test_root/log"
rg -q 'BOOKS PASS' "$books_test_root/log"
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|BOOKS FAIL' "$books_test_root/log"; then exit 1; fi
test -s tests/artifacts/books-rail.png
test -s tests/artifacts/books-grid.png
