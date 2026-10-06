#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
open_test_root=$(mktemp -d "$PWD/tests/.file-open-XXXXXX")
trap 'rm -rf -- "$open_test_root"' EXIT
export XDG_CONFIG_HOME="$open_test_root/config" XDG_DATA_HOME="$open_test_root/data" XDG_CACHE_HOME="$open_test_root/cache"
export ZEPHYRUS_OPEN_FIXTURE="$open_test_root/fixture"
export PYTHONPATH="$PWD/tests/fixtures/file-open${PYTHONPATH:+:$PYTHONPATH}"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
mkdir -p "$ZEPHYRUS_OPEN_FIXTURE"
export https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9
unset ALL_PROXY all_proxy
timeout 35s dbus-run-session quickshell -p "$PWD/file-open-smoke.qml" --no-color > "$open_test_root/log" 2>&1 || { cat "$open_test_root/log"; exit 1; }
cat "$open_test_root/log"
rg -q 'FILE OPEN PASS' "$open_test_root/log"
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|Unable to assign|FILE OPEN FAIL|Cannot open:|Traceback' "$open_test_root/log"; then exit 1; fi
python3 - <<'PY'
import json
import os
from pathlib import Path
fixture = Path(os.environ['ZEPHYRUS_OPEN_FIXTURE'])
assert (fixture / 'saved').read_bytes() == b'edited in default app'
assert (fixture / 'launches').read_text() == '2'
working = Path((fixture / 'opened').read_text())
assert working.read_bytes() == b'edited in default app'
manifest = json.loads((working.parent.parent / 'session.json').read_text())
assert manifest['item']['path'] == '/Document.txt'
assert not list(working.parent.parent.glob('.download-*'))
assert not list(working.parent.glob('.save-*'))
PY
