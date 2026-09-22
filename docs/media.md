# Movies and TV Series

Open **Desktop → Movies** or **Desktop → TV Series**. They are separate plugins
sharing the browser and provider service in `media/`. The shell's normal overlay
owns their lifecycle: Escape or Desktop closes the module and stops its worker.

The default view has a detail area above a horizontal poster rail. The grid button
switches to posters on the left and details on the right. That preference is shared
by both modules. TV Series defaults to the grid until you choose a shared layout. Click a poster or navigate with arrow keys to select a
title. Search expands from the search icon. Filters expand inline beside their
button (scroll horizontally on narrower windows). They include genre, country,
year range, minimum rating/votes, and sort order. Apply commits filters;
Reset clears them. Search is debounced; pages append automatically near the end.
Favorites are separate from discovery and can be searched by title.

Reopening a saved catalogue displays its snapshot while refreshing in the background.
Selection displays the catalogue record immediately, then hydrates metadata and
artwork independently. Late responses cannot replace a newer selection. Image,
logo, and rating slots reserve space. Shared double-buffered image transitions
crossfade backgrounds, title logos, and poster replacements. Initial images appear immediately once decoded. Enriched artwork owns its fields,
so a late details response cannot revert the chosen image. A stable catalogue model appends rows without rebuilding existing cards or resetting scroll position. Artwork uses landscape promotional IMDb
images, optional TMDB artwork with textless backdrops preferred, then MDBList's
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
cp -n media/media.exampe.json "${XDG_CONFIG_HOME:-$HOME/.config}/zephyrus-shell/media.json"
chmod 600 "${XDG_CONFIG_HOME:-$HOME/.config}/zephyrus-shell/media.json"
```

Example structure (replace the example provider with your service's URL):

```json
{
  "tmdb_key": "",
  "omdb_key": "",
  "mdblist_key": "",
  "watchmode_key": "",
  "region": "US",
  "providers": [
    {
      "name": "My service",
      "movie_url": "https://example.org/movie/{imdbId}",
      "series_url": "https://example.org/series/{imdbId}/{season}/{episode}"
    }
  ],
  "player": ["mpv"]
}
```

- IMDbApi is the primary provider and needs no key. Network failures, rate limits,
  and server errors suspend IMDbApi requests for five minutes, including across
  module reopenings; configured alternatives are used immediately during that time.
- `tmdb_key`: a TMDB API key (v3), enabling metadata fallback, title logos,
  trailers, additional artwork, and TMDB ID resolution.
- `omdb_key`: optional fallback for title search, full details, seasons and episodes;
  also adds ratings and missing metadata. OMDb has no discovery feed or backdrop/
  title-logo API, so TMDB is still needed for those features during an IMDbApi outage.
  Search fallback is IMDbApi → TMDB → OMDb; details and episodes use the same order.
  Pagination stays with the provider that supplied the page.
- `mdblist_key`: optional additional ratings and preferred backdrops.
- `watchmode_key`: optional Watch links. `region` selects preferred sources.
- `providers`: named objects with separate `movie_url` and `series_url` templates.
  A provider may supply either or both; each module lists only compatible providers.
  The older single `url` remains accepted as a fallback. Supported substitutions: `{imdbId}`,
  `{tmdbId}`, `{kind:movieValue|seriesValue}`, `{season}`, and `{episode}`.
  Season/episode placeholders require selecting an episode; Watch online opens the
  episode chooser when the series template requires these values. A provider URL without
  placeholders retains NexFlix's `/title/{imdbId}/` convention.
- `player`: an argument array for a desktop player, default `mpv`. Direct media
  URLs ending in `.mp4`, `.mkv`, `.webm`, `.m3u8`, `.mpd`, `.avi`, or `.mov` use
  this player; provider webpages use the default browser. No shell evaluates the
  URL or arguments. Install the configured player before using direct playback.

**Watch online** uses the chosen configured provider. Its main button launches that
provider; its dropdown selects and launches another. **Trailer** is a single button
when one trailer exists, or **Trailers** with a dropdown for several. Both use the
shell accent background. Promotional clips and featurettes are excluded.
The Notes & URL editor has been removed. Older saved notes/URLs are retained in
storage but do not override Watch online. Playback providers are configured in
`media.json`. Reopen the module after changing provider names; keys are read for
each request. Refresh a title to bypass its metadata/artwork cache.

NexFlix `.env` mappings are `TMDB_KEY → tmdb_key`, `MDBLIST_KEY → mdblist_key`, and
`WATCHMODE_KEY → watchmode_key`; `OMDB_KEY → omdb_key` is also supported as a
manual mapping (the backend does not read `.env` files). `GEMINI_KEY` and YouTube creator configuration are
not used. Keep real keys out of this repository. API errors redact request URLs,
keys, and provider response bodies.

## Functionality and boundaries

Overview includes synopsis, rating-service artwork, genres/countries, directors,
writers, and the leading six actors. **Cast** shows the full cast and crew, including
roles and portraits when supplied. Trailer choices live beside Watch online. Selecting a cast member loads a biography and credits
for the current module's media type. Watch links and Wikipedia spoiler plots load
only on request. TV Series adds season selection, paginated episodes, and
per-episode online playback templates; Movies has no episode controls. Favorites
persist independently of metadata refresh. Spoiler text omits Wikipedia headings
and edit links, including for previously cached plots.

IMDbApi search returns at most 50 results; client-side filters/sorts operate on
that result set. TMDB fallback search uses typed, paginated endpoints. Discovery
filters are sent to providers. Missing metadata can limit search filtering. Rating
sources retain their source labels and values; they are not converted to a common
scale. Optional enrichment failures leave the available title usable.

This port uses the desktop browser/player rather than Android's WebView/Media3.
Embedded playback, Cast, YouTube feeds/extraction/summaries, and local-library
scanning are not implemented. Direct streams are handed to a desktop player.
Playback resolution returns a typed web/direct target separately from metadata;
a future local source can resolve a file/player target without changing catalogue
providers or the Movies/TV split.

IMDbApi was unavailable during verification. Live TMDB fallback was verified for
both catalogues, title details, and TV seasons using the existing configuration.
OMDb title/plot retrieval was also verified live; fallback search, details, seasons,
and episodes have fixture coverage. It uses `omdb_key` in the same config.
See the [OMDb API documentation](https://www.omdbapi.com/) for its supported
search, title, and season parameters.

## Storage and implementation

`$XDG_DATA_HOME/zephyrus-shell/media/library.sqlite` (default
`~/.local/share/zephyrus-shell/media/library.sqlite`) stores cached JSON records,
IMDb/TMDB aliases, favorites, notes, and custom URLs. SQLite transactions permit
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
Cast, filmography and episode views instantiate only visible rows. When TMDB
already supplied artwork and credits, enrichment skips duplicate IMDb requests. The worker is destroyed with
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
