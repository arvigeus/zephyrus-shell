# Books

The **Local** view and title-aware qBittorrent search for public domain books
or books authorized for AI training are described in [Local library and qBittorrent](torrents.md).

Books is a desktop discovery browser backed by Open Library. It opens on current
trending works, with searchable catalogue pages, subject/language/first-publication
filters, cover rail and grid layouts, selected-work details, navigable authors,
lazy editions, persistent Favorites, and a subdued selected-cover backdrop. A
catalogue record is an Open Library **Work**; editions are shown only after opening
the Editions tab.

No API key or account is required. Search uses Open Library's Work-level Search
API, with Trending for discovery and Relevance as the default for free-text searches.
Open Library also exposes weekly trending books, but the Search API's compact field
selection makes it a better fit for the catalogue and its filters. Selecting a work loads its description. Author profiles,
author works, and edition pages are fetched only when opened.

## Storage and cache

- User configuration: `$XDG_CONFIG_HOME/zephyrus-shell/books.json`
  (default `~/.config/zephyrus-shell/books.json`). An optional `contact` string,
  usually an email address, identifies Open Library requests. An optional
  `providers` list configures generic external commands, described below.
  Existing contact-only configuration continues to work.
- Favorites and their last saved Work metadata:
  `$XDG_DATA_HOME/zephyrus-shell/books/library.sqlite`
  (default `~/.local/share/zephyrus-shell/books/library.sqlite`).
- Catalogue snapshots, Work details, author records, author-work pages, and edition
  pages: `$XDG_CACHE_HOME/zephyrus-shell/books/cache.sqlite`
  (default `~/.cache/zephyrus-shell/books/cache.sqlite`). Trending pages are kept
  for six hours, searches for a day, and selected detail records for 30 days. A
  cached snapshot appears before refresh; saved Favorites remain available offline.
- Selected layout: `$XDG_CONFIG_HOME/zephyrus-shell/books-ui.ini`.

The worker identifies itself as `Zephyrus Shell Books`. Open Library currently asks
anonymous API clients to stay at one request per second. Adding a contact in
`books.json` identifies the client and raises that documented limit to three per
second. The worker enforces these shared limits, debounces rapid selection changes,
and caches responses. Cover images are loaded from Open Library's hosted Covers API;
missing covers remain a title card.

## Filters and data limits

- Subject is a free-text query because Open Library's subject tags are community
  supplied and do not form a fixed, hierarchical list.
- Language accepts a three-letter ISO 639-2 code such as `eng` or `spa`.
- Year bounds filter the Work's `first_publish_year`, rather than mixing in the
  publication dates of individual editions.
- Sort choices are trending, relevance, newest first, and oldest first. The module
  defaults to relevance while searching and trending in Discover. The module does
  not present rating or edition-count sorts until their ordering is stable enough to
  promise consistently.

Open Library records are incomplete and uneven. A Work may have no author, cover,
synopsis, subjects, ratings, or known edition count. Work-level ratings are shown
when indexed. Publisher, ISBN, format, and page count appear only on edition rows,
where those fields apply. Open Library reading actions appear when the catalogue has a known
public, borrowable, or print-disabled-preview access class and send the user to the
Open Library Work page so Open Library can apply its own access rules.

## Command providers

Providers are user-owned commands with a JSON interface. The shell has no
catalogue-specific adapters, credentials, or query syntax. Configuration and any
provider dependencies stay outside the repository. See
[`books.example.json`](../books/books.example.json) for placeholder configuration:

```json
{
  "contact": "reader@example.org",
  "providers": [
    {
      "name": "Personal provider",
      "command": ["python3", "/absolute/path/to/book-command.py"],
      "env": {}
    }
  ]
}
```

Names must be unique, nonempty single lines. `command` must be a nonempty array
of arguments; commands run directly without a shell. Optional `env` maps arbitrary
environment names to string values and overrides the inherited subprocess
environment. Keep credentials in this private mapping or let the external command
load its own private environment file. Never put credentials in command arguments.
Protect configuration containing secrets with file mode `600`. The shell never
interprets credential variable names.

### Provider plugins

A Books provider plugin is a user-installed directory containing `manifest.json`,
its command, and any command-owned resources. Books loads only explicitly configured
packages; it does not scan directories or import third-party Python into the worker.
The manifest declares the generic command protocol version and argument array:

```json
{
  "api_version": 1,
  "command": ["python3", "{plugin_dir}/provider.py"]
}
```

`{plugin_dir}` is replaced with the package's absolute directory in each argument;
it works with paths containing spaces and does not invoke a shell. See the
[example manifest](../books/provider-plugin.example/manifest.json). Install the
package anywhere in your private files and add this entry to `books.json`:

```json
{
  "name": "Personal provider",
  "plugin": "/absolute/path/to/provider-plugin",
  "env_file": "/absolute/path/to/private-settings.env",
  "env": {}
}
```

Choose either `plugin` or `command` for an entry. Relative plugin paths are resolved
against the directory containing `books.json`. Removing the entry disables the
plugin. Package dependencies belong to its command environment; Books does not
install dependencies automatically. Keep private settings out of distributed
packages.

