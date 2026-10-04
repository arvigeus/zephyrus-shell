# Production readiness review

The shell is a personal Hyprland desktop: launch applications, switch between
built-in catalogue/work modules, control the machine, and keep requested
background work alive. Extensibility through runtime plugin discovery added cost
without supporting that daily workflow.

## Changes

- Fixed, ordered spaces in `core/Modules.qml`, with statically declared components
  in `shell/ModuleOverlay.qml`. Removed discovery subprocess, manifests, templates,
  reload UI/IPC and registry reconciliation. Instances remain lazy and asynchronous.
  Only running modules have loader delegates; retained playback, owned hosts,
  opaque navigation, and monitor ownership stay in the shared lifecycle.
- Optional torrent, scan and subtitle workers start on first use. Books and Games
  read the existing local-library schema through their catalogue worker instead of
  spawning a torrent backend for read-only operations.
- Worker requests queue until process startup. Timeout timers run only with
  callbacks pending. Read traffic leaves capacity for ordered controls; completed
  supersession scopes are released. Invalid protocol data and non-serializable
  backend results settle requests; unexpected exceptions are logged to stderr.
- Atomic file replacement uses one helper with unique temporary files, flushing,
  restrictive permissions and cleanup. Theme, weather/calendar cache and catalogue
  favorites use it, preserving existing XDG paths and formats.
- Calendar mutations fence cache publication across panel and one-shot bar
  processes. Reads started before or during a mutation cannot republish the old
  snapshot. Failed writes preserve offline data; network requests never hold the
  publication lock.
  Malformed calendar/weather caches are discarded and refetched, and invalid
  weather time zones produce a configuration error.
- Files uses `os.scandir` metadata and resolves symlinks only when checking the home
  boundary. Ordinary directory entries no longer resolve their entire parent chain.
- Media and Music separate pure record normalization from network/persistence
  coordination. Python uses consistent Ruff formatting, local lint configuration,
  and ty checks of shipped code. Optional generated PyGObject imports carry narrow
  type-checker annotations.
- Settings moves incidental instructions into tooltips and avoids empty subtitle
  space. Labels needed to distinguish actions, expose errors, or explain destructive
  operations remain visible. The clipboard expectation and virtualized QML test
  timing were corrected to reflect real behavior.
- Projects uses one toolbar and compact rows, with full paths and opened dates in
  tooltips. Files omits redundant folder labels while retaining the folder icon.

## Verification

`make check` runs Ruff, formatting, ty, Python tests, portable Qt QML tests, Node
checks, performance budgets, and isolated Quickshell integration checks. Workers
are exercised through their real backends; module checks use the real entry
points and ShellState actions. Packaging tests stage and inspect the runtime.

The completed checks passed Ruff, formatting and ty; 397 Python tests, 51 QML
tests, 13 Node tests, all 15 smoke checks, performance budgets and the Hyprland
configuration parser. A local comparison on 1,500 directory entries measured a
median of 37.61 ms before the Files refactor and 11.62 ms after it (seven runs).
This measures listing overhead, not end-to-end UI latency.

Loopback HTTP fixtures and private D-Bus sessions need permission outside a
restricted sandbox. Offscreen integration verifies loading, interaction logic and
lifetime; the compositor parser verifies the shipped Lua syntax. Physical hotplug,
actual audio output, and configured remote accounts still need the real desktop.

Do not replace distinct catalogue persistence and pagination with a universal
controller merely because their UI looks similar. Keep provider identity, offline
records, import semantics and existing data paths intact when changing those
boundaries. Terminal command submission intentionally retains an interactive
session until explicit Close; background downloads and custom actions also have
explicit owners.
