#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
export XDG_DOCUMENTS_DIR="$SMOKE_ROOT/documents"
python3 - <<'PY'
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, "modules/books")
from backend import BooksBackend, browse_cache_key

backend = BooksBackend()
art_root = backend.cache
package = backend.config_path.parent / "book-providers" / "fixture plugin"
package.mkdir(parents=True)
shutil.copyfile("tests/fixtures/books/command-provider.py", package / "provider.py")
(package / "manifest.json").write_text(json.dumps({"api_version": 1, "command": [sys.executable, "{plugin_dir}/provider.py"]}))
(package / "settings.env").write_text('FIXTURE_ROOT="' + str(art_root) + '"\n')
backend.config_path.write_text(json.dumps({"contact": "reader@example.org", "providers": [{
    "name": "Fixture provider", "plugin": str(package), "env_file": "settings.env", "env": {},
}]}))
launcher = art_root / "browser-fixture.py"
launcher.write_text('import os, sys\nfrom pathlib import Path\nassert sys.argv[-1] == "https://example.org/read?token=short-lived"\n(Path(os.environ["XDG_CACHE_HOME"])/"browser-opened").write_text("opened")\n')
(backend.config_path.parent / "browser.json").write_text(json.dumps({"modules": {"books": [sys.executable, str(launcher)]}}))
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
from modules.media.local import LocalLibrary
from modules.media.backend import DATA
local_book = art_root / "local-book.epub"
local_book.write_bytes(b"local book fixture")
LocalLibrary(DATA).add({"kind": "book", "id": "OL100W", "title": "The Example Book",
                       "author": "Ada Lovelace"}, local_book, move=True)
provider_book = art_root / "provider-book.epub"
provider_book.write_bytes(b"provider local fixture")
LocalLibrary(DATA).add({"kind": "book", "source": "provider", "id": "book-command:fixture",
                       "title": "Provider-only fixture", "author": "Example Writer",
                       "authors": [{"id": "", "name": "Example Writer"}],
                       "description": "Standalone provider metadata."}, provider_book, move=True)
PY
start_fixture qbittorrent python3 tests/fixtures/media-qbittorrent.py
wait_for "$XDG_CONFIG_HOME/zephyrus-shell/torrents.json"
start_fixture downloads python3 tests/fixtures/books/download-server.py
wait_for "$XDG_CONFIG_HOME/zephyrus-shell/book-download-ready"
run_smoke books "BOOKS" 30s
test -s tests/artifacts/books-rail.png
test -s tests/artifacts/books-grid.png
python3 - <<'PY'
import json, os, time
from pathlib import Path
root = Path(os.environ["XDG_CACHE_HOME"])
for _ in range(30):
    if (root / "browser-opened").exists(): break
    time.sleep(0.1)
assert (root / "browser-opened").read_text() == "opened"
books = root / "zephyrus-shell/books"
assert (books / "resolve-calls").read_text().splitlines() == ["called", "called"]
assert json.loads((books / "resolved-ref.json").read_text()) == {"file": "pdf"}
from modules.media.local import library_root
download = library_root("book") / "Ada Lovelace/The Example Book (1843)/The Example Book (1843).pdf"
assert download.read_bytes().startswith(b"%PDF-1.7")
assert download.with_suffix(".pdf.zephyrus.json").exists()
print("BOOKS PROVIDERS PASS: direct download, shared library destination/import, deferred online launch")
PY
