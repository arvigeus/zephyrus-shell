# Where changes belong

## Module roles

| Space | Job |
| --- | --- |
| Desktop | Reveal the Hyprland session and its normal windows. |
| Applications | Find and launch installed desktop applications; keep personal favorites. |
| Projects | Find local XDG Projects, create or clone a project, and open it in Zed. |
| Files and Terminal | Work with local files and commands without adding resident services. |
| Movies and TV Series | Discover titles and resolve configured watch sources; share one media browser and backend. |
| Music and Radio | Browse a catalogue or station directory and own playback that can continue behind Desktop. |
| Books | Browse Open Library works, authors, and editions; save favorites offline. |
| Games | Discover IGDB titles, relate them to local Steam/Epic libraries, and launch or buy through those stores. |
| Pictures | Browse wallpaper providers and set a chosen image on the desktop. |

Catalogue modules share theme tokens, search controls, loading/empty states,
artwork transitions, and worker ownership patterns. Each provider adapter stays
in its module backend, so the shell only handles navigation and lifetime.

## Code ownership

| Area | Owner |
| --- | --- |
| Entry point and IPC | `shell.qml` |
| Per-monitor surfaces and input regions | `shell/ShellScreen.qml` |
| Running windows and tray | `shell/RunningApps.qml` |
| Background | `shell/Backdrop.qml` |
| Shared module overlay and host contract | `shell/ModuleOverlay.qml` |
| Panel selection | `core/ShellState.qml` |
| Colors and type | `core/theme/Theme.qml`, with the `core/Theme.qml` compatibility facade |
| Plugin registry | `core/Plugins.qml`, `scripts/plugins.py` |
| Notification server | `core/Attention.qml` |
| Weather/calendar in-memory snapshot | `core/AttentionData.qml` (passive cache); requests owned by `attention/AttentionPanel.qml` |
| Owned worker transport and scheduling | `services/Worker.qml`, `services/worker.py` |
| Shared public-response cache | `services/cache.py` |
| Module-owned mpv IPC transport | `services/mpv.py`; players and playback state stay in Music/Radio |
| Local account header and read-only profile dialog | `widgets/UserProfileButton.qml`, `widgets/UserProfilePanel.qml`, `scripts/user_profile.py` |
| Reusable UI | `widgets/` |
| Drawer framing, loader and composition | `drawers/` |
| Machine controls, one section per file | `settings/` |
| Inline network selection | `settings/WifiPage.qml`, `settings/BluetoothPage.qml` |
| Owned Bluetooth pairing agent | `scripts/bluetooth_pair.py` |
| Audio route metadata and naming rules | `scripts/audio_devices.py`, `config/audio/` |
| Allowlisted machine actions | `scripts/machine.py` |
| Calendar and notification views | `attention/` |
| Independent library entries | `plugins/<id>/` |
| Floating behavior and shortcuts | `hyprland/` |

`ShellScreen` creates a bar and overlay windows per monitor. Its bar reserves 66 px
for windows and uses an input mask containing only the pills and app icons. Drawers
ignore the exclusive zone and sit above the bar, covering the corresponding pill
without rearranging floating windows. They touch the top, bottom, and side edges
with square corners. `DrawerSlide.qml` animates entry and exit from the owning
edge over 220 ms; the window and content remain alive until exit completes.
Each drawer uses a transparent full-screen surface with a separate outside-click
area that never overlaps the drawer rectangle. Outside clicks are consumed to
dismiss, without activating the application behind it. Module backgrounds fill the desktop behind the bar; content starts below it.
The bar uses the overlay layer above the module’s top layer, leaving pills visible and
clickable. One module is visible at a time; retained modules can keep their owned
players and workers alive behind the Desktop.

Drawer windows stay declared but their Loader is inactive while hidden. The Spaces
drawer lists Desktop first, then plugin metadata. Opening it leaves the current
module visible. Selecting Desktop hides the overlay and reveals the Hyprland
session. The shared module overlay owns an asynchronous loader slot for each
module. Music and Radio request retention while playback is active, so switching
modules can leave playback running. Escape or the drawer’s
Close control destroys the selected module. Core services are shared across
monitors. A retained module stays owned by the monitor where it opened; opening
a drawer on another monitor does not recreate its player. Optional plugin
services must not be core singletons.

