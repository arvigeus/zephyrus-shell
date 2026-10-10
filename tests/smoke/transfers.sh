#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
offline
# Files only operates inside $HOME.
export HOME="$SMOKE_ROOT" ZEPHYRUS_TRANSFER_FIXTURE="$SMOKE_ROOT/fixture" XDG_MUSIC_DIR="$SMOKE_ROOT/music"
mkdir -p "$ZEPHYRUS_TRANSFER_FIXTURE/target"
python3 - <<'PY'
import os
from pathlib import Path
(Path(os.environ['ZEPHYRUS_TRANSFER_FIXTURE'])/'source.txt').write_bytes(b'fixture\n' * 1024 * 1024)
PY
start_fixture music python3 tests/fixtures/music-download.py
wait_for "$XDG_CONFIG_HOME/zephyrus-shell/music.json"
run_smoke transfers "TRANSFERS" 30s
cmp "$ZEPHYRUS_TRANSFER_FIXTURE/source.txt" "$ZEPHYRUS_TRANSFER_FIXTURE/target/source.txt"

python3 - <<'PY'
import os
from pathlib import Path
saved = list(Path(os.environ['XDG_MUSIC_DIR']).glob('*.mka'))
assert len(saved) == 1 and saved[0].stat().st_size > 0, 'Music did not save the stream'
assert not list(Path(os.environ['XDG_MUSIC_DIR']).glob('.zephyrus-*')), 'Partial Music output was left behind'
PY
