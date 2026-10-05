# Arch packaging and ownership

`PKGBUILD` is the authoritative Arch dependency and installation definition.
There are no release tags yet, so the recipe builds the development branch as
`zephyrus-shell-git`, providing/conflicting with `zephyrus-shell`. Conventional
VCS `pkgver()` uses the commit count and short hash (`r23.g7bb3a0b`). The
`zephyrus-shell-session-git` split package enables the complete supplied
Hyprland session. Both are ordinary pacman packages. No install hook provisions
accounts, enables services, loads kernel modules, or invokes pacman.

The VCS source is fetched before packaging. `package()` only stages files from
that source. Runtime QML/Python/assets/defaults live under
`/usr/share/zephyrus-shell`; public launch/setup commands live under `/usr/bin`.
The CPU boost helper, polkit policy, clipboard unit, color scheme and login entry
use standard `/usr/lib` and `/usr/share` locations. `REVISION` records the exact
payload commit. Tests, local compiled QMLTermWidget copies, credentials, package
build output and mutable user state are excluded. Personal configuration, cache
and state stay in XDG directories. Third-party artwork licenses are installed.
The repository has no top-level license grant; `LicenseRef-Zephyrus` records that
existing limitation rather than inventing permission to redistribute it.

## Dependency audit

The classifications below explain the recipe; edit dependency metadata in the
PKGBUILD rather than treating this document as another install list.

| Class | Evidence and ownership |
| --- | --- |
| Required shell runtime | Quickshell/Qt Quick render the shell and bundled SVGs. No runtime QML imports QtMultimedia or Qt5Compat; playback uses mpv/ffmpeg instead, so those Qt packages are not shell requirements. Python workers use `dateutil` for calendar recurrence. `AudioInventory.qml` and `scripts/audio_devices.py` use `pactl` from libpulse; PipeWire's native Quickshell module alone does not supply it. Systemd supplies `loginctl`, `busctl`, `systemctl` and `systemd-inhibit`. GLib supplies `gio`, `gdbus` and `gsettings`; XDG helpers open URLs and resolve user folders. Bash launches the supplied wrappers; coreutils supplies `du` and standard helpers. |
| Full session runtime | The session split package requires the supported Hyprland Lua/scrolling runtime, UWSM, lock/idle/authentication agents, portals and PipeWire/WirePlumber (`wpctl` shortcuts). It also selects the Qt 6 terminal widget, pairing/GPU Python bindings, capture/history helpers, hardware controls and the Kitty/Dolphin shortcuts and shared appearance defaults. It installs network/Bluetooth/GPU integrations without enabling their services. |
| Optional shell features | Core `optdepends` describe terminal, screenshots, clipboard history, backlight/DDC/PCI details, playback/conversion, pairing/GPU selection, Projects Git/Mise/editor integration, Steam/Epic/UMU and torrent handoff. WARP uses `cloudflare-warp-nox-bin`, `python-dbus` and `python-gobject`; its packaged on-demand service stays disabled and per-user authorization is explicit. Missing optional executables are handled by the owning feature. Installing the session package enables the standard session subset. User-selected browsers, starters, games, Flatpaks, and alternate desktop wallpaper backends are external applications, not blanket package requirements. |
| Build/package only | `git` retrieves the VCS source and computes the version. The payload is interpreted QML/Python; it compiles no native plugin. Standard `base-devel` supplies makepkg's normal build tools. Qt development/compiler packages are not shell runtime requirements. |
| Development/test only | Python unittest, Node for JS model tests, Qt tools/qmltestrunner, and screenshot/Wayland smoke-test tools are development checks. They are not installed just to run the packaged shell. No PKGBUILD `check()` runs the interactive/network-capable full suite. |
| Host/service configuration | NetworkManager/Bluetooth/switcheroo service activation, login-manager policy, I2C module loading/group membership and power-profile authority are explicit provisioning choices. Existing asusd or PPD is used; packaging does not select another power owner. DDC requires suitable hardware, firmware DDC/CI settings and an explicit permissions operation. |

