#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
drive_test_root=$(mktemp -d "$PWD/tests/.drive-sign-in-XXXXXX")
trap 'rm -rf -- "$drive_test_root"' EXIT
export XDG_CONFIG_HOME="$drive_test_root/config" XDG_DATA_HOME="$drive_test_root/data" XDG_CACHE_HOME="$drive_test_root/cache"
export PYTHONPATH="$PWD/tests/fixtures/drive-sign-in${PYTHONPATH:+:$PYTHONPATH}"
export ZEPHYRUS_DRIVE_FIXTURE="$drive_test_root/callback"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
export https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9
unset ALL_PROXY all_proxy
export NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost
python3 - <<'PY'
import json
import os
from pathlib import Path
client = Path(os.environ['XDG_CONFIG_HOME']) / 'zephyrus-shell/credentials/google-drive/client.json'
client.parent.mkdir(parents=True)
client.write_text(json.dumps({'installed': {'client_id': 'fixture', 'client_secret': 'fixture'}}))
client.chmod(0o600)
callback = Path(os.environ['ZEPHYRUS_DRIVE_FIXTURE'])
callback.write_text('')
callback.chmod(0o600)
PY
timeout 30s dbus-run-session quickshell -p "$PWD/drive-sign-in-smoke.qml" --no-color > "$drive_test_root/log" 2>&1 || { cat "$drive_test_root/log"; exit 1; }
cat "$drive_test_root/log"
rg -q 'DRIVE SIGN IN PASS' "$drive_test_root/log"
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|Unable to assign|DRIVE SIGN IN FAIL|Cannot open:|Traceback' "$drive_test_root/log"; then exit 1; fi
python3 - <<'PY'
import json
import os
from pathlib import Path
token = Path(os.environ['XDG_CONFIG_HOME']) / 'zephyrus-shell/credentials/google-drive/token.json'
assert token.stat().st_mode & 0o777 == 0o600
assert json.loads(token.read_text())['access_token'] == 'fixture'
PY
