#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
mkdir -p "$SMOKE_ROOT/bin"
# Every systemd/WARP boundary uses a private bus and fixture executables.
ln -s "$PWD/tests/fixtures/warp_host.py" "$SMOKE_ROOT/bin/warp-cli"
ln -s "$PWD/tests/fixtures/warp_host.py" "$SMOKE_ROOT/bin/systemctl"
export PATH="$SMOKE_ROOT/bin:$PATH"
# The fixture host owns both the session and the fake system bus.
dbus-run-session bash -c '
    export DBUS_SYSTEM_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"
    python3 tests/fixtures/warp_host.py >"$SMOKE_ROOT/host.log" 2>&1 &
    trap "kill $! 2>/dev/null; wait $! 2>/dev/null" EXIT
    for _ in {1..50}; do rg -q "HOST READY" "$SMOKE_ROOT/host.log" && break; sleep 0.1; done
    rg -q "HOST READY" "$SMOKE_ROOT/host.log" || { cat "$SMOKE_ROOT/host.log"; exit 1; }
    ZEPHYRUS_HARNESS=tests/smoke/warp.qml timeout 25s quickshell -p "$PWD/harness.qml" --no-color
' >"$SMOKE_ROOT/warp.log" 2>&1 || { cat "$SMOKE_ROOT/warp.log"; exit 1; }
check_log "$SMOKE_ROOT/warp.log" "WARP"
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
