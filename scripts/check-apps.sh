#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
apps_test_config=$(mktemp -d)
trap 'rm -rf -- "$apps_test_config"' EXIT
export XDG_CONFIG_HOME="$apps_test_config" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
for phase in write read; do
    APPS_TEST_PHASE="$phase" timeout 15s dbus-run-session quickshell -p "$PWD/apps-smoke.qml" --no-color > "$apps_test_config/$phase.log" 2>&1 || { cat "$apps_test_config/$phase.log"; exit 1; }
    cat "$apps_test_config/$phase.log"
    rg -q "APPS PASS $phase" "$apps_test_config/$phase.log"
done
