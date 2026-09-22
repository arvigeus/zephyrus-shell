#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software DRAWER_SHELL_CAPTURE=1
exec timeout 20s dbus-run-session quickshell -p "$PWD/preview.qml" --no-color
