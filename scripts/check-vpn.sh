#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
vpn_test_root=$(mktemp -d)
trap 'rm -rf -- "$vpn_test_root"' EXIT
export XDG_CONFIG_HOME="$vpn_test_root/config" XDG_DATA_HOME="$vpn_test_root/data" XDG_CACHE_HOME="$vpn_test_root/cache" XDG_STATE_HOME="$vpn_test_root/state"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
unset HYPRLAND_INSTANCE_SIGNATURE
mkdir -p "$vpn_test_root/bin" "$XDG_CONFIG_HOME/zephyrus-shell/vpn" tests/artifacts
ln -s "$PWD/tests/fixtures/vpn_host.py" "$vpn_test_root/bin/nmcli"
export PATH="$vpn_test_root/bin:$PATH"
python3 - <<'PY'
import os
import base64
from pathlib import Path
path = Path(os.environ['XDG_CONFIG_HOME']) / 'zephyrus-shell/vpn/Home VPN.conf'
path.touch(mode=0o600)
path.write_text('[Interface]\nPrivateKey = ' + base64.b64encode(b'\x01' * 32).decode() + '\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = ' + base64.b64encode(b'\x02' * 32).decode() + '\nAllowedIPs = 0.0.0.0/0\n')
PY
dbus-run-session bash -c '
    export DBUS_SYSTEM_BUS_ADDRESS="$DBUS_SESSION_BUS_ADDRESS"
    python3 tests/fixtures/vpn_host.py host > "$XDG_STATE_HOME-host.log" 2>&1 &
    host=$!
    trap '\''kill "$host" 2>/dev/null || true; wait "$host" || true'\'' EXIT
    for ((i=0; i<50; i++)); do
        if rg -q "VPN HOST READY" "$XDG_STATE_HOME-host.log"; then break; fi
        sleep 0.1
    done
    if ! rg -q "VPN HOST READY" "$XDG_STATE_HOME-host.log"; then cat "$XDG_STATE_HOME-host.log"; exit 1; fi
    timeout 20s quickshell -p "$PWD/vpn-smoke.qml" --no-color
' > "$vpn_test_root/log" 2>&1 || { cat "$vpn_test_root/log"; exit 1; }
cat "$vpn_test_root/log"
rg -q 'VPN PASS' "$vpn_test_root/log"
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|ERROR qml:|VPN FAIL|Cannot open:.*assets/|test-secret' "$vpn_test_root/log"; then exit 1; fi
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
