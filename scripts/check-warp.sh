#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
warp_test_root=$(mktemp -d)
trap 'rm -rf -- "$warp_test_root"' EXIT
export XDG_CONFIG_HOME="$warp_test_root/config" XDG_DATA_HOME="$warp_test_root/data" XDG_CACHE_HOME="$warp_test_root/cache" XDG_STATE_HOME="$warp_test_root/state"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
unset HYPRLAND_INSTANCE_SIGNATURE
mkdir -p "$warp_test_root/bin" tests/artifacts
# Every systemd/WARP boundary uses a private bus and fixture executables.
ln -s "$PWD/tests/fixtures/warp_host.py" "$warp_test_root/bin/warp-cli"
ln -s "$PWD/tests/fixtures/warp_host.py" "$warp_test_root/bin/systemctl"
export PATH="$warp_test_root/bin:$PATH"
dbus-run-session bash -c '
    export DBUS_SYSTEM_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"
    python3 tests/fixtures/warp_host.py > "$XDG_STATE_HOME-host.log" 2>&1 &
    host=$!
    trap '\''kill "$host" 2>/dev/null || true; wait "$host" || true'\'' EXIT
    for ((i=0; i<50; i++)); do
        if rg -q "HOST READY" "$XDG_STATE_HOME-host.log"; then break; fi
        sleep 0.1
    done
    if ! rg -q "HOST READY" "$XDG_STATE_HOME-host.log"; then cat "$XDG_STATE_HOME-host.log"; exit 1; fi
    timeout 25s quickshell -p "$PWD/warp-smoke.qml" --no-color
' > "$warp_test_root/log" 2>&1 || { cat "$warp_test_root/log"; exit 1; }
cat "$warp_test_root/log"
rg -q 'WARP PASS' "$warp_test_root/log"
python3 - <<'PY'
import os
from pathlib import Path
calls = (Path(os.environ['XDG_STATE_HOME']) / 'fake-warp-calls').read_text().splitlines()
assert calls.count('subscribe') == 1, calls
assert calls.count('listen') == 2, calls
assert calls.count('listener-stopped') == 2, calls
assert calls.count('status') == 2, calls
assert calls[:calls.index('start')] == ['subscribe'], calls
print('WARP EVENT PASS: one subscriber, two on-demand streams, two post-action snapshots, zero periodic queries')
PY
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|ERROR qml:|WARP FAIL|Cannot open:.*assets/' "$warp_test_root/log"; then exit 1; fi
