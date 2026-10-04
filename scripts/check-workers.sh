#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
worker_test_root=$(mktemp -d)
trap 'rm -rf -- "$worker_test_root"' EXIT
export XDG_CONFIG_HOME="$worker_test_root/config" XDG_DATA_HOME="$worker_test_root/data" XDG_CACHE_HOME="$worker_test_root/cache"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
export https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9
timeout 15s dbus-run-session quickshell -p "$PWD/worker-smoke.qml" --no-color > "$worker_test_root/log" 2>&1 || { cat "$worker_test_root/log"; exit 1; }
cat "$worker_test_root/log"
rg -q 'WORKER PASS' "$worker_test_root/log"
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|WORKER FAIL' "$worker_test_root/log"; then exit 1; fi
