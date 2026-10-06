# Zephyrus Shell

A personal Quickshell desktop for Hyprland: desktop pills, two drawers, a quiet center.
Built for Quickshell 0.3.1 and Hyprland 0.56.2's Lua configuration.

## Try it

Prepare an Arch system once before the first run:

```sh
scripts/setup-system.sh
```

The script builds and installs `zephyrus-shell-git` and its full-session
dependency package from this checkout. Required and optional package metadata
live in [`PKGBUILD`](PKGBUILD); this local build does not fetch the shell
repository again. The script leaves NetworkManager,
Bluetooth and switcheroo-control service state unchanged by default. Pass
`--enable-services` to enable networking and Bluetooth; see [system setup](docs/setup.md).

From this directory, inside a Hyprland session:

```sh
quickshell -n -p .
```

From KDE or another desktop, use the ordinary-window preview:

```sh
dbus-run-session quickshell -p ./preview.qml
```

The preview uses real components and the current system clock. Its center panel
uses the configured weather and Nextcloud data. A private bus
keeps its notification server separate from the existing desktop. Running apps and
tray integration are exercised by the actual shell, not this component preview.

Install the development session shim once, then select **Hyprland (uwsm-managed)** at login:

```sh
python3 scripts/setup-session.py install
python3 scripts/migrate-nextcloud.py
```

The shim loads the repository's separated Lua modules, so edits need no copying.
Existing configuration is backed up and can be restored with
`python3 scripts/setup-session.py teardown`. This machine's shim, credential
migration are already prepared. The scrolling layout needs no plugins. See
[session setup and live test checklist](docs/session.md) and
[shared Nextcloud configuration](docs/nextcloud.md).

## What works

- Shared colors and typography for the shell, KDE/Qt, GTK, Kitty and supported editors, with automatic theme-file updates and a common light/dark preference. See [desktop appearance](docs/theme.md) for app coverage and restoration.
- A language switcher on the right, with a neutral English globe and labeled dropdown: Alt+Shift uses English/Bulgarian phonetic by default. Explicitly selecting Vietnamese starts Telex and changes the pair to English/Vietnamese; selecting Bulgarian stops it. See [input languages](docs/input-languages.md).
- Separate pills for Spaces, running windows, the clock, the tray and Settings; empty lists hide, and gaps pass pointer input through.
- Left and right overlay drawers; opening a panel closes the previous one. Escape closes it.
- One drawer on one monitor at a time, with pills on every monitor.
- Applications opens a desktop overlay below the pills, with favorites, a searchable app grid and category filters.
  Favorites is the default tab when any saved favorites are installed; otherwise
  All applications opens. Star buttons add/remove apps. Search from Favorites
  searches all apps. Selections persist in `$XDG_CONFIG_HOME/zephyrus-shell/applications.ini`
  (default `~/.config/zephyrus-shell/applications.ini`). This is a separate list from
  KDE launcher favorites. Stars appear on hover or keyboard focus; saved favorites
  always display a filled star.
- Projects lists folders in the XDG Projects directory, shows local logos and technology badges,
  and opens them in Zed. New Project offers interactive starters, Git Clone supports clone modes,
  and project menus provide Mise and maintenance actions. See [Projects](docs/projects.md).
- Movies and TV Series offer shared catalogue services, search/filters, rail/grid views,
  title artwork, favorites, online provider selection, trailers, full cast/crew, and TV episodes. TMDB provides discovery;
  configured OMDb can supply title search, details, and episodes when needed. See
  [media configuration](docs/media.md) for API keys, provider templates, and limitations.
- Books opens on current Open Library trends with searchable Work-level results,
  subject/language/year filters, rail/grid covers, author links, lazy editions, and
  offline Favorites. No API key is required; see [Books](docs/books.md) for API and cache details.
- Games adds a Discover/Favorites catalog with search, filters, and rail/grid views,
  locally detected Steam installs and launch, optional Epic ownership/install/launch
  through Legendary, UMU support for Epic games, and detail-page ProtonDB guidance.
  Configure the catalog and optional Steam ownership in [Games setup](docs/games.md).
- Terminal has independent shell tabs, shared light/dark colors and a Play menu for
  configurable named commands. Closing the module ends its sessions. See
  [Terminal configuration](docs/terminal.md).
- Spaces opens the module drawer over the current view. Desktop reveals the Hyprland session; Music and Radio can keep playing there until closed.
- Tap Win to open Spaces, then type to search installed applications and space names.
  Up/Down selects a result and Enter opens it; Escape closes the drawer/search.
- Running-window activation and tray activation/context menus beside the left pill.
- Live clock, weather, navigable Nextcloud calendar, task lists, notifications,
  actions, dismissal, toast, and do-not-disturb. Attention has Priority and All views.
  The clock pill indicates today's tasks and events plus pending notifications.
- Separate named audio output and microphone selection, level and mute controls.
- GNOME-style Wi-Fi/Bluetooth split tiles, with device selection inside Control room.
- Inline Wi-Fi passwords and Bluetooth pairing confirmation/PIN entry.
- Laptop brightness through brightnessctl or logind, power profiles, battery status and charge limit.
- Confirmed session actions; native scrolling columns, with optional floating per window.
- A static, procedurally drawn background. No wallpaper download or resident animation.

