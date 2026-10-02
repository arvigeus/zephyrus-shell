# System setup

Run `scripts/setup-system.sh` once on Arch Linux after cloning the project and
before the first launch. It installs the project's required runtime packages using
`pacman`; it does not build project files or change the shell's per-launch command.

```sh
scripts/setup-system.sh
```

The installer asks `pacman` to confirm package changes. Brightness, DDC, UWSM, hyprlock and hypridle are installed by default. The old
`--with-optional-controls` flag remains accepted. GPU selection uses switcheroo-control; firmware GPU controls belong to ASUS tooling.

Setup loads `i2c-dev` for the current boot, records it for future boots, and adds
your user to the `i2c` group using Arch's packaged device rules. Log out and back
in after setup for group membership to apply. External monitors must support
DDC/CI and have it enabled in their own menus. Settings matches the DRM connector
to its I2C adapter automatically, including DisplayPort AUX/USB-C adapters; a bus
can also be selected in Display settings. No root access is needed at runtime.

Setup also installs the narrow CPU boost helper and its polkit action. Existing
checkouts can install only this control with `sudo bash scripts/install-controls.sh`.
It authorizes writes of 0 or 1 to the kernel's CPUFreq boost switch; it cannot
write arbitrary sysfs paths. The UI requests administrator authentication when
needed. An authentication agent must run in the desktop session (Hyprland uses
hyprpolkitagent; Plasma supplies its own). Applications GPU choices require an
active switcheroo-control service; on a hybrid GPU system enable it with
`sudo systemctl enable --now switcheroo-control.service`.

Useful read-only checks:

```sh
ddcutil detect --brief
ddcutil --bus <number-from-detect> getvcp 10 --terse
systemd-inhibit --list
```

Display mode, scale and left-to-right order are saved in
`$XDG_CONFIG_HOME/zephyrus-shell/display-settings.lua`. Personal bus overrides live
in `zephyrus-shell/displays.json`. Turning off an output removes it from the
layout for the current session; at least one output remains enabled. Monitor
orientation is preserved when changing scale or order.

NetworkManager and Bluetooth need their services enabled. Power controls use
the existing active asusd or PPD owner; do not run both with profile management
enabled. The script leaves service state unchanged by
default. To enable and start them during setup, use:

```sh
scripts/setup-system.sh --enable-services
```

Or enable them later with:

```sh
sudo systemctl enable --now NetworkManager.service bluetooth.service
```

The script supports Arch Linux only. On another distribution,
install the packages listed in `scripts/setup-system.sh` using that distribution's
package manager.

For a complete login session choose **Hyprland (uwsm-managed)**. After setup, start the shell from the repository root inside Hyprland:

```sh
quickshell -n -p .
```

The included Hyprland configuration starts Quickshell automatically at session
startup. Setup is not needed again unless you move to a new system or want to install
optional packages later.

For a login-manager development session, native scrolling, portals, locking, and
reversible configuration installation, follow [session setup](session.md). Shared
Nextcloud ownership and credential migration are in [Nextcloud setup](nextcloud.md).
