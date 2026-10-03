#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
theme_test_root=$(mktemp -d)
trap 'rm -rf -- "$theme_test_root"' EXIT
export XDG_CONFIG_HOME="$theme_test_root/config" XDG_DATA_HOME="$theme_test_root/data" XDG_STATE_HOME="$theme_test_root/state" XDG_CACHE_HOME="$theme_test_root/cache"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software ZEPHYRUS_THEME_NO_NOTIFY=1
unset HYPRLAND_INSTANCE_SIGNATURE
timeout 20s dbus-run-session quickshell -p "$PWD/theme-smoke.qml" --no-color > "$theme_test_root/log" 2>&1 || { cat "$theme_test_root/log"; exit 1; }
cat "$theme_test_root/log"
rg -q 'THEME PASS' "$theme_test_root/log"
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|ERROR qml:|THEME FAIL' "$theme_test_root/log"; then exit 1; fi
