#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Install the canonical Zephyrus Shell package and prepare an Arch session.

Usage: scripts/setup-system.sh [--enable-services]

Options:
  --enable-services  Enable and start network and Bluetooth services.
  -h, --help         Show this help.
EOF
}

enable_services=false
for arg in "$@"; do
    case "$arg" in
        --enable-services) enable_services=true ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown option: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
    esac
done

if ! command -v pacman >/dev/null 2>&1 || ! command -v makepkg >/dev/null 2>&1; then
    printf 'This setup script supports Arch Linux (pacman) only.\n' >&2
    exit 1
fi

if [[ $EUID == 0 ]]; then
    printf 'Run this script as your login user; makepkg must not run as root.\n' >&2
    exit 1
fi

script_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if ! command -v sudo >/dev/null 2>&1; then
    printf 'sudo is required to install system packages.\n' >&2
    exit 1
fi
sudo pacman -S --needed base-devel git
printf 'Building/installing Zephyrus Shell from this checkout.\n'
"$script_root/scripts/build-package.sh" --syncdeps --install

# Hardware permissions are a deliberate host setup step; package installation
# never loads kernel modules or changes account group membership.
ddc_user=${SUDO_USER:-$(id -un)}
sudo python3 "$script_root/scripts/setup-hardware.py" configure-ddc --user "$ddc_user"

if [[ "$enable_services" == true ]]; then
    sudo systemctl enable --now NetworkManager.service bluetooth.service
else
    printf '\nServices were not changed. Enable the services used by the controls you want:\n'
    printf '  sudo systemctl enable --now NetworkManager.service bluetooth.service\n'
fi

cat <<'EOF'

System dependencies and the package are installed. Link the login session to this checkout:
  python3 scripts/setup-session.py install
  systemctl --user daemon-reload

Then log out and choose "Zephyrus (Hyprland)" at login (log out once anyway for
I2C group access). See docs/session.md for teardown and troubleshooting.
EOF
