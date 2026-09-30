#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
power_test_root=$(mktemp -d)
trap 'rm -rf -- "$power_test_root"' EXIT
export XDG_CONFIG_HOME="$power_test_root/config" XDG_DATA_HOME="$power_test_root/data" XDG_CACHE_HOME="$power_test_root/cache" XDG_STATE_HOME="$power_test_root/state"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
mkdir -p tests/artifacts
timeout 15s dbus-run-session quickshell -p "$PWD/power-smoke.qml" --no-color > "$power_test_root/log" 2>&1 || { cat "$power_test_root/log"; exit 1; }
cat "$power_test_root/log"
rg -q 'POWER PASS' "$power_test_root/log"
test -s tests/artifacts/battery-details.png
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|ERROR qml:|POWER FAIL' "$power_test_root/log"; then exit 1; fi
