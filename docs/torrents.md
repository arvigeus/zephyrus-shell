# Local library and qBittorrent

Movies, TV Series, Music, Books, and Games can search qBittorrent from the
selected catalogue item. This is intended for public domain media and material
you are authorized to use for AI training. Check the rights and the exact
release before starting a download. The shell does not install search plugins
or choose releases for you.

## Setup

Enable qBittorrent's Web UI and at least one search plugin in qBittorrent.
Its Web API exposes plugin search jobs, results, and torrent download paths;
this integration uses only those operations. See the
[qBittorrent Web UI API](https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API-(qBittorrent-5.0))
and [search plugin instructions](https://github.com/qbittorrent/search-plugins/wiki/Install-search-plugins).

The default connection is `http://127.0.0.1:8080`. If qBittorrent allows
local API access without a login, no configuration file is needed. Otherwise,
copy `media/torrents.example.json` to
`$XDG_CONFIG_HOME/zephyrus-shell/torrents.json` (or
`~/.config/zephyrus-shell/torrents.json`) and set either the Web UI username
and password or an API key. API key authentication requires qBittorrent 5.2.0
or newer. When `api_key` is set, it is used instead of username/password.
Use the file to set a different Web UI address too. Keep it private with
`chmod 600`. Credentials stay in the Python worker and are not sent to QML.
The qBittorrent process must see the **same absolute staging
path** as the shell. A remote Web UI works only when its download filesystem
is mounted at that same path on both machines.
If a local Web UI cannot be reached and qBittorrent is not running, **Find**
offers **Start qBittorrent** for a native or Flatpak installation. It waits for
the Web UI to become available. Remote Web UI connections and an already running
qBittorrent still need their address and Web UI settings checked manually.

Example:

```json
{
  "url": "http://127.0.0.1:8080",
  "username": "admin",
  "password": "your-web-ui-password"
}
```

For qBittorrent 5.2.0 or newer, API key authentication can be used instead:

```json
{
  "url": "http://127.0.0.1:8080",
  "api_key": "your-qbittorrent-api-key"
}
```

## Search and import

Select a title and open **Find**. Movies search with title and year.
Series searches use the title without a year. Series-wide searches add `complete`, season searches add `Sxx`,
and episode searches add `SxxEyy`. These are editable text hints, not proof that
a release contains the desired episodes. Music searches a selected
song with its artist, title, and year; album searches use artist, album, and
release year; artist searches use `<artist> discography`. Books add the author. Games add the
release year. You may edit the query. Results show the release name, size,
seeders, and a link to its details. A result naming a different year is marked
and cannot be queued from that row; refine the search to avoid matching a
different work such as *The General* (1998) instead of *The General* (1926).
Episode and season searches likewise mark results naming different numbers.
More results load as you scroll toward the bottom of the list.

qBittorrent's plugin search is a text search. The *arr stack adds indexers,
quality profiles, release rules, and automated import on top of a download
client. This integration deliberately leaves release selection with you and
uses the catalogue identity to remove ambiguity after selection. It does not
claim the same automatic release ranking as Radarr or Sonarr. See
[Radarr's indexer and download-client settings](https://wiki.servarr.com/radarr/settings).

For Music, the shell fetches the torrent's file list before adding a download.
If it contains several audio files, choose the tracks to download. qBittorrent
receives file priorities with the add request, so unselected tracks are skipped.
This requires qBittorrent Web API 2.11.9 or newer. Selected album and artist
tracks still need individual catalogue matches after download; `ffprobe` tags
are shown as clues when available.

The shell queues the chosen magnet or torrent URL into a unique staging folder
under `$XDG_DATA_HOME/zephyrus-shell/media/torrents/`. The worker checks
completion while the module is open. On completion it asks qBittorrent to rename
the selected files and move the torrent into the organized library. Seeding
continues from the final path. If a release contains
several plausible files, names a different movie year, or lacks an episode number,
**Review files** lets you
choose the correct file and enter numbering. A Music review can also fill in
artist, album, and full release date. Album and artist downloads always wait
for review: match each audio file to a catalogue song before importing it. The
download stays in staging until every selected audio file has a match, then
qBittorrent moves it to the music library. The
review screen can search the song catalogue when the artist's initial top songs
do not include the track.
Reopening a module resumes checking
tracked downloads.

## Scan and delete

Movies and TV Series have **Local → Scan**. Scan checks completed qBittorrent
files first, then the Movies or Series folder under `$XDG_VIDEOS_DIR`. Press
**Scan** without entering a path for the normal scan. A path overrides that
folder. `guessit` reads video names and episode numbers;
an existing NFO or a unique exact catalogue match supplies identity.
Those files are organized automatically. Other files remain in the scan review
list so you can choose the correct catalogue title and, for TV, confirm season
and episode. Ordinary video files are moved into the organized library;
qBittorrent sources are moved by qBittorrent. A missing qBittorrent connection
does not prevent the folder scan. Scan inspects at most 500 unregistered files
per run.

The trash icon requires a hold of about 1.3 seconds. For a file imported from
qBittorrent, it deletes that torrent and all its downloaded content, then
removes every Local file linked to it. Movies remove their whole title folder,
and TV episodes remove their whole season folder, including extra files in
those folders. A multi-file torrent may therefore remove several episodes or
songs at once. A tracked download without a Local entry can be removed from
its title's **Findy** view with the same hold action. Deletion is permanent.

## Library paths and identity

| Type | Destination |
| --- | --- |
| Movie | `$XDG_VIDEOS_DIR/Movies/Title (Year)/Title (Year).ext` |
| TV episode | `$XDG_VIDEOS_DIR/Series/Title (Year)/Season 01/Title (Year) - S01E01.ext` |
| Song | `$XDG_MUSIC_DIR/Title - Artist - Album (YYYY-MM-DD).ext` |
| Book | `$XDG_DOCUMENTS_DIR/Books/Author/Title (Year)/Title (Year).ext` |
| Game file | `$XDG_DATA_HOME/zephyrus-shell/games/Title (Year)/Title (Year).ext` |

XDG user directories are read from environment variables or
`~/.config/user-dirs.dirs`. `Movies`, `Series`, and `Books` are created below
those roots. Game files are archives or installers to inspect; they are not
installed or launched by this feature. A game bundle with several files keeps
each original filename inside its game folder. Music needs a complete release date to
meet the flat filename convention.

The SQLite library stores the selected catalogue ID and exact path. Movies
also get `movie.nfo`; series get `tvshow.nfo`. Those files contain the title,
year, and IMDb/TMDB IDs. Imports also save the torrent release name (when
available), original video filename, and source in an NFO. For TV episodes
this is a per-episode `.release.nfo`; for movies it is in `movie.nfo` when
Zephyrus creates that file, or in a `.release.nfo` when `movie.nfo` already
exists. Existing NFO files are never replaced. The catalogue providers still
supply full metadata. [Subtitles](subtitles.md) uses this release information
to rank OpenSubtitles results.
Local movie and series imports also move matching subtitle files with each
video and rename them to the organized video stem. A lone, differently named
subtitle follows a lone video. qBittorrent performs these renames for torrent
payloads so seeding continues. Separately added subtitles beside a torrent
video move too; destination subtitle files are not overwritten.
Kodi recognizes these ID tags and reads TV episode numbering from filenames;
see its [TV NFO](https://kodi.wiki/view/NFO_files/TV_shows) and
[episode naming](https://kodi.wiki/view/Naming_video_files/Episodes) guidance.
Music, Books, and Games get a small `.zephyrus.json` identity sidecar. **Local**
appears before **Discover** and uses the same catalogue detail view. Discover
checks for local files by identity. A single Watch split button chooses Local
by default when available, with online providers in the same menu. Episode
rows play their matching local file when available.

## Existing files

`scripts/import-local-media.py` helps with a separate, explicit sweep. It does
not infer catalogue identities from filenames. First inventory supported files:

```sh
python3 scripts/import-local-media.py --inventory > /tmp/local-media.json
```

Review that JSON and fill in `id`, `title`, and any missing fields. Use the
catalogue's IMDb/TMDB, Open Library, Apple Music, or game ID. For TV, include
`season` and `episode` if the filename lacks `SxxEyy`. For songs, include
`artist`, `album`, and `releaseDate` in `YYYY-MM-DD` form. Preview the paths,
then import:

```sh
python3 scripts/import-local-media.py --manifest /tmp/local-media.json
python3 scripts/import-local-media.py --manifest /tmp/local-media.json --apply
```

Import moves source files and refuses to overwrite a different
library file. Review every proposed path before `--apply`.
