# Settings drawer

The profile selector applies a saved configuration. Subsequent edits update that
profile automatically. Defaults live in `config/profiles.json`; after the first
edit, the working copy lives in `$XDG_STATE_HOME/zephyrus-shell/profiles.json`
(default `~/.local/state/zephyrus-shell/profiles.json`). Edit that copy to add or
rename profiles, then restart the shell. Only keys included in a profile apply:
`wifi` and `bluetooth` (booleans), `profile` (power-saver/balanced/performance),
`brightness` (5–100), `chargeLimit` (50–100), and `gpu` (a supported Cardwire mode).
Audio routing, volume and display topology are independent of profiles.

Battery expansion assigns profiles to plugged-in, discharging and low-battery
states. “Keep current” disables that trigger. Low battery defaults to 20%.
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

The Wi-Fi header uses the connected network's signal and lock icon. The right
pill shows Wi-Fi when enabled, Bluetooth when enabled, speaker volume, an active
microphone, battery, CPU power profile, and GPU mode as icons with individual
tooltips. The battery tooltip uses live UPower charge, time, and power readings.
Speaker icons distinguish mute, zero, low, and high volume. Brightness and
battery icons also change with their levels; charging takes precedence over the
battery level icon.

Battery fill indicates current charge. The vertical handle sets the charge limit
between 50% and 100%; hover or drag shows its value, and arrow keys also work.
Systems without a writable threshold can request polkit authorization via
`pkexec tee` for the discovered battery threshold file. Permission or firmware
errors appear in the drawer. Battery time and power use existing sysfs readings;
hardware readings refresh on opening, actions, battery events or manual refresh.

## Displays

Under Hyprland, expanding brightness lists connected displays. The icon enables
or disables a display; its name selects the shell's primary brightness target.
The last enabled display cannot be disabled. Hyprland does not have a global
primary-monitor concept. This preference is stored in XDG state. Resolution,
refresh rate, and scale are available in Display settings and apply to the current
Hyprland session. Enabling a disabled display restores its preferred mode at
automatic position and scale 1.

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

GPU modes are discovered with `cardwire get` and applied with `cardwire set MODE`.
See [Cardwire](https://github.com/OpenGamingCollective/cardwire) for installation
and daemon setup. Laptop modes are Integrated, Hybrid and Smart; desktop modes
may differ. The shell shows only modes reported by the installed daemon. It does
not implement a dedicated-only mode or change Cardwire's independent automation
settings; configure those to avoid conflicting with shell battery profiles.

CPU choices use power-profiles-daemon's power profiles, not raw CPU governors.
Detail pages display kernel temperature/fan sensors, load average and boost state.
Fan curves, boost changes and TDP controls remain in the existing ASUS setup.
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

The brush button at the bottom of the System card removes generated image thumbnails
from `$XDG_CACHE_HOME/thumbnails` (normally `~/.cache/thumbnails`). Hold it for
1.3 seconds, as with the Movies delete control. Its tooltip describes the
action. It refuses a symlink target; image previews regenerate when needed.
The cached home breakdown is invalidated after a successful cleanup and rescanned
when System details are next opened. Projects offers
separate, selective development cache cleanup.
The upload icon beside the brush is reserved for system updates and currently
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
mode lasts until turned off or the shell exits.
