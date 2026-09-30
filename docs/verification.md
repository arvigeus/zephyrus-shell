# Verification on this machine

Architecture review, 2026-09-30: 262 Python tests and 27 portable QML tests passed,
as did both Node suites, Hyprland configuration parsing, all eight README smoke
scripts, and the offline performance budgets. The retained check now includes six
state-transition cases against the production ShellState singleton. The preview
produced twelve captures; Applications and Attention captures were inspected.
The current Wayland desktop harness passed, but live Hyprland input, physical
multi-monitor/hotplug, player playback, and hardware/GPU/power behavior were not
validated in this review. See [architecture review](architecture-review.md).

Weather/hardware follow-up, 2026-09-30: the CPU/GPU source was read directly from
this machine's hwmon sensors; the card selector now prefers package/edge readings.
The full Python suite (275 tests), portable QML suite (32 tests), both Node suites,
preview, retained lifecycle, current Wayland panel smoke and performance budgets
passed. The weather layout was captured and inspected using the production panel
and configured Open-Meteo data. This verifies reads and rendering, not sensor
calibration, thermal behavior under controlled load or live Hyprland input.

## Earlier baseline

Environment: Arch Linux, Quickshell 0.3.1, Qt 6.11.2, Hyprland 0.56.2,
ROG Zephyrus G14 GA402RK. Existing desktop session: KDE Wayland.

- Twelve Python tests pass: audio rule isolation, guarded profile changes,
  pairing confirmation/PIN validation, metadata-only discovery, ordering and disabling,
  invalid-plugin isolation, removal, action allowlist/argument handling,
  and refusing Hyprland logout outside a Hyprland session.
- `Hyprland --verify-config` reports `config ok` for the standalone Lua configuration.
- Three JavaScript assertions test audio route naming, monitor replacement and unplugging.
- Component preview renders seven states to `tests/artifacts/preview-0.png`
  through `preview-6.png`: closed, library, applications, controls, attention,
  inline Wi-Fi and inline Bluetooth.
- The actual Wayland integration harness opens library, Apps, controls, and attention,
  receives a notification over a private D-Bus session, dismisses it, and checks
  state cleanup before exiting.
- Visual inspection verified live battery, network, audio and brightness information.

The private test bus can emit desktop-portal activation warnings; offscreen Qt emits
a window-mask warning. Neither indicates a production shell QML loading failure.

Not exercised: real power/session actions, changing network or audio settings,
actual Bluetooth pairing (agent responses are unit tested), a real application launch, physical multi-monitor hotplug,
or mouse/keyboard behavior inside a live Hyprland session. Those actions are not
claimed as tested merely because the controls rendered. No existing desktop
configuration was replaced and no system packages were installed.

Application lifecycle and favorites: `bash scripts/check-apps.sh` uses an isolated
configuration directory and two shell processes to verify the load gate, default
Favorites view, add/remove behavior, persistence across restart, and destruction.
