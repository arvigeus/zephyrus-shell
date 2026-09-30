#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software DRAWER_SHELL_CAPTURE=1
mkdir -p tests/artifacts
preview_test_log=$(mktemp)
trap 'rm -f -- "$preview_test_log"' EXIT
timeout 45s dbus-run-session quickshell -p "$PWD/preview.qml" --no-color > "$preview_test_log" 2>&1 || { cat "$preview_test_log"; exit 1; }
cat "$preview_test_log"
for step in {0..11}; do
    rg -q "CAPTURE .*preview-$step.png true" "$preview_test_log"
    test -s "tests/artifacts/preview-$step.png"
done
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|ERROR qml:' "$preview_test_log"; then exit 1; fi
