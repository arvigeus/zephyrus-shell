#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
module_test_root=$(mktemp -d)
trap 'rm -rf -- "$module_test_root"' EXIT
export XDG_CONFIG_HOME="$module_test_root/config" XDG_DATA_HOME="$module_test_root/data" XDG_CACHE_HOME="$module_test_root/cache"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
mkdir -p "$XDG_CONFIG_HOME/zephyrus-shell" tests/artifacts
# Prevent public-network requests while verifying setup/loading and lifecycle.
export https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9
unset ALL_PROXY all_proxy NO_PROXY no_proxy
timeout 35s dbus-run-session quickshell -p "$PWD/modules-smoke.qml" --no-color > "$module_test_root/log" 2>&1 || { cat "$module_test_root/log"; exit 1; }
cat "$module_test_root/log"
rg -q 'MODULES PASS' "$module_test_root/log"
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|MODULES FAIL' "$module_test_root/log"; then exit 1; fi
