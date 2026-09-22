# Zephyrus Shell

A personal Quickshell desktop for Hyprland: three pills, two drawers, a quiet center.
Built for Quickshell 0.3.1 and Hyprland 0.56.2's Lua configuration.

## Try it

From this directory, inside a Hyprland session:

```sh
quickshell -p .
```

From KDE or another desktop, use the ordinary-window preview:

```sh
dbus-run-session quickshell -p ./preview.qml
```

The preview uses real components. Its clock label is illustrative. A private bus
keeps its notification server separate from the existing desktop. Running apps and
tray integration are exercised by the actual shell, not this component preview.

To use the included floating-first Hyprland configuration from a TTY:

```sh
Hyprland -c "$HOME/Projects/zephyrus-shell/hyprland/hyprland.lua"
```

The existing `~/.config/hypr/hyprland.lua` is not modified. The new configuration
starts the shell and the installed Hyprland polkit agent automatically. For a normal
login-manager session, back up your current configuration and source the absolute
path to this project's `hyprland/hyprland.lua` with Lua's `dofile`.

## What works

- Three separate clickable pill regions; the empty top area passes pointer input through.
- Left and right overlay drawers; opening a panel closes the previous one. Escape closes it.
- One drawer on one monitor at a time, with pills on every monitor.
- Applications opens a desktop overlay below the pills, with favorites, a searchable app grid and category filters.
  Favorites is the default tab when any saved favorites are installed; otherwise
  All applications opens. Star buttons add/remove apps. Search from Favorites
  searches all apps. Selections persist in `$XDG_CONFIG_HOME/zephyrus-shell/applications.ini`
  (default `~/.config/zephyrus-shell/applications.ini`). This is a separate list from
  KDE launcher favorites. Stars appear on hover or keyboard focus; saved favorites
  always display a filled star.
- Every Desktop module shares the same overlay; Escape or clicking Desktop closes it.
- Running-window activation and tray activation/context menus beside the left pill.
- Clock, navigable calendar, notifications, actions, dismissal, toast, and do-not-disturb.
- Separate named audio output and microphone selection, level and mute controls.
- GNOME-style Wi-Fi/Bluetooth split tiles, with device selection inside Control room.
- Inline Wi-Fi passwords and Bluetooth pairing confirmation/PIN entry.
- Laptop brightness through brightnessctl or logind, power profiles, battery status and charge limit.
- Confirmed session actions; floating windows by default, optional tiling per window.
- A static, procedurally drawn background. No wallpaper download or resident animation.

The Settings drawer has saved profiles, expandable audio/display/battery controls,
CPU/GPU/RAM cards, and Cardwire GPU switching. Hardware controls are enabled only
when their backend is available. See [settings configuration](docs/settings.md)
for profiles, battery automation, display aliases, DDC brightness and limitations.
Networking, Bluetooth, audio and battery automation use service events. Hardware
readings refresh on opening, actions, battery changes or manual refresh.

## Dependencies and boundaries

Required: `quickshell`, `hyprland`, Qt Quick Controls, Python 3, PipeWire/WirePlumber,
NetworkManager, UPower, and a polkit agent. Your existing Kitty and Dolphin bindings
are retained. Audio route metadata uses `pactl` (Arch: `libpulse`). Bluetooth
pairing uses `python-dbus` and `python-gobject`, already available on this machine.
No external network or Bluetooth settings application is launched by the drawer.

No screen locker is currently installed on this machine. This shell does **not**
provide a lock screen; suspend is not a substitute for locking. Set up `hyprlock`
and `hypridle` before relying on the session for unattended use. Weather, external
calendars, tasks, persistent notification history, and media-library plugins are
future modules, not placeholder controls. Current notifications are retained only
for the shell's lifetime, capped at 100. Wi-Fi supports saved profiles, open networks,
and WPA/WPA2/WPA3 personal passwords. New enterprise/certificate profiles and hidden
network creation are not yet implemented. Bluetooth discovery is user-triggered
and stops after 30 seconds or when leaving its page. Pairing prompts require an
explicit answer; the helper never becomes the system's default Bluetooth agent.

## Daily shortcuts

| Shortcut | Action |
| --- | --- |
| Super + Space | Left drawer |
| Super + C | Calendar and notifications |
| Super + Comma | Controls |
| Escape (drawer focused) / Super + Escape | Close panel |
| Super + Enter / E | Kitty / Dolphin |
| Super + left / right drag | Move / resize a window |
| Super + V | Toggle floating for the current window |
| Super + Q | Close current window |
| Super + 1–9 | Workspace |
| Super + Shift + 1–9 | Move window to workspace |

## Extend and customize

Read [docs/plugins.md](docs/plugins.md) to add a space. The shell does not contain
an Apps/Movies/Music/etc. enumeration. Only Desktop is built in.

Read [docs/architecture.md](docs/architecture.md) for the file map. Colors, spacing,
and typography live in `core/Theme.qml`; individual machine sections live in
`settings/`; window behavior is in `hyprland/windows.lua`.

See [audio naming](docs/audio-names.md) for per-monitor/per-device JSON rules, and
[attention design](docs/attention-design.md) for the planned Nextcloud task model.

## Check changes

```sh
python3 -m unittest discover -s tests -v
node --test tests/audio-names.test.cjs
Hyprland --verify-config -c "$PWD/hyprland/hyprland.lua"
bash scripts/check-preview.sh
bash scripts/check-apps.sh
# Briefly opens the actual panels on your current Wayland desktop:
bash scripts/check-wayland.sh
```

The preview check opens every panel and saves images under `tests/artifacts/`.
The offscreen backend emits expected window-mask warnings. Actual layer-shell
placement, focus, and multi-monitor behavior also need testing in Hyprland.

References: [Quickshell documentation](https://quickshell.org/docs/v0.3.1/),
[Hyprland configuration](https://wiki.hypr.land/),
[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell).

Interface icons use bundled Lucide SVGs. See [contributor conventions](AGENTS.md)
and [plugin documentation](docs/plugins.md); native app icons retain their artwork.