The Settings drawer has saved profiles, expandable connectivity/audio/display controls and lazily loaded battery information,
CPU/GPU and System cards, and ASUS power profiles. Hardware controls are enabled only
when their backend is available. See [settings configuration](docs/settings.md)
for profiles, battery health and automation, display aliases, DDC brightness and limitations.
Networking, Bluetooth, audio and battery automation use service events. Hardware
readings refresh on opening, actions, battery changes or manual refresh.

## Dependencies and boundaries

See [packaging and dependency ownership](docs/packaging.md) for local builds,
consumer integration, updates and migration. The Arch packages' runtime
dependencies are listed in [`PKGBUILD`](PKGBUILD).
`zephyrus-shell-git` contains the shell and its core dependencies;
`zephyrus-shell-session-git` supplies the full Hyprland session dependency set.
`scripts/setup-system.sh` builds both packages from the current checkout, then
installs the full-session dependency set. Package
installation itself does not enable services or change I2C permissions. Those
actions happen only through the explicit setup command;
see [system setup](docs/setup.md). Your existing Kitty and Dolphin bindings are
retained. No external network or Bluetooth settings application is launched by
the drawer.

The session uses hyprlock/hypridle for locking, idle blanking and locking before
suspend. Super+L locks manually. Quickshell owns notifications; Hyprland and GTK
portals provide sharing and file chooser integration. Power profile, brightness
and GPU helpers remain optional. See [session behavior](docs/session.md).

Weather and Nextcloud need the [attention configuration](docs/attention-design.md).
Persistent notification history and local media-library scanning are future
integrations. Notifications are retained only for the shell's lifetime, capped at
100. Wi-Fi supports saved profiles, open networks, and WPA/WPA2/WPA3 personal
passwords. New enterprise/certificate profiles and hidden network creation are not
yet implemented. Bluetooth discovery is user-triggered and stops after 30 seconds
or when leaving its page. Pairing prompts require an explicit answer; the helper
never becomes the system's default Bluetooth agent.

## Daily shortcuts

| Shortcut | Action |
| --- | --- |
| Super + Space | Left drawer |
| Super + C | Calendar and notifications |
| Super + Comma | Controls |
| Escape (drawer focused) / Super + Escape | Close panel |
| Super + Enter / E | Kitty / Dolphin |
| Super + left / right drag | Move / resize a window |
| Super + Left / Right | Focus previous / next scrolling column |
| Super + mouse wheel | Scroll previous / next column |
| Super + V | Toggle floating for the current window |
| Super + Q / Alt + F4 | Close current window |
| Super + M | Maximize/restore current window |
| Super + L | Lock session |
| Super + 1–9 | Workspace |
| Super + Shift + 1–9 | Move window to workspace |

The panel hides behind fullscreen applications and returns when fullscreen ends.
Maximized windows keep the panel visible. Shell modules, including Movies and
TV Series, also keep it visible above their content.

## Extend and customize

Read [docs/plugins.md](docs/plugins.md) to add a built-in space. The ordered list
lives in `core/Modules.qml`; components are declared in `shell/ModuleOverlay.qml`.
Instances and their workers are created only when needed. Desktop is built in.

Read [docs/architecture.md](docs/architecture.md) for the file map. Colors, spacing,
and typography live in `core/Theme.qml`; individual machine sections live in
`settings/`; window behavior is in `hyprland/windows.lua`.

See [audio naming](docs/audio-names.md) for per-monitor/per-device JSON rules, and
[attention configuration](docs/attention-design.md) for weather and Nextcloud.

## Check changes

```sh
make check
# Individual checks:
ruff check .
ruff format --check .
ty check
python3 -m unittest discover -s tests -v
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qmltestrunner -input tests/qml -import .
node --test tests/*.test.cjs
Hyprland --verify-config -c "$PWD/hyprland/hyprland.lua"
bash scripts/check-preview.sh
bash scripts/check-apps.sh
bash scripts/check-media.sh
bash scripts/check-books.sh
bash scripts/check-games.sh
bash scripts/check-workers.sh
bash scripts/check-modules.sh
bash scripts/check-retained.sh
bash scripts/check-transfers.sh
bash scripts/check-file-open.sh
bash scripts/check-drive-sign-in.sh
bash scripts/check-tray.sh
bash scripts/check-spaces.sh
bash scripts/check-desktop.sh
bash scripts/check-language.sh
python3 scripts/check-performance.py
python3 scripts/benchmark-shell.py --output tests/artifacts/performance-baseline.json
# Briefly opens the actual panels on your current Wayland desktop:
bash scripts/check-wayland.sh
# Exercises native controls against its own temporary window:
bash scripts/check-windows.sh
```

The preview check opens every panel and saves images under `tests/artifacts/`.
Apps, catalogue, and module checks load real entry points. The retained check
also tests `ShellState` transitions and host ownership inside Quickshell.
The offscreen backend emits expected window-mask warnings. Actual layer-shell
placement, focus, and multi-monitor behavior also need testing in Hyprland.

See [performance and autoresearch](docs/performance.md) for reproducible UI,
process-resource benchmarks and the profile/verify/improve experiment loop.

References: [Quickshell documentation](https://quickshell.org/docs/v0.3.1/),
[Hyprland configuration](https://wiki.hypr.land/),
[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell).

Interface icons use bundled Lucide SVGs. See [contributor conventions](AGENTS.md)
and [plugin documentation](docs/plugins.md); native app icons retain their artwork.
