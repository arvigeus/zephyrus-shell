# System setup

Run `scripts/setup-system.sh` once on Arch Linux after cloning the project and
before the first launch. It installs the project's required runtime packages using
`pacman`; it does not build project files or change the shell's per-launch command.

```sh
scripts/setup-system.sh
```

The installer asks `pacman` to confirm any package changes. Pass
`--with-optional-controls` to also install `brightnessctl` and `ddcutil` for laptop
and external monitor brightness controls. Cardwire is an optional GPU switching
helper and is not available from the standard Arch repositories, so install it
separately if desired.

NetworkManager, Bluetooth, and power profiles need their system services enabled
for the matching controls to work. The script leaves service state unchanged by
default. To enable and start them during setup, use:

```sh
scripts/setup-system.sh --enable-services
```

Or enable them later with:

```sh
sudo systemctl enable --now NetworkManager.service bluetooth.service power-profiles-daemon.service
```

The script supports Arch Linux only. On another distribution,
install the packages listed in `scripts/setup-system.sh` using that distribution's
package manager.

After setup, start the shell from the repository root inside Hyprland:

```sh
quickshell -n -p .
```

The included Hyprland configuration starts Quickshell automatically at session
startup. Setup is not needed again unless you move to a new system or want to install
optional packages later.
