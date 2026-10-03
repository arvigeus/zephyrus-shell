#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
terminal_test_root=$(mktemp -d)
trap 'rm -rf -- "$terminal_test_root"' EXIT
export ZEPHYRUS_TERMINAL_TEST="$terminal_test_root"
export XDG_CONFIG_HOME="$terminal_test_root/config" XDG_DATA_HOME="$terminal_test_root/data" XDG_CACHE_HOME="$terminal_test_root/cache" XDG_STATE_HOME="$terminal_test_root/state"
export SHELL="$terminal_test_root/shell"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
unset HYPRLAND_INSTANCE_SIGNATURE BASH_ENV ENV
mkdir -p "$XDG_CONFIG_HOME/zephyrus-shell" tests/artifacts
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
timeout 28s dbus-run-session quickshell -p "$PWD/terminal-smoke.qml" --no-color > "$terminal_test_root/log" 2>&1 || { cat "$terminal_test_root/log"; exit 1; }
cat "$terminal_test_root/log"
rg -q 'TERMINAL PASS' "$terminal_test_root/log"
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|ERROR qml:|TERMINAL FAIL|non-bindable' "$terminal_test_root/log"; then exit 1; fi
while read -r terminal_pid; do
    if kill -0 "$terminal_pid" 2>/dev/null; then
        printf 'Terminal shell %s survived module destruction\n' "$terminal_pid" >&2
        exit 1
    fi
done < "$terminal_test_root/pids"