## Build and run locally

A normal remote build uses ordinary makepkg:

```sh
makepkg --syncdeps --install
```

For the current working tree, including non-ignored uncommitted changes:

```sh
scripts/build-package.sh --syncdeps --install
```

This snapshots the checkout into a temporary Git repository, creates a local
snapshot commit only when needed, and uses standard Git URL rewriting to supply
makepkg's VCS source locally. It neither edits the original Git history nor
fetches Zephyrus from GitHub. Dirty builds have a synthetic local revision/hash;
clean builds preserve the real upstream version. `PKGDEST` can select a separate
output directory. Other package dependency downloads still use pacman normally.
Production builds use the public source and never discover a sibling checkout.

Direct development remains `quickshell -n -p .`; its reversible session shim is
`python3 scripts/setup-session.py install` / `teardown`. Package installation
alone does not replace personal session configuration. After installing:

```sh
zephyrus-shell-session install
systemctl --user daemon-reload
```

The public `zephyrus-shell-session provision --home-strategies FILE` command is
for an installer skeleton with XDG paths pointing inside that skeleton. It is
idempotent, creates no reversible-development manifest/backups, and appends its
own relative file inventory in `PATH<TAB>replace<TAB>never|unchanged` format.
Generated session links/configuration use `never` so fallback roots remain
usable; editable appearance defaults use `unchanged` to preserve user edits.
`zephyrus-shell-session check` verifies generated configuration and links while
allowing edited appearance defaults. Consumers do not enumerate internal paths.

DDC setup is separate: `sudo zephyrus-shell-hardware configure-ddc --user USER`.
It changes host permissions and loads the module; never run that operation while
merely building a package. External system provisioning tools may manage this
policy separately.

## Updates and migration

Consumers can build the root PKGBUILD through their own package workflow.
Refresh the source checkout before rebuilding so metadata and payload changes
are consumed together. Pacman `-Syu` alone cannot update a local VCS package
that is absent from configured repositories; rebuild it through your package
workflow or rerun the local build/install command.
Publish upstream payload changes before a remote rebuild.

An older `zephyrus-shell` package conflicts with the new
`-git` package; pacman will require its replacement. Older manual installations may
also have created unowned color-scheme/session files. On an existing mutable
root inspect `pacman -Qo /usr/share/color-schemes/Zephyrus.colors` and
`pacman -Qo /usr/share/wayland-sessions/zephyrus.desktop`; back up/remove only
confirmed obsolete unowned files if pacman reports file conflicts. A clean
candidate has none of those overlay conflicts. Existing development shims use
their normal teardown before switching to the installed session.

Run `python3 -m unittest discover -s tests -p test_packaging.py -v` for metadata,
staging and a real local makepkg build/archive/setup check. The real build check
uses `--nodeps --nocheck` without installing anything; dependency resolution and
login behavior still need an Arch clean-root/session test.

Arch conventions were checked against the [PKGBUILD manual](https://man.archlinux.org/man/PKGBUILD.5.en). Optional Legendary packaging follows [its upstream package guide](https://github.com/legendary-gl/legendary/wiki/Available-Linux-Packages); UMU is in [Arch Multilib](https://archlinux.org/packages/multilib/x86_64/umu-launcher/).

## Change inventory

In `zephyrus-shell`, this change completes `PKGBUILD`, the `packaging/` launchers,
`desktop/Zephyrus.colors`, `desktop/zephyrus.desktop` and the four
`desktop/defaults/` templates. It updates `scripts/setup-system.sh` and
`scripts/setup-session.py`, adds `scripts/build-package.sh` and
`scripts/setup-hardware.py`, and removes `scripts/install-controls.sh`.
Validation lives in `tests/test_packaging.py`, `tests/test_session_setup.py` and
`tests/test_hardware_setup.py`. Documentation/configuration changes are
`.gitignore`, `README.md`, `docs/setup.md`, `docs/session.md`,
`docs/verification.md` and this document. Some packaging/setup files were already
uncommitted when this task began; that work was preserved and completed.
