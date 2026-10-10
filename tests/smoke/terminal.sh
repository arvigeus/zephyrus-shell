#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
export ZEPHYRUS_TERMINAL_TEST="$SMOKE_ROOT"
export SHELL="$SMOKE_ROOT/shell"
unset BASH_ENV ENV
cat > "$SHELL" <<'BASH'
#!/bin/bash
exec /bin/bash --noprofile --norc
BASH
chmod +x "$SHELL"
python3 - <<'PY'
import json
import os
from pathlib import Path
root = Path(os.environ['ZEPHYRUS_TERMINAL_TEST'])
command = "export ZE_TEST=first; cd /tmp; printf '%s' \"$ZE_TEST:$PWD\" > '" + str(root / 'result') + "'"
(root / 'config/zephyrus-shell/terminal.json').write_text(json.dumps({'commands': [{'name': 'Fixture', 'command': command}]}))
PY
run_smoke terminal "TERMINAL" 28s "non-bindable"
while read -r terminal_pid; do
    if kill -0 "$terminal_pid" 2>/dev/null; then
        printf 'Terminal shell %s survived module destruction\n' "$terminal_pid" >&2
        exit 1
    fi
done < "$SMOKE_ROOT/pids"
