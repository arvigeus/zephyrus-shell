#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
notification_test_root=$(mktemp -d)
trap 'rm -rf -- "$notification_test_root"' EXIT
export XDG_CONFIG_HOME="$notification_test_root/config" XDG_DATA_HOME="$notification_test_root/data" XDG_STATE_HOME="$notification_test_root/state" XDG_CACHE_HOME="$notification_test_root/cache"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
mkdir -p tests/artifacts
timeout 15s dbus-run-session quickshell -p "$PWD/notifications-smoke.qml" --no-color > "$notification_test_root/log" 2>&1 || { cat "$notification_test_root/log"; exit 1; }
cat "$notification_test_root/log"
rg -q 'NOTIFICATIONS PASS' "$notification_test_root/log"
test -s tests/artifacts/notification-popup.png
test -s tests/artifacts/activity-popup.png
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|ERROR qml:|NOTIFICATIONS FAIL' "$notification_test_root/log"; then exit 1; fi
