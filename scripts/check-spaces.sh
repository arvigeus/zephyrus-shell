#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
spaces_test_root=$(mktemp -d)
trap 'rm -rf -- "$spaces_test_root"' EXIT
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
export XDG_CONFIG_HOME="$spaces_test_root/config" XDG_DATA_HOME="$spaces_test_root/data" XDG_CACHE_HOME="$spaces_test_root/cache" XDG_STATE_HOME="$spaces_test_root/state"
timeout 20s dbus-run-session quickshell -p "$PWD/spaces-smoke.qml" --no-color > "$spaces_test_root/log" 2>&1 || { cat "$spaces_test_root/log"; exit 1; }
cat "$spaces_test_root/log"
rg -q 'SPACES CONTROLS PASS' "$spaces_test_root/log"
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|ERROR|SPACES CONTROLS FAIL|Cannot open:.*assets/lucide' "$spaces_test_root/log"; then exit 1; fi
