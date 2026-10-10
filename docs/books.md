# Books

Books browses [Open Library](https://openlibrary.org): trending works, search
(titles, authors, ISBNs), subject/language/year filters, work details, authors,
editions, and Favorites. No account or API key is needed. Optional command
providers can add **Read online** and direct downloads. The **Local** view and
qBittorrent search under **Find** are described in
[Local library and qBittorrent](torrents.md).

## Configuration

Everything is optional. `$XDG_CONFIG_HOME/zephyrus-shell/books.json`
(default `~/.config/zephyrus-shell/books.json`), see
[books.example.json](../modules/books/books.example.json):

```json
{
  "contact": "reader@example.org",
  "providers": []
}
```

- `contact` — a single line, usually an email, sent in the User-Agent. Open
  Library allows about one request per second anonymously and three with a
  contact; Books paces requests accordingly (1.02 s or 0.36 s apart).
- `providers` — command providers, described below.

## Files

| What | Where |
| --- | --- |
| Favorites (with their last saved metadata) | `$XDG_DATA_HOME/zephyrus-shell/books/library.sqlite` |
| Response cache | `$XDG_CACHE_HOME/zephyrus-shell/books/cache.sqlite` |
| Rail/grid choice | `$XDG_CONFIG_HOME/zephyrus-shell/books-ui.ini` |
| Downloaded books | `$XDG_DOCUMENTS_DIR/Books/Author/Title (Year)/Title (Year).ext` |

Trending pages are refreshed after 6 hours, searches and author works after a
day, and work details and editions after 30 days. A cached page is shown
immediately while the fresh one loads, and saved data is shown with a warning
when Open Library is unreachable. Cache entries not refreshed for 90 days are
removed when Books starts.

## Using it

- Filters: subject is free text; language is a three-letter ISO 639-2 code
  (`eng`, `spa`); years filter the work's first publication year; sort is
  Trending, Relevance, Newest first, or Oldest first.
- Click an author to see their profile and other works. The Editions tab lists
  publishers, ISBNs, formats, and page counts.
- The Open Library button opens the work on openlibrary.org; its label says
  Read, Borrow, or Preview when Open Library offers that access.
- Open Library data is uneven: covers, authors, synopses, and ratings may be
  missing.

## Command providers

A provider is a program you install yourself. Books runs it directly (no
shell) with one JSON request on stdin and reads exactly one JSON object from
stdout. Diagnostics go to stderr. Each call has a 25-second timeout; the
command and its children are killed on timeout and when Books closes.

```json
{
  "providers": [
    {"name": "My provider", "command": ["python3", "/path/to/provider.py"], "env": {"API_TOKEN": "..."}},
    {"name": "Packaged provider", "plugin": "/path/to/provider-plugin", "env_file": "settings.env"}
  ]
}
```

- `name` — unique, single line.
- `command` — nonempty argument array. Or use `plugin` instead (not both).
- `plugin` — a directory containing `manifest.json`:
  `{"api_version": 1, "command": ["python3", "{plugin_dir}/provider.py"]}`.
  `{plugin_dir}` becomes the directory's absolute path. Relative plugin paths
  are resolved against the directory containing `books.json`. See the
  [example manifest](../modules/books/provider-plugin.example/manifest.json).
- `env_file` — literal `NAME=value` lines (`export`, comments, and quoted
  values allowed; nothing is expanded). Relative to the plugin directory, or to
  the `books.json` directory for `command` entries. Read on every call.
- `env` — string values; these override `env_file`, which overrides the
  inherited environment.

Keep secrets in `env` or `env_file`, never in arguments, and `chmod 600` those
files. Configured environment values and URLs are removed from error messages.

### Protocol

Search (`page` is zero-based):

```json
{"op": "search", "query": "Example book", "page": 0, "limit": 10}
```

```json
{"success": true, "results": [
  {"id": "a", "title": "Example book", "authors": ["Example Writer"], "format": "epub",
   "size_bytes": 2048000, "identifiers": {"isbn_13": ["9780306406157"]}, "ref": {"file": "a"}}
]}
```

Each result needs a nonempty `title` and a `ref` (any JSON value); `authors` is
an optional string array. Optional: `id`, `year`, `format`, `language`,
`publisher`, `pages`, `identifiers` (a list of ISBNs or an object with `isbn`,
`isbn_10`, `isbn_13`), `size_bytes`, `size`, `cover_url`, `description`,
`page_url`. Return one result per file format.

Resolve (`purpose` is `read` or `download`):

```json
{"op": "resolve", "ref": {"file": "a"}, "purpose": "download"}
```

```json
{"success": true, "url": "https://example.org/book.epub"}
```

The URL must be http(s) without embedded credentials. Resolved URLs are never
cached or logged. Any request may fail with
`{"success": false, "error": "Short reason"}`, with any exit code.

### What uses providers

- **Read online** (shown only when providers are configured) searches providers
  for the selected work using up to three ISBNs from its first 72 editions, then
  the title and authors. Offers match on ISBN (ISBN-10 and ISBN-13 are
  equivalent); without any edition ISBNs, they need the exact title and an exact
  author. One match opens directly; several appear in the button's menu.
- **Find** searches providers with its editable query next to qBittorrent.
  **Download** resolves a fresh URL, streams the file into the books library,
  and shows progress, cancel, and retry in Activity. HTML responses, unknown
  formats, incomplete transfers, and existing files at the destination fail
  the download. Only offers that match the selected work as above are filed
  under it; others keep their own title and author.

One provider failing does not hide another's results.

## Limitations

- No embedded reader; reading always opens a browser.
- Open Library subject search is fuzzy, and its data can lag.
