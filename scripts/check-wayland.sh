#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export QT_QPA_PLATFORM=wayland
exec timeout 18s dbus-run-session quickshell -p "$PWD/smoke.qml" --no-color
