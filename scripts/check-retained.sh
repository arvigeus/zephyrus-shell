#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
retained_test_root=$(mktemp -d)
trap 'rm -rf -- "$retained_test_root"' EXIT
export XDG_CONFIG_HOME="$retained_test_root/config" XDG_DATA_HOME="$retained_test_root/data" XDG_CACHE_HOME="$retained_test_root/cache"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
export https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9
unset ALL_PROXY all_proxy NO_PROXY no_proxy
timeout 20s dbus-run-session quickshell -p "$PWD/retained-smoke.qml" --no-color > "$retained_test_root/log" 2>&1 || { cat "$retained_test_root/log"; exit 1; }
cat "$retained_test_root/log"
rg -q 'RETAINED PASS' "$retained_test_root/log"
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|RETAINED FAIL' "$retained_test_root/log"; then exit 1; fi
