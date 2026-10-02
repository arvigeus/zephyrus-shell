# Development Hyprland session

The **Hyprland (uwsm-managed)** login-manager entry uses UWSM and the
generated `~/.config/hypr/hyprland.lua` shim. The installed entry already exists
on this machine. Use it for the first live test; log out of Plasma first.
The repository remains the source of configuration and QML edits.

## Setup and teardown

```sh
scripts/setup-system.sh
python3 scripts/setup-session.py install
python3 scripts/migrate-nextcloud.py
```

The development installer generates a Lua `dofile` shim using the checkout's
absolute path and links the static hypridle, hyprlock and Hyprland portal files.
Lua modules resolve relative to the repository entry point, and `dofile` reloads
them on `hyprctl reload`. No committed file contains a personal checkout path.
Paths honor `XDG_CONFIG_HOME` and `XDG_STATE_HOME`.

Existing files/symlinks are preserved beside their replacements as
`*.before-zephyrus`; the inventory is in
`$XDG_STATE_HOME/zephyrus-shell/dev-session.json`. Repeating installation with
the same checkout is safe. Move the checkout only after teardown/reinstallation.

```sh
python3 scripts/setup-session.py teardown
```

Teardown restores the previous files and removes only unchanged installed files.
It refuses to delete files you edited or proceed if a backup is missing. Preserve
your edit and restore the generated file/link before retrying. It does not remove
packages, migrated Nextcloud configuration or credentials. Log out of the
Zephyrus session before teardown. The installer does not replace the system
login-manager desktop entry or your old `hyprland.conf`.

## Native scrolling desktop

`windows.lua` selects Hyprland's built-in scrolling layout. New ordinary windows
join horizontal columns at half the monitor's usable width. Explicit widths also
apply to a single column; it no longer automatically fills the work area. Focusing a column brings it into view. Dialogs keep native
floating behavior, and Super+V can toggle floating for an individual window.
No plugin or custom window controls are required. The earlier hyprbars prototype
has been disabled (`hyprpm disable hyprbars`); its cached installation may remain,
but the session does not load it. Application-owned title bars remain owned by
the application.

Super+Left/Right focuses the previous/next column, including leaving a maximized
column. Super+mouse wheel scrolls the view one column. Alt+F4 or Super+Q closes
the current window. Super+M toggles native maximized state within the desktop
work area. Super+right-drag or grabbing a border resizes; the border has an 8 px
extra grab area. Super+left-drag moves a floating window. Minimize is deferred;
scrolling away and activating a running-app button keeps every window reachable.

The pill bar reserves 46 logical pixels for desktop windows on each monitor.
Modules keep their own full-screen background and content below the pills.
Window rounding is 8 px, compositor transitions are 110–160 ms, and drawer motion
is 140 ms. These values are separate from monitor scaling.

`monitors.lua` supplies a generic preferred-mode/automatic-scale fallback, then
loads optional `$XDG_CONFIG_HOME/zephyrus-shell/monitors.lua`. This personal file
is outside the checkout and setup/teardown does not overwrite it. This laptop's
current preference is:

```lua
hl.monitor({ output = "eDP-2", mode = "preferred", position = "auto", scale = 1.25 })
```

Choose an output name from `hyprctl monitors`, edit that personal file and run
`hyprctl reload`. Other outputs retain the automatic fallback. Scaling affects
both applications and the shell; no per-widget scaling workaround is needed.

The windows list groups by monitor and workspace, then follows scrolling columns
from left to right. New windows and moved columns update the list; floating
windows follow the columns in their original order. Unknown compositor metadata
keeps a window reachable until its geometry arrives.

Drag a running-window button horizontally and release beside another button to
reorder scrolling columns. The accent line marks the insertion position; holding
near an edge scrolls a long list. Releasing outside the list cancels. Drops work
between tiled windows on the same monitor and workspace. Floating windows remain
clickable but cannot be reordered this way. Hyprland moves the entire column,
including stacked windows when a column contains more than one window.

Running-app buttons resolve a window's app ID through Quickshell's desktop-entry
lookup (including case/WM-class matching) and use the entry's configured icon.
Activating a running-app button focuses its window without moving the pointer;
automatic focus cursor warps are disabled. Unknown icons stay blank. Desktop
entries may use theme names or absolute image paths.

Clicking a window button reveals the desktop and focuses that app. Hovering its
bar button only shows the title tooltip. Pointer focus follows the actual window
under the mouse, so an inactive window can receive scroll input while keyboard
focus stays on the active window; clicking changes keyboard focus.
Modules with active retention requests continue in the
background; other modules close. Right-click offers Close, Mute/Unmute
when PipeWire identifies an audio stream, 25%/50%/75%/Full width, Float/Tile,
and a destination Monitor when another output is active. Scrolling sizes affect
the selected column; floating sizes use the display's usable area. Audio mute
can affect multiple windows sharing the same application process or audio ID.
Tray buttons forward primary activation on left-click, the application's menu
on right-click, secondary activation on middle-click, and wheel events.
Menu-only items open their menu on left-click. Tray actions reveal the desktop
before handing input to the application. Native tray menus require the entry
point's `UseQApplication` pragma; changes to this mode require restarting the
shell. Missing tray theme icons fall back to the installed application's icon.
Window and tray hover tooltips have no input region, so context menus remain
available while the tooltip is visible.

Tap either Win key to toggle Spaces on the focused monitor. Super+Space also
toggles it. Typing opens a centered local search of installed applications and
module names; Up/Down selects a result, Enter launches or opens it, and Escape
closes the drawer. Searches do not load modules or start provider workers.
The center pill separates date, time, weather and attention indicators with dots.
Tasks due today, events spanning today and pending notifications have separate
Lucide icons. A shared, cached calendar snapshot refreshes every 15 minutes even
when Attention is closed; browsing another month does not change today's icons.

