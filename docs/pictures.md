# Pictures

Pictures opens in the current wallpaper's category: Wallhaven, Bing Daily, or
Wallpaper Engine. New still-image selections save their provider; older cached
Wallhaven/Bing image paths are recognized too. With no recognized selection it
opens Wallhaven's toplist, which defaults to SFW wallpapers. Wallhaven
supports search, category, sort, time range, aspect ratio, and minimum
resolution filters. Bing Daily is a second provider, with a country filter and
search over the recent images returned by Bing. Each provider supplies its own
filter definitions and wallpaper details to the shared browser.

**Wallpaper Engine** is an optional, **experimental** third provider with
**Workshop** and **Installed** catalogues. Playback compatibility varies by
wallpaper and Proton/Wallpiper version; some scenes containing video still crash.
Workshop discovery happens directly in Pictures:
search titles/descriptions, filter by Scene/Video/Web and a subject tag, and sort
by Popular, Newest, Trending this week, or Relevance. Results have static previews
and can be saved to Favorites before installation. Tiles use small Steam CDN
previews. Selecting a wallpaper loads that preview first, then crossfades to a
creator-uploaded still image from Steam's additional previews when available.
**View preview** opens that larger image too. Some creators provide only a small
GIF and videos; those items have no larger still image available through this
API, and retain the primary preview. Workshop discovery defaults
to Steam's `Everyone` content tag. Installed search also matches IDs and local
tags, with a tag selector and title sorting. **Apply wallpaper** checks local
files and required software, and shows actionable errors if anything is missing.
Pictures checks missing requirements for the selected Wallpaper Engine item
every three seconds while visible. An amber warning explains when the application,
Wallpiper, or wallpaper download is missing, and clears automatically once ready.
These checks apply only to Wallpaper Engine selections.
Animated previews, random selection, and
wallpaper-property editing are not included.

