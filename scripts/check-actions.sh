#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
action_test_root=$(mktemp -d)
trap 'rm -rf -- "$action_test_root"' EXIT
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
export XDG_CONFIG_HOME="$action_test_root/config" XDG_DATA_HOME="$action_test_root/data" XDG_CACHE_HOME="$action_test_root/cache" XDG_STATE_HOME="$action_test_root/state"
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
timeout 15s dbus-run-session quickshell -p "$PWD/action-controls-smoke.qml" --no-color > "$action_test_root/log" 2>&1 || { cat "$action_test_root/log"; exit 1; }
cat "$action_test_root/log"
rg -q 'ACTION CONTROLS PASS' "$action_test_root/log"
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|ERROR|ACTION CONTROLS FAIL' "$action_test_root/log"; then exit 1; fi
