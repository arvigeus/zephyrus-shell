# Settings drawer

Desktop colors, fonts and light/dark appearance share the configuration described
in [desktop appearance](theme.md). The source is watched automatically; an
appearance button can use the same source in a later UI update.

The profile selector applies a saved configuration. Subsequent edits update that
profile automatically. Defaults live in `config/profiles.json`; after the first
edit, the working copy lives in `$XDG_STATE_HOME/zephyrus-shell/profiles.json`
(default `~/.local/state/zephyrus-shell/profiles.json`). Edit that copy to add or
rename profiles, then restart the shell. Only keys included in a profile apply:
`wifi` and `bluetooth` (booleans), `profile` (power-saver/balanced/performance),
`brightness` (5–100), and `chargeLimit` (50–100 on supported ASUS hardware).
Old saved `gpu` values report an error; use standard application GPU selection.
A failed hardware action leaves the active profile unchanged and reports the error.
Audio routing, volume and display topology are independent of profiles.

Battery expansion loads a read-only information card for each laptop battery:
charge and status, estimated time until full (or the charge limit) or empty, health relative to its
original capacity, power draw or charging power, charge cycles, and temperature
when available. Capacity uses Wh or mAh according to the driver's readings;
missing readings are marked unavailable. Pack manufacturer, model and chemistry
appear below the readings. Details are read asynchronously from sysfs only while
expanded, refresh with hardware updates and every five seconds while visible,
and are released when collapsed. Battery power measures power flowing into or
out of the battery, not total system consumption from the adapter. A plugged-in
battery at its charge limit can show `0.0 W · Idle` while the laptop uses adapter
power. Hover this row for the reading's meaning in the current battery state.
Adapter online status is read separately from battery status: a pack may still
report discharging while plugged in. That combination shows “Plugged in · Battery
discharging” and hides the battery-only runtime estimate. UPower power-source
events also refresh the hardware snapshot on plugging or unplugging.

Automatic profile assignments remain configurable in the state file's `battery`
object (`default`, `discharging`, and `low` map to profile names; an empty string
disables a trigger). Low battery defaults to 20%.
Transitions use UPower events even with the drawer closed; they do not repeatedly
override manual selection within the same state. An assigned profile also applies
at shell startup. Defaults have no automatic assignments. If one setting fails,
other profile settings still apply and the drawer displays the error.

Microphone icon toggles mute on **all currently exposed hardware microphones**;
this is software mute, not hardware disconnection. Expansion chooses the default
audio device. Per-device role aliases are described in [audio-names.md](audio-names.md).

Wi-Fi and Bluetooth expand inside the drawer. Their icons toggle each radio;
expanding shows nearby networks or devices in a height-limited list. Bluetooth
uses BlueZ's device type icon when available, mapped to bundled Lucide artwork.
Network and Bluetooth connection controls sit on their device rows. A Wi-Fi
network's icon or name connects or disconnects it; protected networks use a lock icon,
while open and OWE networks use the standard Wi-Fi icon. One, two, or three Wi-Fi
arcs show low (under 40%), high (40–74%), or full (75% and above) signal. Hover
over a network to see its exact signal percentage, status, and security type.
Saved and open networks connect immediately. An unknown protected network shows
one password field with connect and cancel icons on the same row. The Wi-Fi
header and network icon show `wifi-sync` while NetworkManager
changes state. Disconnecting a Wi-Fi device suppresses automatic reconnection
until a connection is explicitly requested. Bluetooth shows a paired check icon;
forgetting a device requires a second click on its trash button within five seconds.

Cloudflare WARP appears at the top of the wireless network list with a monochrome
logo. Its name and logo are muted while disconnected; click either to connect or
disconnect. WARP also works over Ethernet. Errors remain inline. A Cloudflare logo
appears in the right status pill only while the tunnel is connected.

The shell owns consumer registration, LAN exclusions, scoped authorization and
the on-demand daemon lifetime. Install the optional client and run
`sudo zephyrus-shell-warp setup --user USERNAME` once; see [WARP setup](warp.md).
First activation accepts Cloudflare's terms and registers if needed. Existing
registration is retained. Organization enrollment and WARP+ licensing are
advanced CLI operations.

