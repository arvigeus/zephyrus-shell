#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
windows_test_root=$(mktemp -d)
windows_test_output_created=false
windows_test_cleanup() {
    if "$windows_test_output_created"; then hyprctl output remove ZEPHYRUS-TEST >/dev/null 2>&1 || true; fi
    rm -rf -- "$windows_test_root"
}
trap windows_test_cleanup EXIT
export XDG_CONFIG_HOME="$windows_test_root/config" XDG_DATA_HOME="$windows_test_root/data" XDG_CACHE_HOME="$windows_test_root/cache" XDG_STATE_HOME="$windows_test_root/state"
export QT_QPA_PLATFORM=wayland
mkdir -p tests/artifacts
hyprctl monitors all -j | python3 -c 'import json, sys; sys.exit("ZEPHYRUS-TEST already exists; refusing to remove it") if any(m["name"] == "ZEPHYRUS-TEST" for m in json.load(sys.stdin)) else None'
hyprctl output create headless ZEPHYRUS-TEST
windows_test_output_created=true
timeout 40s dbus-run-session quickshell -p "$PWD/window-controls-smoke.qml" --no-color > "$windows_test_root/log" 2>&1 || { cat "$windows_test_root/log"; exit 1; }
cat "$windows_test_root/log"
rg -q 'WINDOW CONTROLS PASS' "$windows_test_root/log"
test -s tests/artifacts/window-menu.png
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|ERROR qml:|WINDOW CONTROLS FAIL|Cannot open:.*assets/lucide' "$windows_test_root/log"; then exit 1; fi
