# Music

The **Local** song view and song, album, and artist qBittorrent searches for
public domain music or audio authorized for AI training are described in
[Local library and qBittorrent](torrents.md). The Find icon sits with each
song, album, or artist's other actions. Album and artist downloads let you
select audio files before qBittorrent starts downloading, then require matching
each selected file to a catalogue song before import. Artist searches include
`discography`; audio tags appear as matching clues when available. Local songs use
the same playback queue as discovered songs.

Music uses the Apple Music public catalog for search, artist discographies, album
tracks, genres, and popularity charts. Discover opens on Apple's most-played song
chart, optionally scoped by genre, in the same song table used for search results.
This is popularity-ranked discovery rather than a global newest-releases feed.
The Filters button opens the fixed Songs, Artists, and Albums browser, where each
column has its own search. Apple catalog search and chart pages load incrementally;
selecting an artist loads its top songs and the first album page. Songs can then
load further top-song pages and, when that ranking ends, tracks from small album
batches as the Songs pane scrolls. Album metadata pages load separately, without
fetching every track list up front. Selecting an album loads its
track list and credited artists. Favorites are split into Artists, Albums, and
Songs.

Artist rows and artist names in the song table have an information action. It
fetches Apple Music artist artwork, genres, share URL, and editorial notes when
available, without loading the artist's albums or tracks. If the catalog response
does not include a biography, opening artist information makes one best-effort
request to that artist's public Apple Music page and reads its embedded `bio`.
The biography is cached for the life of the Music service. This public-page field
is separate from the documented catalog editorial-notes attributes, so it may
change or be absent for some artists. Apple does not expose the profile's “From”
line in the artist catalog attributes used here.

Apple supplies catalog metadata only. Playback is optional and uses the ordered
providers configured by the user. For an Apple song, Music first searches each
provider by ISRC when available, then by artist and title. A provider must return
a confident match before Music passes its configured stream URL to mpv. Some
catalog tracks may have no match; catalog browsing still works when no playback
providers are configured. Install `mpv` for playback, seeking, pause, and volume.

## Configuration

Music reads:

```text
$XDG_CONFIG_HOME/zephyrus-shell/music.json
```

If `XDG_CONFIG_HOME` is unset, it reads `~/.config/zephyrus-shell/music.json`.
Start from the secret-free template:

```sh
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/zephyrus-shell"
cp -n plugins/music/music.example.json "${XDG_CONFIG_HOME:-$HOME/.config}/zephyrus-shell/music.json"
chmod 600 "${XDG_CONFIG_HOME:-$HOME/.config}/zephyrus-shell/music.json"
```

`catalog_token` accepts either an Apple Music developer token (JWT) or an HTTP(S)
URL that returns the token. A URL response may be a plain token string or JSON
with a `dev_token` or `token` property; JSON may also provide
`cache_ttl_seconds`. The token is fetched by the Music backend and cached until
its expiry (or for five minutes when the response does not include an expiry).
Apple catalog access does not use the user's personal library or provide audio
playback. `storefront` is a two-letter country code and defaults to `us`.

`providers` is an ordered list of optional playback adapters. Each adapter uses
GET requests for JSON search results and a URL template for the selected stream.
For example:

```json
{
  "storefront": "us",
  "catalog_token": "https://example.invalid/music-token",
  "providers": [
    {
      "name": "Audio service",
      "base_url": "https://service.example",
      "search_url": "{base_url}/search/tracks?q={query}&limit={limit}",
      "results_path": "tracks",
      "track_id_field": "trackId",
      "track_title_field": "title",
      "track_artist_field": "artistName",
      "track_artists_field": "artistNames",
      "track_isrc_field": "isrc",
      "stream_url": "{base_url}/track/{id}",
      "headers": {
        "Origin": "https://service.example",
        "Referer": "https://service.example/"
      }
    }
  ]
}
```

The example values are placeholders. `search_url` supports `{base_url}`, `{query}`,
`{artist}`, `{title}`, `{isrc}`, and `{limit}`. Search values are URL-encoded.
`results_path` and track field names support dot-separated JSON paths. The
provider's response must contain a list at `results_path`; each result needs an
ID, title, artist, and preferably an ISRC. The defaults are `tracks`, `trackId`,
`title`, `artistName`, `artistNames`, and `isrc` respectively. `stream_url`
supports `{base_url}`, `{id}`, `{track_id}`, `{query}`, `{artist}`, `{title}`,
and `{isrc}`. IDs and query values are URL-encoded. Static `headers` are used
for the search request and forwarded to mpv for streaming. Providers are tried
in the order listed. Leave `providers` empty for catalog-only browsing.

`lyrics_providers` is an ordered list of optional LRCLIB-compatible lyrics
endpoints. Music looks up lyrics only when the lyrics button is clicked; it does
not make a request for every song in a result list. The default provider is the
free LRCLIB service, which does not require an API key:

```json
"lyrics_providers": [
  {"name": "LRCLIB", "base_url": "https://lrclib.net/api"}
]
```

Each endpoint must implement the LRCLIB `/get` query contract and return
`plainLyrics` or `syncedLyrics`. Providers are tried in order until one returns
lyrics. Music sends the track title, primary artist, album, and duration to
improve matching. Missing matches display “No lyrics available.” The LRCLIB
client-identification header is sent by default, and rate-limit responses are
honored with a per-endpoint cooldown. To use an API key, add `api_key`; it is
sent in an `Authorization` header with the `Bearer ` prefix by default. Set
`api_key_header` and `api_key_prefix` to match the endpoint, or provide fixed
`headers` when needed. Keep keys in the user configuration file, not in the
repository. Set `lyrics_providers` to an empty array to disable lookups.

The Apple developer token and any provider headers belong only in this user
configuration. The backend does not print configured URLs or tokens in errors.
Reopen Music after changing its configuration.

## Playback and data

Playback uses shuffle and repeat-all behavior. Songs, albums, and artists are
stored separately in:

```text
$XDG_CONFIG_HOME/zephyrus-shell/music-favorites.json
```

When `XDG_CONFIG_HOME` is unset, favorites are stored under `~/.config`.
