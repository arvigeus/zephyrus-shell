# Games

The **Local** file view and context-aware qBittorrent search for public domain
games or game material authorized for AI training are described in
[Local library and qBittorrent](torrents.md). Imported game files are opened
for inspection, not installed or launched automatically.

Games combines an IGDB catalogue with locally discovered Steam and Epic games.
The catalogue supplies titles, artwork, genres, platforms, release dates, and
related games. It does not claim that a catalogue result is owned or installed.
When IGDB lists an official website, a small globe link in the game details opens it.
The local library scan supplies those states independently. Favorites and manual
store matches live in the local SQLite database.

**Local** lists imported game files. **Library**, between Local and Discover,
lists your Steam and Epic games without requiring IGDB credentials. Choose
**All games** for installed or owned games, **Installed** for games on this
computer, or **Purchased** for games confirmed as owned. Purchased also includes
claimed free games; launchers report ownership rather than payment history.
Games opens **Library** by default when it contains any installed or owned games.
With an empty store library, it opens **Local** when imported files exist,
otherwise **Discover**.
Refresh the store libraries from the Library toolbar. Steam ownership requires
the configured public profile below; Epic ownership requires Legendary sign-in.
Unknown ownership is never treated as proof that an uninstalled game is owned.

Matching games in both stores share one Library row, with both stores still
available in its details. Unique saved catalogue matches supply metadata and
artwork; games without a saved match use their launcher title. Exact title
matching treats standalone Roman sequel numbers II–X as their Arabic equivalents
(for example, IGDB's **Alan Wake II** matches Epic's **Alan Wake 2**). Edition and
DLC names remain significant, and ambiguous matches stay separate.

Library shows available launcher metadata immediately: Epic descriptions and
portrait/backdrop images from Legendary, plus Steam artwork by AppID. It then
enriches the displayed games in the background, updating cards in place and
showing **Loading metadata…** while work is pending. With IGDB configured,
unmatched entries request a unique exact title match; Roman sequel numbers are
normalized, conflicting Steam AppIDs are rejected, and a matching Steam AppID
breaks title ties. The launcher identity and favorites remain intact.

IGDB fields take precedence. Missing fields fall back to Epic's supplied data
or Steam store details (description, images, genres, platforms and companies).
Steam store metadata needs no Steam Web API key or IGDB credentials. Available
store data also remains usable when IGDB has no unique match or is unavailable.
Steam details are cached for seven days and IGDB library matches for one day;
failed requests wait five minutes before automatic retry, preserving saved data.
**Refresh game details** retries metadata for the selected game immediately.
Some delisted products or launcher records may still lack artwork/descriptions.

Search, filters, and the rail/grid views share the same presentation patterns as
Movies, TV Series, and Books. The game worker in `games/backend.py` owns the
catalogue, library scans, launches, and cached results; `games/igdb.py` owns
IGDB authentication and request pacing. The shell only hosts the module.

## Configure the catalogue

Copy [games.example.json](../games/games.example.json) to
`$XDG_CONFIG_HOME/zephyrus-shell/games.json` (usually
`~/.config/zephyrus-shell/games.json`). Set `igdb_client_id` and
`igdb_client_secret`, then restrict the file with `chmod 600`.

```json
{
  "igdb_client_id": "",
  "igdb_client_secret": "",
  "steam_api_key": "",
  "steam_id": "",
  "proton_path": ""
}
```

The worker exchanges the IGDB credentials for a Twitch app token. It keeps the
token in memory, refreshes it before expiry, spaces catalogue requests to the
documented four-per-second budget, and caches browse/detail results separately.
Credentials are not sent to QML or included in errors. The first catalogue
page does not wait for local launcher discovery. IGDB permits paged results and
supports the genre, platform, year, and sort filters used here.
[IGDB API documentation](https://api-docs.igdb.com/)

## Store actions

- Steam installs are found from local `libraryfolders.vdf` and app manifests.
  `Play` launches through Steam; `Install` opens Steam's installation flow.
- `steam_api_key` and `steam_id` optionally check ownership for a public Steam
  profile. A private or unavailable profile remains an unknown ownership state.
- Legendary supplies Epic ownership and installation state. When available,
  UMU can launch Epic games with the appropriate Proton identity. An unavailable
  Legendary installation leaves Epic actions unavailable without blocking IGDB.
- A known unowned game offers `Buy` when IGDB supplies a validated store product
  link. Steam AppIDs resolve to their product page. Checkout links are store
  controlled, so the action opens the product page.

Store matching uses a saved manual match, an explicit store ID, then a unique
normalized title. An ambiguous title never launches another edition. Steam AppIDs
also identify ProtonDB reports; that lookup happens only in game details and
uses a seven-day cache. ProtonDB ratings are guidance, never a launch gate.
[Steam ownership API](https://partner.steamgames.com/doc/webapi/IPlayerService#GetOwnedGames) ·
[Legendary](https://github.com/derrod/legendary) ·
[UMU](https://github.com/Open-Wine-Components/umu-launcher)

The catalogue, personal records, library snapshots, and store matches are in
`$XDG_DATA_HOME/zephyrus-shell/games/library.sqlite`. Refreshing the local
libraries does not invalidate the catalogue cache. If IGDB is temporarily
unavailable, a saved catalogue page remains available with a warning.
