#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Prepare an Arch Linux system to run Zephyrus Shell.

Usage: scripts/setup-system.sh [--with-optional-controls] [--enable-services]

Options:
  --with-optional-controls  Compatibility flag; display and power helpers are installed by default.
  --enable-services         Enable and start network and Bluetooth services.
  -h, --help                Show this help.
EOF
}

enable_services=false
for arg in "$@"; do
    case "$arg" in
        --with-optional-controls) ;;
        --enable-services) enable_services=true ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
    esac
done

if ! command -v pacman >/dev/null 2>&1; then
    printf 'This setup script supports Arch Linux (pacman) only.\n' >&2
    exit 1
fi

packages=(
    quickshell
    hyprland
    hyprlock
    hypridle
    brightnessctl
    ddcutil
    i2c-tools
    uwsm
    pciutils
    xdg-desktop-portal
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    hyprshot
    satty
    kooha
    wl-clipboard
    cliphist
    libnotify
    xdg-user-dirs
    kitty
    dolphin
    git
    qt6-declarative
    qt5-wayland
    qt6-wayland
    qt6-5compat
    qmltermwidget
    noto-fonts
    breeze-gtk
    breeze-icons
    breeze
    breeze5
    kvantum
    kvantum-qt5
    plasma-integration
    plasma5-integration
    python
    python-dateutil
    python-dbus
    python-gobject
    pipewire
    pipewire-pulse
    wireplumber
    libpulse
    networkmanager
    bluez
    upower
    hyprpolkitagent
    switcheroo-control
)

if ! command -v sudo >/dev/null 2>&1; then
    printf 'sudo is required to install system packages.\n' >&2
    exit 1
fi

sudo pacman -S --needed "${packages[@]}"
sudo bash "$(dirname -- "${BASH_SOURCE[0]}")/install-controls.sh"

# ddcutil ships modules-load/udev rules on Arch; ensure the current boot is
# ready too. Group membership provides stable access across suspend/resume.
printf 'i2c-dev\n' | sudo tee /etc/modules-load.d/zephyrus-ddc.conf >/dev/null
sudo modprobe i2c-dev
ddc_user=${SUDO_USER:-$(id -un)}
if [[ "$ddc_user" != root ]]; then
    sudo usermod -aG i2c "$ddc_user"
fi
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=i2c-dev

if [[ "$enable_services" == true ]]; then
    sudo systemctl enable --now NetworkManager.service bluetooth.service
else
    printf '\nServices were not changed. Enable the services used by the controls you want:\n'
    printf '  sudo systemctl enable --now NetworkManager.service bluetooth.service\n'
fi

cat <<'EOF'

System dependencies are installed. Prepare the repository-linked login configuration:
  python3 scripts/setup-session.py install

Select Hyprland at login. The native scrolling layout needs no plugins.
Log out and back in once for I2C group access. Enable DDC/CI in external
monitors' own menus; Settings detects their connector's bus automatically.

See docs/session.md for locking, portals, teardown and the live test checklist.

Power controls use an already active asusd or power-profiles-daemon. Do not enable competing profile owners. GPU selection uses switcheroo-control.
EOF