One shell-wide observer subscribes to systemd state changes. It starts
`warp-cli --listen status` only while the daemon is active and releases it when
the daemon stops. Settings and every output share the same state, including
connection events arriving after a connect command completes. There is no
periodic status polling. When WARP is off, only the passive D-Bus subscriber
remains; no WARP daemon or CLI listener runs.

The Wi-Fi header uses the connected network's signal and lock icon. The right
pill shows Wi-Fi when enabled, Bluetooth when enabled, speaker volume, an active
microphone, battery, CPU power profile, and GPU mode as icons with individual
tooltips. The battery tooltip uses live UPower charge, time, and power readings.
Speaker icons distinguish mute, zero, low, and high volume. Brightness and
battery icons also change with their levels; charging takes precedence over the
battery level icon. Active Keep awake and Keep screen on modes also appear in
the right pill with their coffee and eye icons.

Battery fill indicates current charge. The vertical handle sets the charge limit
between 50% and 100%; hover or drag shows its value, and arrow keys also work.
Systems without a writable threshold can request polkit authorization via
`pkexec tee` for the discovered battery threshold file. Permission or firmware
errors appear in the drawer. Battery time and power use existing sysfs readings;
hardware readings refresh on opening, actions, battery events or manual refresh.
CPU/GPU temperatures come from
`/sys/class/hwmon/*/temp*_input` in millidegrees Celsius and are rounded for display;
they do not poll while the drawer stays open. The combined hardware cards prefer
CPU package/control and GPU edge sensors and show the hottest matching device,
rather than whichever sensor happens to enumerate first. Detailed sensor readings
remain available on the hardware pages. Hover the card temperature for its sensor
label and sampling rule.

## Displays

Under Hyprland, expanding brightness lists connected displays. The icon enables
or disables a display; enabled displays use the monitor icon and disabled
displays use monitor-off. Its name selects the shell's primary brightness target.
The last enabled display cannot be disabled. Hyprland does not have a global
primary-monitor concept. This preference is stored in XDG state. Resolution,
refresh rate, scale, order, and enabled/disabled choices are saved in
`$XDG_CONFIG_HOME/zephyrus-shell/display-profiles.json` and restored on reload,
login, hotplug and wake after the connected outputs settle. Each connected set
has its own layout: laptop-only, home monitor and another docked monitor can keep
different enabled displays, positions and scales. Monitors are identified by
make/model/serial, falling back to description or connector when unavailable;
changing a USB-C port does not lose a uniquely identified monitor's settings.
Identical displays without unique serial numbers require their original connectors.

Changes in Display settings save the entire connected setup automatically.
**Remember current layout** also captures arrangements made with other tools,
including vertical offsets and rotation. New setups reuse known monitors' settings
with automatic placement; new physical monitors start with preferred mode and
automatic scale rather than inheriting a previous monitor's connector settings.
Existing `display-settings.lua` preferences migrate for the connected displays on
first use. That file subsequently contains only a diagnostic snapshot; the shell
owns profile selection rather than applying stale connector rules on reload.

Enabling a disabled display restores its saved geometry. Disconnecting the last
external display re-enables the internal panel if necessary, using its saved scale
and mode at the origin. This laptop-only layout does not overwrite the docked
layout's disabled-panel preference. At least one attached output always remains
enabled. Hyprland transfers the removed display's workspaces and apps to an enabled
output; profiles restore display geometry, not individual application positions.

`config/displays.json` maps connector names to aliases and optional DDC buses:

```json
{
  "eDP-1": {"label": "Internal screen"},
  "DP-1": {"label": "Dell", "ddcBus": 6}
}
```

Find the correct bus with `ddcutil detect`. External brightness requires ddcutil,
a DDC-capable display, and I²C access. Unsupported external displays show a disabled
brightness slider. Built-in brightness uses brightnessctl or logind.

## Hardware

GPU selection belongs to switcheroo-control and the application's desktop entry.
Applications exposes a GPU picker on hover/focus and in its right-click menu.
Each explicit launch queries the active service again and uses its discovered
device identity for that process only. On Mesa, Vulkan sees only the selected
device. Existing application instances must be closed first; a single-instance
app may otherwise forward the request to its existing process. Launching Steam
with a GPU choice affects newly started games in that Steam process, not an
already running Steam client. No session-wide environment is changed.
Supported firmware GPU mode changes are available in ROG Control Center and
may require a reboot. The shell does not install a GPU-blocking daemon or force
one GPU globally. It skips sensors on suspended GPUs so monitoring does not
wake them.

