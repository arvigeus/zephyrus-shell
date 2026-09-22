# Settings drawer

The profile selector applies a saved configuration. Subsequent edits update that
profile automatically. Defaults live in `config/profiles.json`; after the first
edit, the working copy lives in `$XDG_STATE_HOME/drawer-shell/profiles.json`
(default `~/.local/state/drawer-shell/profiles.json`). Edit that copy to add or
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
RAM reports actual usage with no invented performance-mode selector.
Lucide icons are vendored with their license in `assets/lucide/`.