Print selects a screenshot area, Super+Print selects a window, and Shift+Print
captures the active output. Captures go to XDG Pictures/Screenshots and the
clipboard. The Settings drawer also exposes Screenshot and Clipboard actions;
Super+Shift+V opens the native searchable Clipboard space. The dotfiles desktop
package supplies Hyprshot, cliphist, wl-clipboard and session-owned history
watchers; development checkouts show setup guidance when helpers are missing.

Hyprland transfers workspaces and windows when an output disappears or is
disabled. The shell checks topology changes and re-enables a connected internal
panel if no usable output remains, including waking its DPMS state. Working
external-only setups stay external-only. Module ownership follows a surviving
screen without recreating retained workers or players.

## Session ownership

Choose **Hyprland (uwsm-managed)** at login. UWSM imports the compositor
variables, starts `graphical-session.target`, handles XDG autostart, and cleans
up services and environment on logout or compositor failure. `session.lua`
calls `uwsm finalize`; there is no Python session supervisor.

Setup installs a standard `zephyrus-shell.service` and enables the distribution's
`hypridle.service` and `hyprpolkitagent.service`. All are bound to the graphical
session; Hyprland environment conditions prevent them starting under Plasma.
Systemd restarts a failed shell. PipeWire uses its packaged socket activation;
portals use their packaged D-Bus activation and the Hyprland/GTK routing file.
GTK provides file choosing, and Hyprland screen sharing and screenshots.

After setup or teardown run `systemctl --user daemon-reload`. For migration from
the old setup, teardown and reinstall the development shim, then log out and
choose the UWSM entry. Do not start a second shell in the current session.

Quickshell owns notifications. Power controls call an already active `asusd`
on ASUS machines, or an already active PPD elsewhere. Setup does not install or
enable a second power policy daemon. ASUS firmware owns AC/battery profile
transitions unless you explicitly configure Zephyrus automatic assignments.
Performance is a firmware profile, not a promise of a safe temperature ceiling.
GPU selection uses switcheroo-control per application; ROG Control Center owns
supported firmware mode changes. Settings skips suspended GPU sensors to avoid
waking a dGPU for monitoring.

Read logs with `journalctl --user -b -u zephyrus-shell -u hypridle` and inspect
`hyprctl configerrors`. Test a login/logout cycle before relying on cleanup.

## Lock and idle

Super+L calls `loginctl lock-session`, handled by hypridle's duplicate-safe
hyprlock command. hyprlock uses system PAM authentication, your Pictures wallpaper and a small
password field on each monitor. Pictures updates an atomic `lock-wallpaper`
symlink in the Zephyrus config directory each time you set a wallpaper, including
when targeting another desktop. The session supplies its XDG-aware path to
hyprlock. Before a wallpaper is selected, the solid Zephyrus background is used.

Idle locks after five minutes, blanks displays after six, and suspends after
thirty. Resume turns displays on. Before any suspend, hypridle requests locking;
`inhibit_sleep = 3` holds the logind delay inhibitor until the compositor reports
a session lock. This also covers suspend from Settings and lid/logind events.
The idle suspend command explicitly checks systemd inhibitors. **Stay awake**
blocks automatic suspend but allows locking and display blanking. **Keep screen
on** blocks idle dimming/blanking and suspend; both modes wake blanked outputs
when enabled. Key presses and pointer movement also enable DPMS. The Lua DPMS
commands use `enable`/`disable`, including the idle and resume hooks.

Settings Sleep, Log out, Restart, Power off and scheduled shutdown require a
two-second hold on the action itself. Releasing early or closing the drawer
cancels the hold. Manual Sleep clears the shell's own awake inhibitor first.
These are initial idle timings to tune later.

## Live test checklist

- Log out of Plasma, select **Hyprland**, and verify background, the shell pills,
  tray, notification ownership, audio and polkit prompts without launching KDE.
- Open several apps: ordinary windows form scrolling columns; Super+Left/Right focuses
  adjacent columns and Super+mouse wheel scrolls. Borders or Super+right-drag
  resize. Super+V toggles floating; Super+left-drag moves floating windows.
- Alt+F4/Super+Q closes and Super+M maximizes/restores below the pills. Move
  between maximized and ordinary columns. Verify running-app icons and activate
  an off-screen window from its button. Minimize is intentionally unavailable.
- Drag running-window buttons left and right, including at the list's scroll
  edges; verify the insertion line, column order and cancellation outside the list.
- Launch from Applications; open both drawers and Attention; select modules and
  Desktop; press Escape. Activate multiple running windows from their app buttons.
- Super+L, authenticate, then test five/six-minute idle lock/blanking, inhibitors,
  Settings Sleep, and lid/suspend resume. Confirm the lock is present on resume.
- In a portal-using app, open a file picker and share a screen/window. Check
  permission prompts and cancellation, not only backend service state.
- Open Calendar, navigate months and task lists, refresh, create/edit a disposable
  event/task and complete it; confirm changes in Nextcloud. Music/Files have no
  cloud operations yet.
- With another monitor, test pills/drawers, moving/resizing/maximizing windows,
  mixed scales, hotplug and locking on all outputs.
- Log out and log back in; check that there is one shell/idle agent and no orphan
  shell services or stale window-control configuration.

References: [native scrolling layout](https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/),
[hypridle lock/suspend handling](https://wiki.hypr.land/Hypr-Ecosystem/hypridle/),
[Hyprland portals](https://wiki.hypr.land/Hypr-Ecosystem/xdg-desktop-portal-hyprland/).
