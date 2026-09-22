# Verification on this machine

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
