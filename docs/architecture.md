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
| Running windows and tray | `shell/RunningApps.qml`, `shell/TrayPill.qml`, `shell/TrayButton.qml` |
| Shared compositor geometry and window ordering | `core/WindowList.qml`, `core/windows/WindowOrderModel.qml`, `core/WindowOrder.js` |
| Background | `shell/Backdrop.qml` |
| Shared module overlay and host contract | `shell/ModuleOverlay.qml` |
| Panel selection | `core/ShellState.qml` |
| Colors and type | `core/theme/Theme.qml`, with the `core/Theme.qml` compatibility facade |
| Ordered built-in spaces | `core/Modules.qml` |
| Pure provider record normalization | `media/records.py`, `plugins/music/records.py` |
| Atomic state replacement | `services/storage.py` |
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
| Clipboard popover and its owned history worker | `clipboard/`; session-owned cliphist watchers record history |
| Independent library entries | `plugins/<id>/` |
| Scrolling layout, optional floating and shortcuts | `hyprland/` |

`ShellScreen` creates a passive desktop bar and a transient interaction window
per monitor. Both reserve 42 px for desktop windows. One set of pills moves to
the interaction window while a module or bar popup is open. The passive bar
never requests keyboard focus; the interaction window unmaps on dismissal. Its
input mask contains the pills and, for an open module, the area below them. Drawers
ignore the exclusive zone and sit above the bar, covering the corresponding pill
without rearranging desktop windows. They touch the top, bottom, and side edges
with square corners. `DrawerSlide.qml` animates entry and exit from the owning
edge over 140 ms; the window and content remain alive until exit completes.
Each drawer uses a transparent full-screen surface with a separate outside-click
area that never overlaps the drawer rectangle. Outside clicks are consumed to
dismiss, without activating the application behind it. Module backgrounds fill the desktop behind the bar; content starts below it.
The interaction window uses Overlay while a module is visible and Top while
drawers are showing. Pills and module content share one keyboard owner. One
module is visible at a time; all open modules keep their state and owned
resources behind Desktop until explicitly closed.

`WindowList` keeps Wayland activation handles and orders them by Hyprland's
monitor, workspace and horizontal column geometry. It refreshes after compositor
events settle, with one shared one-second geometry refresh while multiple windows
exist to cover silent column moves. `WindowOrderModel` coalesces per-window IPC
changes until the current response has finished, publishing one complete order
and suppressing updates when only the scroll offset changes.
`RunningApps` wraps that list in `ScriptModel`
so reordering preserves existing buttons, decoded icons and keyboard focus.
Without compositor metadata it retains the Wayland list as a fallback.
`widgets/ReorderDrag.qml` supplies the local pointer gesture; `RunningApps` owns
the insertion marker and edge scrolling. A completed drop goes through
`WindowList` to `zephyrus.reorder_column` in `hyprland/windows.lua`, which checks
current workspace/monitor geometry and uses native scrolling-column swaps.

Drawer windows stay declared but their Loader is inactive while hidden. The Spaces
drawer lists Desktop first, then built-in spaces. Opening it leaves the current
module visible. Selecting Desktop hides the overlay and reveals the Hyprland
session. The shared module overlay creates an asynchronous loader slot for each
running module using statically declared components. Desktop, navigation and
Escape hide the selected module. The Spaces sidebar X destroys it; closing an
entry leaves the drawer open, so several modules can be stopped in one visit. Core services are shared across
monitors. An open module stays owned by the monitor where it opened; opening
a drawer on another monitor does not recreate its player. Optional plugin
services must not be core singletons. In the live shell, one module loader is
owned by the shell root and visually attached to the selected screen's module
surface. Removing that surface reparents the loader onto a surviving screen;
the loaded module objects and their workers keep their lifetime.

`ShellState` is the sole writer of module lifetime bookkeeping: running IDs,
monitor ownership and pending navigation. Visual components never
rewrite those maps. There is no runtime module scan, manifest parsing, or registry
reload. Unopened modules have no instances, workers, or loader delegates. `ShellState.reconcileScreens` moves
ownership when a screen disappears. `ModuleLoader` supports the shared live-shell
host and individual preview hosts; `ModuleOverlay` gates creation until drawers finish closing.
Each module receives its own host, so a hidden module can close itself without
closing the selected space. Cross-module navigation uses `host.openModule(id,
payload)` and optional destination `handleOpen(payload)`; the host validates
availability and delivers once, while the modules interpret the payload. See
[the host contract](plugins.md).

`services/` contains reusable infrastructure, not automatically resident services.
`Worker.qml` owns a process and settles callbacks on response, timeout, or exit.
Startup requests wait for the process to start. Optional torrent/subtitle workers
start on their first request; unused services have no process or polling timer.
Books and Games read their local library through their existing catalogue worker.
`worker.py` bounds pending work, serializes mutation operations, and emits a reply
even for superseded reads. Read queues reserve capacity for controls, and
supersession bookkeeping is bounded by pending work. Unexpected backend exceptions
are logged to stderr and still settle the request. Backend generation filtering does not cancel a read
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
editor state are transient UI state. The panel worker exists only while the panel is open. The bar uses a one-shot
reader every 15 minutes. Both use `attention/backend.py` for credentials, CalDAV
requests and cache publication. A short file lock and revision fence prevent
reads started before or during a mutation from restoring the invalidated cache;
network calls do not hold the lock. Failed writes retain the offline snapshot.

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
widgets. Provider fixtures validate local behavior; live account and physical monitor
behavior still require the real session.

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

## Settings and weather snapshots

The right drawer is created lazily and retained after its closing animation.
Its last hardware snapshot stays usable while fresh readings arrive. Reopening
within 30 seconds reuses the snapshot; explicit refresh, completed actions,
monitor hotplug/reload and power-source changes refresh it. Native PipeWire,
NetworkManager and UPower properties continue to drive live status. Shared,
debounced event connections avoid duplicate queries from multiple monitor bars.
Old snapshot responses cannot overwrite a change made by an action. DDC reads
are cached for 60 seconds and invalidated after brightness writes. Hidden
battery polling, Wi-Fi/Bluetooth scanning and the audio subscription stop while
the drawer is closed. Optional module workers retain their normal lifecycle.

All clock pills and Attention share `AttentionData`'s forecast and one one-shot
weather request every 15 minutes. The existing disk cache survives shell restarts
and keeps the previous forecast during network errors. No resident weather
worker, per-monitor network request or second-by-second polling is added.
