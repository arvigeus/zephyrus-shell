# Subtitles for Local movies and episodes

Select a title with a Local video and open **Subtitles**. The tab replaces
**Find** for Local titles. For a TV series, choose an episode at the top or
open its Subtitles action from the episode list. The view shows subtitle files
beside that video and embedded subtitle tracks. It shows their language and
format, plus the video's frame rate when `ffprobe` can read it. Text-based
embedded tracks can be extracted as separate SRT files with `ffmpeg`.
Image-based tracks remain available inside the video player but cannot be
extracted as SRT here.

The on-disk inventory scans the video's folder, not subfolders. It includes
supported subtitle files whose names start with the video or recorded original
filename, or whose season and episode match. If the folder contains exactly one
video, it also includes subtitle files without an episode number, even when
their names differ.

When a Local scan or reviewed import moves a video into its library folder, it
moves subtitles from the source folder with it. A subtitle named after the
original video keeps its trailing language or variant marker: `Release.mkv`
with `Release.srt` and `Release-bg.srt` becomes `Movie (2024).mkv`,
`Movie (2024).srt`, and `Movie (2024)-bg.srt`. Matching TV episode numbers
also associate subtitle files with the right episode. If a source folder has
one video and one subtitle with an unrelated name, that subtitle is renamed to
the video's new stem. Ambiguous subtitles stay in the source folder. Existing
destination subtitles are never overwritten. For qBittorrent imports,
qBittorrent renames subtitles in its payload so seeding continues. Subtitles
added separately beside the torrent video move with the video too.

Click the play icon next to a subtitle file to launch the configured `mpv`
player with that exact subtitle selected. Ordinary local playback still uses the
player's normal subtitle selection. Subtitle filenames use language suffixes
such as `.bg.srt`, `.vi.srt`, and `.en.srt`, so multiple languages can coexist
beside one video. Existing subtitle files are preserved. Hold the trash button
to remove a subtitle downloaded, extracted, or adjusted by Zephyrus; subtitles
that were already in the folder are shown but protected from removal because
they may belong to a seeding torrent.

## OpenSubtitles setup

Put an `opensubtitles` object in
`$XDG_CONFIG_HOME/zephyrus-shell/media.json` (normally
`~/.config/zephyrus-shell/media.json`):

```json
"opensubtitles": {
  "api_key": "your-app-api-key",
  "username": "your-OpenSubtitles-username",
  "password": "your-OpenSubtitles-password",
  "languages": ["en"]
}
```

This object goes inside the existing top-level JSON object, separated from
other keys by a comma. Keep the config file private (`chmod 600`). The API key
enables search; account credentials are also needed for downloads. They stay
inside the Python worker and are not sent to QML. OpenSubtitles applies its
own download quota. See the [OpenSubtitles API documentation](https://opensubtitles.stoplight.io/docs/opensubtitles-api)
for account and API access.

Choose one to five languages before searching. English is selected by default.
Bulgarian and Vietnamese are one-click options; another two- or three-letter
language code can be added. Scroll through results to reveal more matches and
load later OpenSubtitles pages automatically.
Search uses the video's [OpenSubtitles file hash](https://github.com/opensubtitles/oshash)
and catalogue IMDb/TMDB identity. Results for each selected language are shown
together, with exact file matches, release-name matches, trusted uploaders,
hearing-impaired/forced flags, frame rate, and download count. Downloads are
manual, one result at a time. Each becomes a separate SRT file alongside the
video; downloading a second subtitle in the same language adds a numbered
copy rather than replacing the first.

## Timing

When a search result declares a frame rate different from the video, its
**Adjust** button scales cue times locally if enabled before downloading that
result. For an existing SRT file, choose **Adjust** on that subtitle's row.
The inline controls start at the video's frame rate; change it if the subtitle
was made for a different rate, or enter an offset in seconds. **Save** keeps
the original as `<filename>.srt.bak` and writes the adjusted subtitles at the
original path. Later saves use `.bak.2`, `.bak.3`, and so on. The timing
tool changes SRT cue timestamps; it does not fix subtitles whose lines drift
irregularly or whose release has different cuts.

Release provenance is saved during Local import in NFO files. Movie releases
use `movie.nfo` when Zephyrus creates it; existing movie NFO files are left
alone and receive a separate `.release.nfo`. TV episodes always use a
per-episode `.release.nfo` alongside `tvshow.nfo`. Search uses the release
name and original filename as ranking hints. Torrent magnets and account
credentials are never written to NFO files.
