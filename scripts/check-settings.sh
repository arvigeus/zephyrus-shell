#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
settings_test_root=$(mktemp -d)
trap 'rm -rf -- "$settings_test_root"' EXIT
export XDG_CONFIG_HOME="$settings_test_root/config" XDG_DATA_HOME="$settings_test_root/data" XDG_CACHE_HOME="$settings_test_root/cache" XDG_STATE_HOME="$settings_test_root/state"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
unset HYPRLAND_INSTANCE_SIGNATURE
mkdir -p tests/artifacts
timeout 20s dbus-run-session quickshell -p "$PWD/settings-smoke.qml" --no-color > "$settings_test_root/log" 2>&1 || { cat "$settings_test_root/log"; exit 1; }
cat "$settings_test_root/log"
rg -q 'SETTINGS PASS' "$settings_test_root/log"
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|ERROR qml:|SETTINGS FAIL|Cannot open:.*assets/lucide' "$settings_test_root/log"; then exit 1; fi
