#!/usr/bin/env bash
set -euo pipefail
if [[ $EUID != 0 ]]; then
    printf 'Run with sudo to install the scoped CPU boost helper.\n' >&2
    exit 1
fi
controls_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
install -d -o root -g root -m 755 /usr/lib/zephyrus-shell
install -o root -g root -m 755 "$controls_root/scripts/cpu-boost.py" /usr/lib/zephyrus-shell/cpu-boost
install -o root -g root -m 644 "$controls_root/system/org.zephyrus-shell.cpu-boost.policy" /usr/share/polkit-1/actions/org.zephyrus-shell.cpu-boost.policy