Discovery uses Steam's documented
[`IPublishedFileService.QueryFiles`](https://partner.steamgames.com/doc/webapi/IPublishedFileService#QueryFiles)
API and keeps its opaque pagination cursors. It automatically reuses
`steam_api_key` from `$XDG_CONFIG_HOME/zephyrus-shell/games.json`; no Games worker
is loaded and the key never enters QML, favorites, or results. An optional
`wallpaper_engine.steam_api_key` in `pictures.json` overrides it. With a key,
the provider opens Workshop; without one it opens Installed. Browsing either
catalogue starts no Steam, Proton, or Wallpiper process.

Steam still handles subscriptions and downloads. **Download through Steam**
opens the selected item's page in Steam, where you click Subscribe; return to
Pictures while the download finishes. The action invokes the `steam`
executable directly, bypassing desktop URL handlers, and shows launch errors.
The selected item's installation state updates automatically, and Refresh can
also recheck your library. Subscribing does not install Wallpaper Engine itself:
the Steam application, Proton, and Wallpiper must be installed separately. The
selected item shows missing setup requirements in Pictures without starting
Wallpiper or any renderer.
Steam's documented
[Web API subscription method](https://partner.steamgames.com/doc/webapi/ISteamRemoteStorage#SubscribePublishedFile)
requires publisher credentials, so a personal search key cannot perform that
step. Finding and choosing wallpapers stays in Pictures; installation requires
that Steam handoff.

This integration currently requires Hyprland, Wallpaper Engine, Proton, and
[Wallpiper](https://github.com/ejalxndr/wallpiper), with `wallpiperd` and
`wallpiperctl` on the shell's `PATH`. Do **not** add Wallpiper to session autostart:
the shell starts its own daemon only when a Wallpaper Engine choice is applied
or restored at shell startup. Closing Pictures leaves that choice playing.
Applying a Wallhaven/Bing image shuts down the owned daemon, renderer, portal,
and remaining owned Proton/Wine helpers, then unloads the wallpaper worker.
An ordinary still-image session starts none of those processes. An independently
running Wallpaper Engine session must be closed before using this provider.
Playback is muted when applying or restoring a choice. Pictures replaces the
native picker, so the controller removes only its owned `wallpaperui.exe`
processes, including Wine processes whose main thread has exited while UI
threads remain alive. This prevents picker windows and their border helpers
from remaining above applications; web-wallpaper processes are left running.

The controller journals its ownership marker in
`$XDG_CONFIG_HOME/zephyrus-shell/.engine-ownership.json` before launching the
daemon. A config-scoped exclusive lease prevents two controllers from managing
the same choice. After a worker or shell crash, its replacement resumes and
terminates only processes bearing the previous marker, checks PID start times,
and starts a fresh session. This also works when the runtime directory changes.
If the shell restarts with a still-image choice, a short-lived cleanup worker
reconciles the journal and unloads; ordinary still-image startup needs no worker.
Owned processes can remain after an abrupt shell crash until the shell next
starts. This is recovery on restart, not an external session supervisor.

Startup reads Wallpaper Engine's native selection for each monitor slot. When
the portal is already producing visible frames on every output, it avoids
reopening an identical restored scene, video, or web wallpaper; only unmatched
slots receive a Set command. A saved path without frames does not prove restoration
succeeded, so it receives the ordinary Set command. Portal surface recreation
alone does not reload the project. This avoids unnecessary media initialization.
Unrecognized native configuration also falls back to the ordinary Set command.

While Zephyrus owns playback, it temporarily sets the native `playbacksleep`,
`playbackfullscreen` and `playbackmaximized` preferences to `run`. Windows
window/display heuristics under Wallpiper can stop rendering on an awake Wayland
desktop, leaving the portal frozen on its last frame. Disabling only the sleep
rule does not prevent that freeze after changing wallpapers. Zephyrus uses
Hyprland's actual fullscreen and DPMS state instead, suspending the owned renderer
when an application is fullscreen or all outputs sleep. A journal in
`$XDG_CONFIG_HOME/zephyrus-shell/.engine-native-playback.json` preserves each
original preference; stopping playback or recovering after a controller crash
restores them. The earlier `.engine-native-sleep.json` journal is recovered too.
Other native settings, properties and selected wallpapers remain intact. Native
configuration errors are reported rather than overwritten.

Temporary compositor/control failures and lost desktop surfaces get a 15-second
recovery window with the still-image fallback visible. A stopped renderer or
daemon is restarted; persistent transient failures also trigger a restart.
Restarts are limited to three per selection, with 1-, 2-, and 4-second backoff.
Unexpected controller exits have a separate three-attempt budget in QML. Output
sleep/removal alone does not consume that budget. Permanent setup errors and
exhausted retries stop playback and keep the fallback; use **Apply wallpaper**
to retry after fixing the reported problem. A new Apply resets the budgets.
A new `wallpaper*.mdmp` in the renderer's installation directory is treated as
an application crash, including when its crash dialog keeps the renderer alive.
The controller stops its owned processes immediately and does not restart that
selection automatically. The error includes the dump path and appears in
Pictures while keeping Apply available. Old dumps do not block a fresh Apply.
Terminal errors survive controller/shell reloads in the same runtime directory;
a new desktop session may attempt restoration again. A failed Apply from an
animated choice keeps the failed selection and its still fallback, avoiding a
second automatic launch caused by rolling back to the previous animated choice.

The controller defaults `WALLPIPER_FORCE_LINEAR=1` for capture. This avoids
striped output from tiled GPU buffers that import successfully on Hyprland/Mesa
but display incorrectly, while retaining GPU frame delivery. An explicit
`WALLPIPER_FORCE_LINEAR=0` in the shell environment overrides this default.

Setup on Arch Linux / Hyprland:

1. Install Wallpaper Engine in Steam and install a suitable Proton version from
   Steam's Tools library. Wallpiper currently reports Proton 11 or newer as tested.
   Its upstream recommendation is a clean Wallpaper Engine installation that
   has never been launched through Steam/Proton; see the
   [Wallpiper setup notes](https://github.com/ejalxndr/wallpiper#building-from-source).
2. Install both the core and Hyprland portal. With `paru`, run
   `paru -S wallpiper-hyprland` (the portal package depends on `wallpiper`). For a
   source build, follow upstream dependencies, run `make build-core`, then
   `make build-hyprland`, then `make install-wallpiperd`. Ensure `~/.local/bin`
   is on the shell process's `PATH` when using the local installation.
   This adapter targets the Wallpiper 2.1.0 CLI/portal layout. Keep the core and
   portal on matching versions and rerun the native checks below after upgrades;
   runtime compatibility is not established by the fixture tests.
   Wallpiper 2.1.0 adds Wayland frame delivery fixes; some AUR recipes still
   package 2.0.1. On Mesa systems where the 2.1.0 portal reports no render node,
   its surfaceless EGL context can incorrectly require pbuffer support.
   [This small source patch](patches/wallpiper-surfaceless-egl.patch) removes
   that unused surface requirement; apply it before rebuilding the portal.
3. Run `wallpiperctl check-config` to validate Steam, Proton, and Wallpaper Engine
   paths. Supply the environment overrides below if autodetection fails.
   Do not start `wallpiperd` manually or enable an autostart service.
4. For Workshop discovery, keep the existing Games Steam key or obtain a
   [personal Steam Web API key](https://steamcommunity.com/dev/apikey) and store
   it in the configuration described above. Installed browsing needs no key.
5. Restart Zephyrus Shell to load this integration and any changed environment.
   Open Pictures → Wallpaper Engine. Find a wallpaper in Workshop, download it
   through Steam if needed, wait for its download, and click **Apply wallpaper**. Choose
   **Installed** to browse your local Workshop library.

The selected wallpaper is applied to all current monitor slots. Zephyrus yields
its background surface only on outputs with a detected Wallpiper background
surface with visible frames. Apply waits for the daemon's tracked renderer before
sending control commands, avoiding a first-launch race; startup/control failures
retain the still-image fallback and reach the
Apply action. Fullscreen on any active, visible workspace pauses animation
globally; leaving fullscreen resumes it. Maximized windows, hidden workspaces,
and sleeping displays do not trigger fullscreen detection. All outputs asleep
pauses rendering until an output wakes. Commands are sent on state
transitions. After requesting Pause, the controller suspends only the daemon's
tracked, owned renderer process with `SIGSTOP`, ensuring it stops producing frames
even when a scene continues updating after Pause. It sends `SIGCONT` before Play
or shutdown; the portal retains the last frame and unrelated Steam/game processes
are untouched. The loaded scene remains in memory while suspended. The lock screen uses a project's
still preview, or keeps its existing image when no supported preview is available.

Standard Steam installations and paths in `steamapps/libraryfolders.vdf` are
detected. Both the current `distribution/wallpaper64.exe` layout and older
`wallpaper64.exe` layout are supported; the adapter supplies the detected renderer
path to Wallpiper automatically. Additional libraries can be listed in
`$XDG_CONFIG_HOME/zephyrus-shell/pictures.json`:

```json
{
  "wallpaper_engine": {
    "library_paths": ["/mnt/games/SteamLibrary"],
    "proton_bin": "/home/you/.local/share/Steam/compatibilitytools.d/GE-Proton11-5-x86_64/proton"
  }
}
```

Both fields are optional. `proton_bin` selects a compatibility tool for this
provider only; otherwise the controller resolves an executable Proton tool
across the discovered libraries and supplies that same path to the daemon and
control commands. Missing or non-executable configured paths produce a setup
warning, including during startup restoration. For a transparent/black background or control
timeouts, upstream recommends a tested Proton 11 build; see its
[troubleshooting notes](https://github.com/ejalxndr/wallpiper/blob/main/TROUBLESHOOTING.md).

Wallpiper's documented `WALLPIPER_STEAM_ROOT`, `WALLPIPER_PROTON_BIN`, and
`WALLPIPER_WE_EXE` overrides can be supplied in the shell's environment. The
controller selects the Hyprland portal, disables its tray, and gives its daemon
private temporary sockets and PID tracking. Runtime directories must be owned
by the current user, have private permissions, and cannot be symlinks. Lock
files cannot be symlinks either. Runtime acknowledgements and
`daemon.log` live in `$XDG_RUNTIME_DIR/zephyrus-wallpaper-<uid>-<config-hash>`
(under `/tmp` if `XDG_RUNTIME_DIR` is unset).
The previous daemon log is retained as `daemon.previous.log` on restart, and
terminal runtime errors include the log directory. Logs are diagnostic output
from Wallpiper; this adapter does not perform continuous log rotation.

Verify with `python3 -m unittest discover -s tests -p test_wallpaper_engine.py`
and `bash scripts/check-wallpaper-engine.sh`. The latter uses real module actions
and the production controller/worker with isolated executable fixtures, including
restoration at startup, transient surface loss, controller `SIGKILL` recovery,
and orphan cleanup during static startup. When a live Wallpiper session is already running, isolate
the smoke test's process view with
`bwrap --die-with-parent --unshare-pid --dev-bind / / --proc /proc bash scripts/check-wallpaper-engine.sh`.
Native
Wallpaper Engine/Proton rendering, physical monitor-slot mapping, and CPU/GPU
savings require a live desktop check.

Before treating a new Wallpiper/Proton/GPU combination as supported, check scene,
video, and web wallpapers; two outputs with different scales; unplug/replug and
DPMS sleep/wake; fullscreen pause/resume; changing choices while paused; and
switching to a still image. Restart the shell after killing only its recorded
wallpaper controller and verify recovery without affecting an independently
started Steam/game process. Confirm the fallback remains visible on startup
failure and that selecting a still image leaves no owned Wine/portal helpers.

Native checks on 2026-10-06 (Wallpaper Engine 2.8.42, GE-Proton11-5,
Hyprland/RADV RX 6800S, one DP-3 output): installed **Meteors at Dawn**
(`3413921910`) initially supplied a frame, then froze despite an alive renderer
and visible portal. Presence/alpha checks alone did not verify animation. With
native sleep/fullscreen/maximized heuristics disabled, captures taken seconds
apart changed, including after the production Apply path and owned-daemon
restart. Native preference restoration, controller crash recovery, fullscreen
pause/resume and DPMS transitions are also covered by isolated entry-point tests.

**Blue Archive** (`3510729512`) contains an H.264/AAC video inside a scene texture.
It consistently crashes at renderer offset `0xf178d` from Wine's `mfmediaengine`
load handler. Fresh isolated prefixes with both GE-Proton11-5 and Proton Hotfix
reproduce this failure. A media trace successfully identifies both streams, then
shows unsupported `IMFMediaSourceEx` queries before the native wrapper crashes.
This establishes a media-path compatibility failure, not its complete upstream
fix; no native executable or Wine binary is patched. Earlier checks without the
immediate Play command or with the native picker alive also failed. The adapter
contains the crash rather than repeating launches. Test prefixes were removed
and the live Meteors selection and original native preferences restored afterward.

Wallhaven has three broad content categories: General, Anime, and People. “All
categories” combines them. More specific subjects are tags, so category and
tag stay as separate filters and can be used together. The Tags dropdown has
popular suggestions and an inline search field that filters the suggestions as
you type. Typing also searches Wallhaven's tag directory and replaces the
suggestions with matching tags; selecting a result applies its exact tag ID.
The JSON API supports free-text tag queries and lookup by a known ID, but does
not document tag autocomplete, so tag suggestions use Wallhaven's public HTML
search page. If that page is unavailable, the typed text remains usable as a
Wallhaven query. Queries can use `+tag` to require a tag, `-tag` to exclude
one, and `id:37` for an exact tag ID. The clear button inside the field
restores the suggestions. The visible SFW selector was removed; Wallhaven
requests continue to default to SFW. See
[Wallhaven's search API](https://wallhaven.cc/help/api#search).

The catalogue can switch between a horizontal strip and a grid. A selected
image first uses its uncropped provider preview when available, then fades a
higher-resolution image over it when the displayed size needs one. Favorites
retain their provider identity and are stored in
`$XDG_CONFIG_HOME/zephyrus-shell/pictures-favorites.json` (or
`~/.config/zephyrus-shell/pictures-favorites.json` when `XDG_CONFIG_HOME` is
not set).

Bing Daily uses Microsoft's homepage feed at
[`HPImageArchive.aspx`](https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8&mkt=en-US).
It is an official Bing endpoint, but Microsoft does not document it as a
supported developer API. The feed exposes only a small recent window (about
two weeks), so Bing search and random selection are limited to those images.
Pictures keeps Bing's title, copyright credit, and Bing detail link with each
image. The images remain copyrighted by their listed owners.

Use **Set wallpaper & lock screen** to download the selected original and apply
it to Zephyrus Shell's desktop on every monitor. No separate wallpaper daemon
is needed. The choice is saved in
`$XDG_CONFIG_HOME/zephyrus-shell/wallpaper.json` and survives closing Pictures
and restarting the shell. Downloaded originals are kept in
`$XDG_DATA_HOME/zephyrus-shell/wallpapers` (or `~/.local/share/zephyrus-shell/wallpapers`).
Downloads have a one-minute deadline; failures restore the button and display
an error. Hide Pictures with Escape or select Desktop to see the wallpaper.

To set a random wallpaper at startup in Hyprland, add the backend command to
`hyprland.conf`:

```ini
exec-once = python3 /absolute/path/to/zephyrus-shell/pictures/backend.py --random
```

`--random` chooses a random provider and then a random image from that
provider. Pin a provider with `--provider=wallhaven` or `--provider=bing`; use
`--country=VN` (or another supported country code) to choose the Bing market
when Bing is selected. Wallhaven uses its random API ordering. Bing chooses
from the recent images in its homepage feed. Wallhaven uses the default SFW
filters. The command updates the same saved desktop setting as the module
button, including when it runs before the shell starts.

For use outside Zephyrus Shell, add `--target=desktop`. This retains support
for swww, hyprpaper, KDE Plasma, and GNOME. Start `swww-daemon` or hyprpaper
when using those services. On a custom desktop, set
`ZEPHYRUS_WALLPAPER_COMMAND` to a command with an optional `{path}` argument,
for example `my-wallpaper-tool --file {path}`. An external wallpaper service
cannot replace Zephyrus Shell's own opaque background.

Setting a wallpaper also updates the lock-screen image. Hyprlock reads the
atomic `zephyrus-shell/lock-wallpaper` symlink on the next lock; the image stays
in the Pictures cache, with no second download or wallpaper daemon. This applies
to both shell and external desktop targets.

## Command provider plugins

Pictures supports explicitly configured, user-owned wallpaper commands in
`$XDG_CONFIG_HOME/zephyrus-shell/pictures.json`. Provider code, accounts, scraping,
and dependencies belong to those packages outside the repository. Nothing is
scanned or installed automatically; removing a configuration entry disables it.
The built-in providers do not require any command plugins.

See [pictures.example.json](../pictures/pictures.example.json):

```json
{
  "providers": [
    {
      "id": "personal_wallpapers",
      "name": "Personal wallpapers",
      "plugin": "/absolute/path/to/wallpaper-provider",
      "env": {}
    }
  ]
}
```

IDs must be unique lower-case identifiers (`[a-z][a-z0-9_-]{0,63}`), distinct from
built-in IDs. Names must be unique nonempty single lines. Choose either `plugin`
or a direct argument-array `command`. A package contains `manifest.json` with
`api_version: 1` and `command`, as in the
[example manifest](../pictures/provider-plugin.example/manifest.json).
`{plugin_dir}` expands to the absolute package directory without shell expansion.
Relative plugin paths resolve beside `pictures.json`; paths with spaces work.
Optional `env_file` and `env` follow the shared
[Books provider configuration rules](books.md#provider-plugins), including literal
assignments, per-operation reload, private files, and diagnostic redaction.
Pictures and Books share the package loader and owned command runner, while their
operation protocols remain separate.

Commands receive one JSON request on stdin and return one JSON object on stdout.
Send diagnostics to stderr. Commands run directly without a shell or third-party
Python imports, with a 25-second timeout. Timeout, module closure, and worker
shutdown terminate owned command process groups. Loading the provider list
starts no command. Commands run only when browsing their category or applying a
selected item. Provider failures appear through existing loading/error states.

### Browse and resolve protocol

Browse uses one-based pages by default. The next page may be a nonnegative
integer or an opaque string; Pictures returns it unchanged on the next request.
Queries and filters belong to the command.

```json
{"op":"browse","query":"clouds","page":1,"filters":{}}
```

```json
{
  "success": true,
  "items": [
    {
      "id": "clouds-1",
      "title": "Clouds",
      "kind": "video",
      "preview": "https://example.org/clouds.jpg",
      "thumbSmall": "https://example.org/clouds-thumb.jpg",
      "url": "https://example.org/clouds",
      "ref": {"record":"clouds-1"}
    }
  ],
  "next": "next-page-token"
}
```

Each item requires a nonempty string `id`, nonempty `title`, and opaque JSON
`ref`. `kind` is `image` (default) or `video`. Optional `preview`, `thumbSmall`,
`thumbLarge`, and `url` are HTTP(S) URLs without embedded credentials. Previews
and thumbnails are still images, including for videos. Optional `width`, `height`,
`fileSize`, and `description` populate the existing details. Each response is
limited to 500 items. Generic command providers support discovery, free-text
search, pagination, and Favorites; random selection and provider-specific filter
controls are not exposed in this initial protocol.

Applying a selected wallpaper sends its reference back unchanged:

```json
{"op":"resolve","ref":{"record":"clouds-1"}}
```

```json
{"success":true,"url":"https://example.org/clouds.mp4","headers":{"Referer":"https://example.org/clouds"}}
```

Optional headers are string mappings without control characters. Resolved URLs
and headers are used only for the download, never saved in Favorites or wallpaper
settings. Both operations can return `{"success":false,"error":"Retry later."}`.
References and still-image metadata persist with Favorites; do not include
credentials or short-lived download URLs in references. Cached original files
use hashed item IDs and provider IDs, so arbitrary catalogue IDs cannot escape
the wallpaper directory or collide after punctuation replacement. Removing a
provider hides its Favorites until re-enabled; saving other Favorites preserves
those disabled-provider records.

Image downloads use the existing desktop and lock-screen path. Video downloads
accept MP4 containers only, validate content type and the MP4 signature, and
reject HTML/software responses. Downloads have a 60-second deadline; images
are limited to 250 MiB, videos to 1 GiB. Partial files are removed on failure.

### Optional video playback

Install `mpvpaper` and `ffmpeg` separately to apply a video wallpaper in a Hyprland
session. These are optional dependencies; browsing, Favorites, and image wallpapers
continue to work without them. Missing requirements appear when applying a video,
before resolving or downloading it. See the
[mpvpaper documentation](https://github.com/GhostNaN/mpvpaper).

The existing session wallpaper controller owns the player, with silent looping,
hardware decoding when available, and fill cropping across all outputs. It waits
for MPV playback and visible Background-layer surfaces before yielding the shell's
still backdrop. A separate manually started `mpvpaper` session is left alone and
reported to the user. Fullscreen applications and sleeping outputs pause playback.
Closing Pictures leaves playback running; the saved video restores when the shell
starts. Choosing a still wallpaper or another renderer stops the owned player.
Shell shutdown and crash recovery use the same process-ownership journal as the
existing animated wallpaper controller. A playback failure keeps a still backdrop
and requires explicit Apply to retry.

`ffmpeg` extracts one still frame into the wallpaper cache for the desktop fallback
and lock screen; video itself never becomes the lock-screen image. Saved settings
contain `mode: "video"`, the local MP4 path, provider ID, selection identity, and
still-frame image URL. Failed startup restores a previous static choice; failures
when replacing animated playback remain latched until explicit Apply, avoiding
repeated renderer launches.

Verification: `python3 -m unittest discover -s tests -p 'test_picture*.py'`,
`bash scripts/check-pictures.sh`, and `bash scripts/check-picture-providers.sh`.
The plugin smoke check uses real module entry points, command packages, downloads,
FFmpeg still extraction, the session controller, and owned player/IPC fixtures.
Native visual quality and hardware decoding still need a real desktop check.
