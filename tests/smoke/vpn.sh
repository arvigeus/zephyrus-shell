#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
mkdir -p "$SMOKE_ROOT/bin" "$XDG_CONFIG_HOME/zephyrus-shell/vpn"
ln -s "$PWD/tests/fixtures/vpn_host.py" "$SMOKE_ROOT/bin/nmcli"
export PATH="$SMOKE_ROOT/bin:$PATH"
python3 - <<'PY'
import os
import base64
from pathlib import Path
path = Path(os.environ['XDG_CONFIG_HOME']) / 'zephyrus-shell/vpn/Home VPN.conf'
path.touch(mode=0o600)
path.write_text('[Interface]\nPrivateKey = ' + base64.b64encode(b'\x01' * 32).decode() + '\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = ' + base64.b64encode(b'\x02' * 32).decode() + '\nAllowedIPs = 0.0.0.0/0\n')
PY
# The fixture host owns both the session and the fake system bus.
dbus-run-session bash -c '
    export DBUS_SYSTEM_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"
    python3 tests/fixtures/vpn_host.py host >"$SMOKE_ROOT/host.log" 2>&1 &
    trap "kill $! 2>/dev/null; wait $! 2>/dev/null" EXIT
    for _ in {1..50}; do rg -q "VPN HOST READY" "$SMOKE_ROOT/host.log" && break; sleep 0.1; done
    rg -q "VPN HOST READY" "$SMOKE_ROOT/host.log" || { cat "$SMOKE_ROOT/host.log"; exit 1; }
    ZEPHYRUS_HARNESS=tests/smoke/vpn.qml timeout 20s quickshell -p "$PWD/harness.qml" --no-color
' >"$SMOKE_ROOT/vpn.log" 2>&1 || { cat "$SMOKE_ROOT/vpn.log"; exit 1; }
check_log "$SMOKE_ROOT/vpn.log" "VPN" "test-secret"
python3 - <<'PY'
import json
import os
from pathlib import Path
root = Path(os.environ['XDG_STATE_HOME'])
calls = [json.loads(line) for line in (root / 'vpn-calls').read_text().splitlines()]
assert sum('AddConnection2' in call for call in calls) == 1, calls
assert sum('up' in call for call in calls) == 1, calls
assert sum('down' in call for call in calls) == 2, calls
assert json.loads((root / 'vpn-host.json').read_text()) == {}
print('VPN BOUNDARY PASS: one temporary import, explicit activation, denied action preserved state, tunnel removed')
PY
