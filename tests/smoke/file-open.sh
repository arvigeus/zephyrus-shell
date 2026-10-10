#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
export ZEPHYRUS_OPEN_FIXTURE="$SMOKE_ROOT/fixture"
export PYTHONPATH="$PWD/tests/fixtures/file-open${PYTHONPATH:+:$PYTHONPATH}"
mkdir -p "$ZEPHYRUS_OPEN_FIXTURE"
offline
run_smoke file-open "FILE OPEN" 35s
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
