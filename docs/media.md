# Movies and TV Series

Local library and qBittorrent search for public domain media or material
authorized for AI training are documented in [Local library and qBittorrent](torrents.md).

Open **Spaces → Movies** or **Spaces → TV Series**. They are separate plugins
sharing the browser and provider service in `media/`. The shell's normal overlay
owns their lifecycle: Escape or selecting Desktop closes the module and stops its worker.

The default view has a detail area above a horizontal poster rail. The grid button
switches to posters on the left and details on the right. That preference is shared
by both modules. TV Series defaults to the grid until you choose a shared layout. Click a poster or navigate with arrow keys to select a
title. Search expands from the search icon. Filters expand inline beside their
button (scroll horizontally on narrower windows). They include genre, country,
year range, minimum rating/votes, and sort order. Apply commits filters;
Reset clears them. Search is debounced; pages append automatically near the end.
Favorites are separate from discovery and can be searched by title.

The ordinary genre choices follow TMDB's separate [movie](https://developer.themoviedb.org/reference/genre-movie-list)
and [TV](https://developer.themoviedb.org/reference/genre-tv-list) genre lists.
TV uses TMDB's combined labels such as **Action & Adventure** and
**Sci-Fi & Fantasy**. Biography and Sport are not TMDB genres, so they are not
offered as genre filters. **Anime** is the separate MAL catalogue choice in
both modules.

Reopening a saved catalogue displays its snapshot while refreshing in the background.
Selection displays the catalogue record immediately, then hydrates metadata and
artwork independently. Late responses cannot replace a newer selection. Image,
logo, and rating slots reserve space. Shared double-buffered image transitions
crossfade backgrounds, title logos, and poster replacements. Initial images appear immediately once decoded. Enriched artwork owns its fields,
so a late details response cannot revert the chosen image. A stable catalogue model appends rows without rebuilding existing cards or resetting scroll position. Artwork uses TMDB artwork with textless backdrops preferred, then MDBList's
backdrop when available. TMDB supplies title logos, preferring English. A missing
or failed logo falls back to the title text. Portrait posters are never stretched
into backdrops. The layout is inspired by the supplied Arctic Fuse screenshots;
no Kodi skin code or branding is included.

## Configuration and secrets

All API keys and playback provider templates belong in:

```
~/.config/zephyrus-shell/media.json
```

When set, `$XDG_CONFIG_HOME` replaces `~/.config`. Nothing is imported from
NexFlix automatically. Start from the committed, secret-free template:

```sh
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/zephyrus-shell"
# Copy only if you do not already have media.json:
cp -n media/media.example.json "${XDG_CONFIG_HOME:-$HOME/.config}/zephyrus-shell/media.json"
chmod 600 "${XDG_CONFIG_HOME:-$HOME/.config}/zephyrus-shell/media.json"
```

An example is in [`media/media.example.json`](../media/media.example.json).
Replace the example provider with your service's URL:

```json
{
  "tmdb_key": "",
  "omdb_key": "",
  "mdblist_key": "",
  "watchmode_key": "",
  "mal_client_id": "",
  "region": "US",
  "providers": [
    {
      "name": "My service",
      "movie_url": "https://example.org/movie/{imdbId}",
      "series_url": "https://example.org/series/{imdbId}/{season}/{episode}"
    }
  ],
  "anime_sources": [],
  "player": ["mpv"],
  "opensubtitles": {
    "api_key": "",
    "username": "",
    "password": "",
    "languages": ["en"]
  }
}
```

- `tmdb_key`: a TMDB API key (v3), enabling discovery, title search, details,
  title logos, trailers, artwork, episodes, and ID resolution.
- `omdb_key`: optional fallback for title search, full details, seasons and episodes;
  also adds ratings and missing metadata. OMDb has no discovery feed or backdrop/
  title-logo API, so TMDB is needed for those features.
  Search, details, and episodes use TMDB first, then OMDb when configured.
  Pagination stays with the provider that supplied the page.
- `mdblist_key`: optional additional ratings and preferred backdrops.
- `watchmode_key`: optional Watch links. `region` selects preferred sources.
- `mal_client_id`: optional official MyAnimeList API client ID. Register a client
  at [MAL API configuration](https://myanimelist.net/apiconfig/create). Public
  catalogue requests use the client ID without a user OAuth login. When set,
  official MAL data supplies ordinary Anime search, rankings, scores, and title
  details. AniList supplies catalogue-wide genre/year/score filters and results
  if an official MAL request fails. Without a client ID, AniList supplies Anime
  browsing and details, but MAL scores are unavailable.
- `providers`: named objects with separate `movie_url` and `series_url` templates.
  A provider may supply either or both; each module lists only compatible providers.
  Supported substitutions: `{imdbId}`,
  `{tmdbId}`, `{kind:movieValue|seriesValue}`, `{season}`, and `{episode}`.
  Season/episode placeholders require selecting an episode; Watch online opens the
  episode chooser when the series template requires these values. A provider URL without
  placeholders retains NexFlix's `/title/{imdbId}/` convention.
- `anime_sources`: optional named source adapters for Anime playback. Keep source
  endpoints, matching patterns, and decoder keys in your private `media.json`.
  The supported strategies are `mal_embed` (an `embed_url` with `{malId}`,
  `{episode}`, and `{mode}`) and `search_embed` (a title search followed by
  episode and server lookups). Both use `blob_pattern` and `xor_key` to resolve a
  direct stream. A title search adapter also needs `search_url`,
  `result_pattern`, `episodes_url`, `episode_pattern`, `servers_url`, and
  `server_pattern`. Set `episodes_field` and `servers_field` when those requests
  return HTML inside a JSON field. Source names appear only as playback choices.
- `player`: an argument array for a desktop player, default `mpv`. Direct media
  URLs ending in `.mp4`, `.mkv`, `.webm`, `.m3u8`, `.mpd`, `.avi`, or `.mov` use
  this player; provider webpages use the [configured browser command](browser.md). No shell evaluates the
  URL or arguments. Install the configured player before using direct playback.
- `opensubtitles`: optional OpenSubtitles.com API key and account for
  [Local subtitle management](subtitles.md). `languages` sets the starting
  search choices; the selection can be changed for each search.

The Watch split button selects Local first when a file exists, followed by the
configured online providers. Its main button launches the selected source;
its dropdown selects and launches another. **Trailer** is a single button
when one trailer exists, or **Trailers** with a dropdown for several. Both use the
shell accent background. Promotional clips and featurettes are excluded.
**Services** lists availability links from Watchmode for the selected title.
The Notes & URL editor has been removed. Older saved notes/URLs are retained in
storage but do not override Watch online. Playback providers are configured in
`media.json`. Reopen the module after changing provider names; keys are read for
each request. Refresh a title to bypass its metadata/artwork cache.

Selecting **Anime** in Discover switches Movies or TV Series to an anime
catalogue. Search, sort, year, minimum score, and the second genre selector
apply to anime; country and minimum votes are hidden. Other genres and All
continue to use the ordinary movie/TV catalogue. Anime records use MAL IDs,
and a displayed MAL score opens the title on MyAnimeList. The configured
official MAL API supplies standard search, rankings, scores, and title details,
including premiere season, adaptation source, age rating, and background notes.
AniList handles combined
search, genre, year, and minimum score filters, and provides the keyless
catalogue. Its score drives AniList-powered score filters and ordering; MAL
rankings use MAL scores. AniList scores are never displayed as MAL scores.
Results without a MAL ID are omitted. When a title is selected, one cached
AniList request fills missing artwork and trailers and supplies voice cast and
staff. The **Cast** tab links those people to their AniList pages. MAL scores
and fields take precedence.
The **Collections** tab loads related and recommended Anime titles on demand as
poster cards. Selecting one opens its catalogue details in the matching Movies
or TV Series module. Ordinary movies show their TMDB franchise collection when
available, plus TMDB recommendations. Ordinary TV Series show TMDB
recommendations. Overview does not request collection data.

Opening an Anime **Episodes** tab looks up an exact MAL-to-Kitsu mapping through
AniMap, then loads available episode titles, summaries, dates, and thumbnails.
This is cached for seven days for completed titles, one day for airing titles;
missing or ambiguous mappings fall back to numbered episodes. Discovery never
requests episode metadata for every card. Anime playback uses `anime_sources`
and requires `mpv`; **Watch online** starts episode 1, while **Episodes** lets
you choose another. Choose Sub or Dub beside Watch online. Availability and
audio choices depend on each configured source. **Find** searches by title and
can also search from an episode. **Spoilers** looks up a matching Wikipedia plot
by anime title when no IMDb ID is available.

NexFlix `.env` mappings are `TMDB_KEY → tmdb_key`, `MDBLIST_KEY → mdblist_key`, and
`WATCHMODE_KEY → watchmode_key`; `OMDB_KEY → omdb_key` is also supported as a
manual mapping (the backend does not read `.env` files). `GEMINI_KEY` and YouTube creator configuration are
not used. Keep real keys out of this repository. API errors redact request URLs,
keys, and provider response bodies.

## Functionality and boundaries

Overview includes synopsis, rating-service artwork, genres/countries, directors,
writers, and the leading six actors. **Cast** shows the full cast and crew, including
roles and portraits when supplied. Trailer choices live beside Watch online. Selecting a cast member loads a biography and credits
for the current module's media type. Availability links and Wikipedia spoiler plots load
only on request. TV Series adds season selection, paginated episodes, and
per-episode online playback templates; Movies has no episode controls. Favorites
persist independently of metadata refresh. Spoiler text omits Wikipedia headings
and edit links, including for previously cached plots.

TMDB search uses typed, paginated endpoints. Discovery
filters are sent to providers. Missing metadata can limit search filtering. Rating
sources retain their source labels and values; they are not converted to a common
scale. Optional enrichment failures leave the available title usable.

This port uses the desktop browser/player rather than Android's WebView/Media3.
Embedded playback, Cast, and YouTube feeds/extraction/summaries are not
implemented. Direct streams and local files are handed to a desktop player.
Local files are registered by catalogue identity during import or a Local scan.
The scan uses `guessit` to propose a match and requires exact title and year
for automatic catalogue matching. Uncertain matches wait for manual selection.

TMDB was verified for both catalogues, title details, and TV seasons using the existing configuration.
OMDb title/plot retrieval was also verified live; search, details, seasons,
and episodes have fixture coverage. It uses `omdb_key` in the same config.
See the [OMDb API documentation](https://www.omdbapi.com/) for its supported
search, title, and season parameters.

## Storage and implementation

`$XDG_DATA_HOME/zephyrus-shell/media/library.sqlite` (default
`~/.local/share/zephyrus-shell/media/library.sqlite`) stores cached JSON records,
IMDb/TMDB aliases, favorites, notes, custom URLs, registered local files, and
tracked qBittorrent imports. SQLite transactions permit
multiple windows/workers without clobbering personal data. Aliases migrate personal
records to the canonical IMDb ID. Back up this database for personal data.

`$XDG_CONFIG_HOME/zephyrus-shell/media-ui.ini` stores each module's view preference.
Images currently use Qt's image cache; metadata persists on disk. Browse pages
are fresh for 15 minutes, title/artwork/watch/person records for a day, and episodes
for an hour. Saved catalogue pages can be shown when all configured providers fail. Refresh never deletes
personal data. API configuration is read only by Python; QML receives provider
names and the selected playback target, not metadata API credentials.

`MediaService.qml` owns a Python standard-library worker using JSON lines over
stdin/stdout. Up to four requests run concurrently. Responses carry request IDs;
the UI guards browse, title, and episode generations. Rapid poster selection waits
90 ms before starting hydration so intermediate titles do not flood the worker.
Cast, filmography and episode views instantiate only visible rows. The worker is destroyed with
the module. The explicitly launched browser/player may outlive it.

Checks:

```sh
python3 -m unittest discover -s tests -v
bash scripts/check-media.sh
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qmltestrunner -input tests/qml
```

The smoke check uses an isolated XDG fixture database, exercises both real plugin
entry points, saves rail/grid screenshots under `tests/artifacts/`, and checks
persistence and destruction. It never needs API keys or touches your library.

The poster rail starts with a provider page and fetches more near its end. Grid mode
fetches toward 60 titles initially, then continues near the bottom. Provider page
sizes and availability can limit the total. The bottom spacer retains breathing
room without a title count or Load more button. Browse errors offer Retry.

Ratings open provider title URLs where available; missing Rotten Tomatoes or
Metacritic URLs fall back to a title search on that provider. Portraits and episode
thumbnails depend on provider artwork. Filmographies show posters newest first, with All selected initially and role tabs
for available acting, directing, writing, producing, and other crew credits.
Country labels use ISO country names and flag emoji (font support required).
The visible backdrop stays fixed while details and supplementary artwork load.
Opening Settings retains the active module and its worker underneath the drawer,
including in the component preview. Shared wheel scrolling applies to drawers,
settings, media, applications, dropdowns, and notifications; touchpad pixel deltas
remain continuous while mouse notches animate quickly over a larger distance.

Title loading remains visible through catalogue-detail and artwork/rating enrichment,
season discovery, and title-logo loading. Rating links normalize provider-relative
paths to HTTPS pages; IMDb uses the canonical title ID. Rotten Tomatoes critics
and audience (Popcorn) scores are grouped together.
