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
| Colors and type | `core/Theme.qml` |
| Plugin registry | `core/Plugins.qml`, `scripts/plugins.py` |
| Notification server | `core/Attention.qml` |
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
