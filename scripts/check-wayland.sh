#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export QT_QPA_PLATFORM=wayland
wayland_test_log=$(mktemp)
trap 'rm -f -- "$wayland_test_log"' EXIT
timeout 18s dbus-run-session quickshell -p "$PWD/smoke.qml" --no-color > "$wayland_test_log" 2>&1 || { cat "$wayland_test_log"; exit 1; }
cat "$wayland_test_log"
rg -q 'SMOKE PASS' "$wayland_test_log"
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|ERROR qml:' "$wayland_test_log"; then exit 1; fi
