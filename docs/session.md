# Development Hyprland session

The ordinary **Hyprland** login-manager entry uses `start-hyprland` and the
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
join horizontal columns at half the monitor's usable width; a single column
fills the work area. Focusing a column brings it into view. Dialogs keep native
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

## Session ownership

`environment.lua` sets Wayland/Hyprland identity. `session.lua` starts one owned
Python supervisor. It imports the actual display and desktop environment into
the user manager and D-Bus activation before starting services. It starts
PipeWire/WirePlumber, the installed Hyprland polkit agent, and restarts portals
with the Hyprland/GTK routing file. GTK supplies file choosing; Hyprland supplies
screen sharing and screenshots. Dolphin may use its own Qt chooser; portal
consumers use the routing above.

The supervisor runs Quickshell and hypridle, restarts a failed child after three
seconds, and watches the compositor's event socket. Normal logout and compositor
failure terminate the owned process groups, stop portals and the polkit agent
if this session started it, and clear display/desktop variables in the user
manager. Audio services are shared user services and remain available.
This setup assumes one graphical desktop session for this Unix user at a time.
The UWSM-managed login entry is not the validated development path.

Quickshell owns `org.freedesktop.Notifications`; no dunst, mako or KDE notification
server is autostarted. Preview tests use private buses. Nothing requires Plasma
to be running; Kitty and Dolphin are applications, not session providers.
NetworkManager, Bluetooth and power profiles need their services enabled.
Brightness/DDC helpers, hyprlock and hypridle are installed by default;
unavailable hardware disables the corresponding controls. GPU switching stays
optional.

Session output is in `$XDG_STATE_HOME/zephyrus-shell/session.log` (normally
`~/.local/state/zephyrus-shell/session.log`), with the preceding run in
`session.previous.log`. Also inspect `journalctl --user -b` for portal/polkit
failures and `hyprctl configerrors` for compositor configuration.

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
  supervisor or stale window-control configuration.

References: [native scrolling layout](https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/),
[hypridle lock/suspend handling](https://wiki.hypr.land/Hypr-Ecosystem/hypridle/),
[Hyprland portals](https://wiki.hypr.land/Hypr-Ecosystem/xdg-desktop-portal-hyprland/).
