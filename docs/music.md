# Music

Downloads use floating **Activity** popups, so progress does not resize the music
tables. Plain status and error messages use desktop notifications and Attention.
Finished or failed activity rows can be dismissed. Stream saves share Files' job queue UI, with
cancellation, track progress, and time estimates when duration is available.
Completed saves refresh Local automatically. Multiple saves can be queued; the
worker runs at most two concurrently and preserves existing track filenames.

Music owns its torrent service and continues polling while hidden, so downloads
and imports keep running after selecting Desktop or another space. Retention
combines playback, stream saves, and torrent work; hidden Music is released when
all three become idle. **Activity → Manage download** opens the existing review
and hold-to-delete controls in a popup. Torrent progress uses qBittorrent's size,
speed, and ETA; qBittorrent itself keeps running after an explicit Music close.
Escape or explicit Close stops Music's owned stream saves, player, and workers.

The **Local** song view and song, album, and artist qBittorrent searches for
public domain music or audio authorized for AI training are described in
[Local library and qBittorrent](torrents.md). The Find icon sits with each
song, album, or artist's other actions. Album and artist downloads let you
select audio files before qBittorrent starts downloading, then require matching
each selected file to a catalogue song before import. Artist searches include
`discography`; audio tags appear as matching clues when available. Local songs use
the same playback queue as discovered songs.

Music uses the Apple Music public catalog for search, artist discographies, album
tracks, genres, popularity charts, and catalog playlists. Discover opens on the
playlist set in `default_playlist`, when configured, otherwise Apple's most-played
song chart. The playlist may be an Apple Music playlist ID or its share URL. The
genre filter continues to show Apple's chart for the selected genre.
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
`default_playlist` is optional. Set it to a public Apple Music catalog playlist ID
(such as `pl.2a86e272cf2349a99de68fd9cf7d4776`) or its `music.apple.com` share URL
to use that playlist as Discover's default. Leave it empty to use most-played
charts. Private library playlists are not available through the catalog token.

`providers` is an ordered list of optional playback adapters. Each adapter uses
GET requests for JSON search results and a URL template for the selected stream.
For example:

```json
{
  "storefront": "us",
  "catalog_token": "https://example.invalid/music-token",
  "default_playlist": "",
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
      "download": {
        "track": "stream",
        "album": "stream"
      },
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

`download` is optional. Set `track`, `album`, both, or neither to expose the
matching Download icons. Music uses the first provider in the ordered list with
a value for that action. Set a value to `"stream"` to resolve a matching song
through that provider's `search_url` and `stream_url`, then save its audio with
`ffmpeg` without re-encoding. The resolved stream must be readable by `ffmpeg`;
Music reports a failed save if it is not. An album saves each matching song and
reports how many tracks succeeded.
Files go to `XDG_MUSIC_DIR` (or `~/Music`) as
`<song> - <artist> - <album> (YYYY-MM-DD).mka`. A full release date and the other
filename fields are required. `.mka` is a Matroska audio container; the codec
inside (for example, FLAC) retains the quality supplied by the provider. This
does not import the files into the Local library. Install `ffmpeg` for stream
downloads.

Alternatively, a value may be an HTTP(S) download URL template if the provider
offers an endpoint that returns a file or redirects to one. Download templates
use the same URL encoding and `{base_url}` syntax as search and stream
templates. They may use `{id}`,
`{title}`, `{artist}`, and `{query}`; tracks may also use `{track_id}`, `{album_id}`,
`{album}`, and `{isrc}`, while albums may use `{album_id}` and `{album}`. For
downloads, `{id}` is the selected Apple catalog song or album ID (or the ID of
another displayed source), while the stream template's `{id}` comes from the
playback provider's search result. Values required by a download template must
be present on the selected item. Music opens the expanded URL with the configured
Music browser command; the provider endpoint handles the file or redirect.
Provider authors are responsible for supplying URLs that accept these catalog
values. Existing configurations without `download` work unchanged and show no
Download icons.

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