CPU choices call the already active `asusd` on ASUS hardware: Power saver maps
to Quiet, Balanced to Balanced, and Performance to Performance. Elsewhere an
already active power-profiles-daemon is supported. The shell does not activate
a second profile owner. ASUS owns AC/battery transitions unless explicit shell
automatic assignments are configured. Performance does not impose a thermal
ceiling; fan/PPT experiments belong in the firmware tools and need measurement.
The CPU detail page includes a boost toggle when the kernel exposes the standard
global CPUFreq switch. It uses a root-owned, one-shot helper with polkit
administrator authentication, not a tuning daemon or passwordless sudo. Boost
changes last for the current boot and are not saved in shell profiles. Refresh
readings after firmware/profile changes to confirm the actual state. Disabling
boost may reduce heat and CPU performance; it does not impose a temperature
ceiling or limit dGPU power. Fan curves and PPT controls remain in ASUS tooling.
CPU, GPU, and System cards share one row. The CPU and GPU cards show the device
name, temperature, usage, and available mode buttons. System shows memory and
root filesystem usage. The colored bars mark 0–60% green, 60–85% yellow, and
85–100% red. GPU utilization and temperature show unavailable when the driver
does not expose readings. Opening System scans top-level home directories
asynchronously and groups folders smaller than 1% of home usage (with a 64 MiB
minimum) and home-level files under “Other folders & files”. There is no row
count limit. Symlinks and other mounted filesystems are not traversed. A scan
warning means paths were inaccessible or changed during the scan, so the
reported sizes may be low; hovering the warning shows the first errors.
CPU/GPU readings are sampled on drawer opening and manual refresh, rather than
polled continuously. The home breakdown is cached after a successful scan.
RAM reports actual usage with no invented performance-mode selector.
Lucide icons are vendored with their license in `assets/lucide/`.

The System card's second action switches between the shared dark and light
themes, saving the choice in `theme.json`. Cleaning comes first and Update third.

The brush button at the bottom of the System card removes generated image thumbnails
from `$XDG_CACHE_HOME/thumbnails` (normally `~/.cache/thumbnails`). Hold it for
1.3 seconds, as with the Movies delete control. Its tooltip describes the
action. It refuses a symlink target; image previews regenerate when needed.
The cached home breakdown is invalidated after a successful cleanup and rescanned
when System details are next opened. Projects offers
separate, selective development cache cleanup.
The upload icon after the theme toggle is reserved for system updates and currently
has no action.

## Shutdown

The power button still shuts down immediately after confirmation. Its adjacent
arrow offers delays of 15, 30, 60, 90, 120, 180, 240, or 300 minutes. These
use systemd's scheduled poweroff and can be canceled from the same menu. The
menu shows a cancellation action only when systemd reports a scheduled shutdown.

The Sleep button opens the existing suspend confirmation. Its adjacent arrow
offers Keep awake (coffee) to block sleep while allowing dimming and blanking,
and Keep screen on (eye) to block both sleep and idle screen actions. The menu
uses tooltips for explanations. While either mode is active, its icon replaces
the moon; clicking it turns the mode off. Manual Sleep is available in the menu
and releases the mode before suspending. The modes use systemd sleep inhibitors;
Keep screen on also uses a systemd idle inhibitor and, on Wayland compositors
supporting the idle-inhibit protocol, the shell's panel window. The selected
mode lasts until turned off, the lid closes, or the shell exits. Closing the lid
returns to Desktop and locks unless the session lock pause is active; opening
it wakes only enabled outputs after restoring saved display preferences.

The same Sleep dropdown offers **Disable locking**, using the `lock-open` icon.
It pauses automatic locking and idle suspend for this Hyprland session while
allowing display blanking, including returning from manual or lid sleep without
a new password prompt. The Sleep button shows `lock-open` while paused. Select
**Restore locking** to end the pause, or log out; the next login restores normal
locking. This is independent of the two awake modes. Manual Super+L still locks.
