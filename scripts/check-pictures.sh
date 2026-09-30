#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
pictures_test_root=$(mktemp -d)
trap 'rm -rf -- "$pictures_test_root"' EXIT
export XDG_CONFIG_HOME="$pictures_test_root/config" XDG_DATA_HOME="$pictures_test_root/data" XDG_CACHE_HOME="$pictures_test_root/cache"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
export https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9
unset ALL_PROXY all_proxy NO_PROXY no_proxy
mkdir -p "$XDG_CONFIG_HOME/zephyrus-shell" "$XDG_DATA_HOME/zephyrus-shell/wallpapers"
python3 - <<'PY'
import os
from pathlib import Path
import struct
import zlib
image = Path(os.environ['XDG_DATA_HOME']) / 'zephyrus-shell/wallpapers/wallhaven-fixture.png'
def chunk(kind, data):
    return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
image.write_bytes(b'\x89PNG\r\n\x1a\n'
    + chunk(b'IHDR', struct.pack('!2I5B', 1, 1, 8, 2, 0, 0, 0))
    + chunk(b'IDAT', zlib.compress(b'\x00\x45\x67\x89')) + chunk(b'IEND', b''))
image.with_name('wallhaven-fixture2.png').write_bytes(image.read_bytes())
PY
for pictures_test_phase in write read; do
    export PICTURES_TEST_PHASE="$pictures_test_phase"
    timeout 15s dbus-run-session quickshell -p "$PWD/pictures-smoke.qml" --no-color > "$pictures_test_root/log" 2>&1 || { cat "$pictures_test_root/log"; exit 1; }
    cat "$pictures_test_root/log"
    rg -q 'PICTURES PASS' "$pictures_test_root/log"
    if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|PICTURES FAIL|Error decoding' "$pictures_test_root/log"; then exit 1; fi
done
