#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Prepare an Arch Linux system to run Zephyrus Shell.

Usage: scripts/setup-system.sh [--with-optional-controls] [--enable-services]

Options:
  --with-optional-controls  Also install brightnessctl and ddcutil.
  --enable-services         Enable and start NetworkManager and Bluetooth.
  -h, --help                Show this help.
EOF
}

with_optional_controls=false
enable_services=false
for arg in "$@"; do
    case "$arg" in
        --with-optional-controls) with_optional_controls=true ;;
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
    qt6-declarative
    qmltermwidget
    noto-fonts
    python
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
    power-profiles-daemon
)

if [[ "$with_optional_controls" == true ]]; then
    packages+=(brightnessctl ddcutil)
fi

if ! command -v sudo >/dev/null 2>&1; then
    printf 'sudo is required to install system packages.\n' >&2
    exit 1
fi

sudo pacman -S --needed "${packages[@]}"

if [[ "$enable_services" == true ]]; then
    sudo systemctl enable --now NetworkManager.service bluetooth.service power-profiles-daemon.service
else
    printf '\nServices were not changed. Enable the services used by the controls you want:\n'
    printf '  sudo systemctl enable --now NetworkManager.service bluetooth.service power-profiles-daemon.service\n'
fi

cat <<'EOF'

System dependencies are installed. Start Zephyrus Shell from a Hyprland session with:
  quickshell -n -p .

Cardwire is an optional GPU switching helper and is not installed by this script.
EOF
