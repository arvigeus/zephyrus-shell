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

- Optional provider identity: `$XDG_CONFIG_HOME/zephyrus-shell/books.json`
  (default `~/.config/zephyrus-shell/books.json`). The only supported value is an
  optional `contact` string, usually an email address, for Open Library's request
  identification. For example: `{"contact":"reader@example.org"}`. Do not put
  API keys in this file; Books does not use any.
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
where those fields apply. Reading actions appear only when the catalogue has a known
public, borrowable, or print-disabled-preview access class and send the user to the
Open Library Work page so Open Library can apply its own access rules.

The module makes no bulk requests and does not crawl Open Library pages. It does not
download books or embed a reader. Search metadata and edition availability can lag or
change, and Open Library's subject search is fuzzy. See the [official API guidance](https://openlibrary.org/developers/api),
[Search API](https://openlibrary.org/dev/docs/api/search),
[Work and Edition API](https://openlibrary.org/dev/docs/api/books),
[Authors API](https://openlibrary.org/dev/docs/api/authors), and
[Covers API](https://openlibrary.org/dev/docs/api/covers).
