#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
offline
mkdir -p "$XDG_DATA_HOME/zephyrus-shell/wallpapers"
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
for pictures_test_case in write wallhaven bing; do
    export PICTURES_TEST_PROVIDER="$pictures_test_case"
    pictures_test_phase=read
    if [[ "$pictures_test_case" == write ]]; then
        pictures_test_phase=write
    elif [[ "$pictures_test_case" == bing ]]; then
        python3 - <<'PY'
import json,os
from pathlib import Path
setting=Path(os.environ['XDG_CONFIG_HOME'])/'zephyrus-shell/wallpaper.json'
value=json.loads(setting.read_text())
value['provider']='bing'
setting.write_text(json.dumps(value))
PY
    fi
    export PICTURES_TEST_PHASE="$pictures_test_phase"
    run_smoke pictures "PICTURES" 15s "Error decoding"
done
