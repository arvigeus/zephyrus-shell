# Games

Games combines your Steam and Epic (via Legendary) libraries with the
[IGDB](https://www.igdb.com) catalogue. It can play, install, and uninstall
through the store launchers and shows ProtonDB ratings. The **Local** view and
qBittorrent search under **Find** are described in
[Local library and qBittorrent](torrents.md); imported game files are only
opened in the file manager, never installed or run.

## Views

- **Library** — installed and owned Steam/Epic games. Works without IGDB.
  Filter by All games, Installed, or Purchased (confirmed ownership, including
  claimed free games). A game in both stores is one row. Games opens here when
  this view has anything.
- **Discover** — IGDB catalogue with genre, platform, release-year, and sort
  filters. Needs IGDB credentials.
- **Favorites** — games you starred.
- **Local** — imported game files.

Library cards first show launcher data (Epic art and descriptions from
Legendary, Steam art by AppID), then fill in from the Steam store and a unique
exact IGDB title match in the background (**Loading metadata…**). IGDB fields
win when available. Steam store data needs no key.

## Configuration

`$XDG_CONFIG_HOME/zephyrus-shell/games.json` (default
`~/.config/zephyrus-shell/games.json`), see
[games.example.json](../modules/games/games.example.json). All keys are optional;
`chmod 600` the file.

```json
{
  "igdb_client_id": "",
  "igdb_client_secret": "",
  "steam_api_key": "",
  "steam_id": "",
  "proton_path": ""
}
```

- `igdb_client_id`, `igdb_client_secret` — a Twitch application's client ID
  and secret ([IGDB setup](https://api-docs.igdb.com/#getting-started)).
  Required for Discover and IGDB metadata.
- `steam_api_key` ([get one](https://steamcommunity.com/dev/apikey)) and
  `steam_id` (17-digit SteamID64) — check Steam ownership. The profile and its
  game details must be public.
- `proton_path` — Proton directory passed to UMU as `PROTONPATH` for Epic games.

The file is re-read when it changes.

## Stores

- **Steam**: installs are read from `steamapps/libraryfolders.vdf` and
  `appmanifest_*.acf` under `~/.steam/steam`, `~/.steam/root`,
  `$XDG_DATA_HOME/Steam`, and the Flatpak Steam directory. Play runs
  `steam -applaunch <AppID>`; Install and Uninstall open Steam's own prompts.
  Needs `steam` on `PATH` (or `steam.sh` in the Steam directory).
- **Epic**: `legendary list` and `legendary list-installed` supply ownership
  and installs; sign in with `legendary auth` first. Play runs
  `legendary launch`; Install and Uninstall run `legendary --yes install|uninstall`
  in the background. When `umu-run` is on `PATH`, games run through UMU with a
  per-game prefix in `$XDG_DATA_HOME/zephyrus-shell/games/prefixes/egs/`.
- **Buy** opens the store page when ownership is known to be missing.
- Uninstall always asks for confirmation.

Games are matched to store entries by a manual link, then the store ID IGDB
lists, then a unique exact title (Roman numerals II–X match Arabic ones, so
"Alan Wake II" matches "Alan Wake 2"). Ambiguous titles are not matched. Use
**Link** or **Edit store link** on a store button to set a Steam AppID or Epic
app name by hand.

ProtonDB ratings use the matched Steam AppID; they are guidance only.

## Files and caching

Everything lives in `$XDG_DATA_HOME/zephyrus-shell/games/library.sqlite`:
saved games, favorites, manual store links, and a response cache. The rail/grid
choice is in `$XDG_CONFIG_HOME/zephyrus-shell/games-ui.ini`.

Catalogue pages are cached for 15 minutes, game details, ProtonDB ratings,
filter lists, and Steam store data for 7 days, IGDB library matches and the
store-library snapshot for 1 day, Steam ownership for 30 minutes. Store
libraries are rescanned at most once a minute unless you press refresh. When a
service is unreachable, saved data is shown with a warning and automatic
retries wait 5 minutes (15 seconds for IGDB). Cache entries not refreshed for
90 days are removed when Games starts.

## Limitations

- Only Steam and Epic (Legendary). No GOG, itch.io, or non-Steam shortcuts.
- Some delisted games have no artwork or description anywhere.