Optional `env_file` works with both plugins and direct commands. Relative file
paths use the plugin directory, or the `books.json` directory for direct commands.
Files contain literal `NAME=value` assignments, optionally prefixed with `export`;
blank lines and comments are allowed. Quote values containing spaces. Variables
and command substitutions are never expanded. The subprocess environment merges
inherited values, then file values, then the entry's `env` overrides. Files are read
for each operation, so credential changes take effect without copying secrets into
`books.json`. Environment values are removed from diagnostics. Protect private
environment files with mode `600`.

Plugins and direct commands share the same runtime, matching, download jobs,
timeouts, and lifecycle. Manifest loading starts no command; execution remains on
demand. All external catalogue and account logic stays in the plugin command.

Each invocation receives one JSON request on stdin and must return exactly one JSON
object on stdout. Send diagnostics to stderr. Commands have a 25-second timeout;
timed-out commands and their children are terminated. Closing Books terminates
active provider commands. Failures appear beside the relevant action; one provider's
failure does not hide another provider's results. Diagnostics are shortened, with
configured environment values and URLs removed.

Search requests use zero-based pages and a default limit of 10:

```json
{"op":"search","query":"Example book","page":0,"limit":10}
```

The protocol also permits commands to accept search requests without `page` or
`limit`. A successful response contains one item per available edition/file format:

```json
{
  "success": true,
  "query": "Example book",
  "count": 2,
  "results": [
    {"id":"edition-a","title":"Example book","authors":["Example Writer"],"format":"epub","size_bytes":2048000,"identifiers":{"isbn_13":["9780306406157"]},"ref":{"file":"a"}},
    {"id":"edition-a","title":"Example book","authors":["Example Writer"],"format":"pdf","size":"4 MB","ref":{"file":"b"}}
  ]
}
```

Each result requires a nonempty `title`, string-array `authors` (or no authors),
and an opaque `ref`. Optional metadata includes `id`, `year`, `format`, `language`,
`publisher`, `pages`, `identifiers`, `size_bytes`, `size`, `cover_url`, `description`,
and `page_url`. ISBN identifiers may be a list of ISBN strings or an object with
`isbn`, `isbn_10`, or `isbn_13` values. Separate formats remain separate choices,
including when they share an ID. Reference values may be any JSON value.

Resolve requests pass the selected offer's reference back unchanged:

```json
{"op":"resolve","ref":{"file":"a"},"purpose":"download"}
```

```json
{"success":true,"url":"https://example.org/read"}
```

The optional generic `purpose` is `read` for **Read online** and `download` for
**Find → Download**. Commands that omit purpose handling can continue to return
their default URL; commands supporting both actions should resolve a fresh URL
for the requested use. The returned URL must be an HTTP(S) web URL without embedded
user credentials. Books resolves only after an offer is selected. Reading uses
the shared Books browser launcher; downloading streams the file into the local
library. Resolved URLs are never cached or logged; signed links can expire.
An external command may consume a provider allowance when it issues a URL,
even if saving the file later fails. Search and offer matching never request
resolution; download resolution starts only after choosing **Download**.
Provider search results and references stay in memory. Only Open Library metadata
is persisted in the catalogue cache. Either operation may return a failure object
with a concise explanation, including with a nonzero exit code:

```json
{"success":false,"error":"Service unavailable. Retry later."}
```

**Read online** looks up offers only when clicked for the selected Open Library
Work. Matching inspects up to the first 72 edition records, searches up to three
normalized ISBNs followed by the title and authors, and accepts exact ISBN matches.
Valid ISBN-10 values are also matched to their ISBN-13 equivalent. If those editions
have no ISBN, matching requires the exact normalized title and at least one exact
normalized author name; missing authors or weak title matches produce no offer.
Multiple providers or file formats appear in the existing split-button dropdown.
Refresh book details to retry availability.

**Find** searches configured commands alongside qBittorrent using its editable
query. Provider rows show their provider, format, size, and a **Download** control.
Downloads use the shared library importer and the same organized destination as
book torrents: `$XDG_DOCUMENTS_DIR/Books/Author/Title (Year)/Title (Year).ext`.
The Activity panel shows byte progress, cancellation, errors, and retry. Finished
or failed rows can be dismissed; plain status messages use desktop notifications
and Attention. Retry
resolves a new URL. Selecting Desktop or another space keeps active transfers
running. Escape hides Books and preserves its state. The Spaces sidebar X
destroys the worker and cancels direct transfers.
Partial files are removed, existing library files are never replaced, and HTML
responses are reported as failed downloads. Completed files appear in Local.

Find results are independent offers. Only verified ISBN matches, or an exact title
and author match against cached editions without ISBNs, inherit the selected Work's
identity and destination. Other offers keep their own metadata and a separate local
identity. Opening those local records never requests Open Library details, authors,
editions, or Favorites. Provider IDs are never sent to Open Library or saved as
Work identities.

Run `python3 -m unittest discover -s tests -p 'test_book*.py'` and
`bash scripts/check-books.sh` to check the generic protocol and real module flows
using offline fixtures and isolated XDG storage.

The module makes no bulk requests and does not crawl Open Library pages or embed
a reader. Search metadata and edition availability can lag or
change, and Open Library's subject search is fuzzy. See the [official API guidance](https://openlibrary.org/developers/api),
[Search API](https://openlibrary.org/dev/docs/api/search),
[Work and Edition API](https://openlibrary.org/dev/docs/api/books),
[Authors API](https://openlibrary.org/dev/docs/api/authors), and
[Covers API](https://openlibrary.org/dev/docs/api/covers).
