# System setup

Run `scripts/setup-system.sh` as your login user on Arch Linux after cloning the
project and before the first run. It builds and installs the canonical
`zephyrus-shell-git` package and the `zephyrus-shell-session-git` dependency
package from this checkout, including the standard full-session
integrations and surrounding desktop session tools.

`PKGBUILD` owns the package dependencies and install paths. Its VCS versions are
derived from the current Git checkout; `git` is the package build dependency.
For direct upstream package work use `makepkg --syncdeps --install`; for the
current working tree use `scripts/build-package.sh --syncdeps --install`. See
[packaging](packaging.md) for the dependency audit and consumer contract.

The metadata separates a required shell runtime (Quickshell/Qt, Python, audio metadata,
systemd and XDG/GLib command helpers) from `zephyrus-shell-session-git`, which
declares the full Hyprland-session integrations. The base package lists other
optional integrations separately. Build tools and test tools do not become
runtime dependencies. NetworkManager, Bluetooth and switcheroo-control may be
installed as optional integrations, but their services require deliberate
activation. I2C module loading and group membership are explicit host setup
performed by `scripts/setup-system.sh` or the packaged hardware setup command;
they never run as a package-install side effect.

```sh
scripts/setup-system.sh
```

The package manager asks before changing packages. Optional dependencies are
listed in `PKGBUILD` with the feature each one enables. The full-session split package selects the standard session integrations;
other optional features can be installed individually. `--with-optional-controls` remains
accepted as a redundant full-session option. GPU selection uses switcheroo-control; firmware GPU
controls belong to ASUS tooling.

The explicit setup script loads `i2c-dev` for the current boot, records it for
future boots, and adds your user to the `i2c` group using Arch's packaged device
rules. Package installation does none of these host changes. Log out and back in
after setup for group membership to apply. External monitors must support
DDC/CI and have it enabled in their own menus. Settings matches the DRM connector
to its I2C adapter automatically, including DisplayPort AUX/USB-C adapters; a bus
can also be selected in Display settings. No root access is needed at runtime.

The package provides the narrow CPU boost helper and its polkit action. It
authorizes writes of 0 or 1 to the kernel's CPUFreq boost switch; it cannot write
arbitrary sysfs paths. The UI requests administrator authentication when needed.
An authentication agent must run in the desktop session (Hyprland uses
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
`$XDG_CONFIG_HOME/zephyrus-shell/display-profiles.json`, with separate layouts for
each connected monitor set. Settings migrates the connected displays' old
`display-settings.lua` preferences automatically. Personal bus overrides live
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

The setup script and package support Arch Linux only. Other distributions can
run the shell from a checkout if their Quickshell, Qt/QML and Python runtime
packages provide the required APIs; this repository does not currently ship an
RPM package.

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