`ShellState` is the sole writer of module lifetime bookkeeping: running IDs,
monitor ownership, retention, and pending navigation. Registry reload passes
installed IDs to `ShellState.reconcilePlugins`; registry and visual components
must not independently rewrite those maps. `ModuleLoader` gates overlays by
monitor ownership; `ModuleOverlay` gates creation until drawers finish closing.
Each module receives its own host, so a hidden module can close itself without
closing the selected space. Cross-module navigation uses `host.openPlugin(id,
payload)` and optional destination `handleOpen(payload)`; the host validates
availability and delivers once, while the modules interpret the payload. See
[the host contract](plugins.md).

`services/` contains reusable infrastructure, not automatically resident services.
`Worker.qml` owns a process and settles callbacks on response, timeout, or exit.
`worker.py` bounds pending work, serializes mutation operations, and emits a reply
even for superseded reads. Backend generation filtering does not cancel a read
already in progress: views still guard selections and browse results against
late replies. Module adapters define their operations, mutation lanes, provider
rules, and errors. Shared mpv code owns only socket validation, framing, and
cleanup; it neither starts players nor stores playback state.

Catalogue reuse is at stable UI boundaries: theme, search, artwork, model
reconciliation, scroll handling, and transport. Domain identity, pagination,
favorites, stale-data fallback, and details stay with each catalogue backend.
Books' Work/Edition relationships, Games' store/library matches, and Media's
IMDb/TMDB aliases justify distinct persistence implementations. Do not replace
them with a universal catalogue controller or database solely because they use
similar rails and SQLite tables.

Attention views bind to the passive `AttentionData` snapshot without assigning
local copies. Panel loading flags, request generations, month selection, and
editor state are transient UI state. The worker and refresh timers currently
exist only while the panel is open. Before adding a second Nextcloud consumer,
establish one integration owner for credentials, CalDAV requests, cache
invalidation, and mutation completion under `attention/` or `services/`; views
should subscribe to it rather than create another calendar/task cache. Choose
its lifetime explicitly instead of making it resident through a plugin import.

Configuration and secrets belong in `$XDG_CONFIG_HOME/zephyrus-shell`; persistent
records belong in `$XDG_DATA_HOME/zephyrus-shell`; replaceable public responses
belong in `$XDG_CACHE_HOME/zephyrus-shell`. Existing Music/Radio/App favorites in
configuration and catalogue-specific database locations are compatibility paths;
changing them requires a migration, not an incidental refactor. Player sockets
use private per-module runtime directories, with a short temporary path fallback
for Unix socket length limits. `Paths.file()` resolves repository resources, not
user data. User-directory resolution remains separate from application XDG roots.

Smoke harnesses must use the real module entry points, shared loader, and
`ShellState` actions. Do not emulate lifetime by assigning loader activity or
navigation fields directly. State-only checks run inside Quickshell because the
core import includes its native bindings; ordinary Qt QML tests cover portable
widgets. See [the architecture review](architecture-review.md) for deferred work
and validation limits.

Machine actions use argument arrays, never interpolated shell commands. Controls
invoke an explicit allowlist. A Python snapshot process runs when controls open;
it has no permanent polling loop. PipeWire and UPower use Quickshell's native bindings.

The shell and compositor configurations are independent. You can use the shell
with your own Hyprland config, or adjust compositor bindings without touching QML.
The shipped Lua was validated against the installed Hyprland, whose API differs
from older `hyprland.conf` and early Lua configurations.

Interface icons use bundled Lucide SVGs through `widgets/Icon.qml` or
`Action.iconName`; native application and brand icons are the exception. See
`AGENTS.md` for contributor conventions.

Hardware snapshots live in `core/HardwareSnapshot.qml`: a startup read warms the
cache, and opening Settings or requesting refresh updates it without clearing
previous readings. There is no polling timer. Profile selection closes the drawer
and opens a separate profile surface after the exit animation.

Sensor selection and weather interpretation belong to their Python data owners:
`scripts/machine.py` chooses representative CPU/GPU sensors and
`attention/weather.py` summarizes full local days from hourly conditions. QML
formats these results and lays out the current, hourly and daily views; it does
not choose sensors or infer daily weather independently.
