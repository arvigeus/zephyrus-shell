#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
tray_test_root=$(mktemp -d)
trap 'rm -rf -- "$tray_test_root"' EXIT
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
export XDG_CONFIG_HOME="$tray_test_root/config" XDG_DATA_HOME="$tray_test_root/data" XDG_CACHE_HOME="$tray_test_root/cache" XDG_STATE_HOME="$tray_test_root/state"
timeout 15s dbus-run-session quickshell -p "$PWD/tray-controls-smoke.qml" --no-color > "$tray_test_root/log" 2>&1 || { cat "$tray_test_root/log"; exit 1; }
cat "$tray_test_root/log"
rg -q 'TRAY CONTROLS PASS' "$tray_test_root/log"
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|ERROR|TRAY CONTROLS FAIL|Cannot display PlatformMenuEntry' "$tray_test_root/log"; then exit 1; fi
