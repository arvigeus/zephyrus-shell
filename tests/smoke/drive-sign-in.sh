#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
export PYTHONPATH="$PWD/tests/fixtures/drive-sign-in${PYTHONPATH:+:$PYTHONPATH}"
export ZEPHYRUS_DRIVE_FIXTURE="$SMOKE_ROOT/callback"
offline
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
run_smoke drive-sign-in "DRIVE SIGN IN" 30s
python3 - <<'PY'
import json
import os
from pathlib import Path
token = Path(os.environ['XDG_CONFIG_HOME']) / 'zephyrus-shell/credentials/google-drive/token.json'
assert token.stat().st_mode & 0o777 == 0o600
assert json.loads(token.read_text())['access_token'] == 'fixture'
PY
