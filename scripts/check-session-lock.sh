#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
idle_test_root=$(mktemp -d)
trap 'rm -rf -- "$idle_test_root"' EXIT
export XDG_CONFIG_HOME="$idle_test_root/config" XDG_DATA_HOME="$idle_test_root/data" XDG_CACHE_HOME="$idle_test_root/cache" XDG_STATE_HOME="$idle_test_root/state"
export XDG_RUNTIME_DIR="$idle_test_root/runtime" HYPRLAND_INSTANCE_SIGNATURE=fixture-session
export ZEPHYRUS_IDLE_PROFILE="$XDG_RUNTIME_DIR/zephyrus-shell/idle-fixture-session/hypridle.conf"
export ZEPHYRUS_IDLE_LAUNCHER="$PWD/scripts/idle.py"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
mkdir -p "$XDG_RUNTIME_DIR" "$idle_test_root/bin" "$XDG_CONFIG_HOME/zephyrus-shell" tests/artifacts
chmod 700 "$XDG_RUNTIME_DIR"
python3 - <<'PYCONFIG'
import os
from pathlib import Path
(Path(os.environ["XDG_CONFIG_HOME"]) / "zephyrus-shell/theme.json").write_text('{"mode":"light"}')
PYCONFIG
export PATH="$idle_test_root/bin:$PATH"
# Exercise real policy changes and the service entry point while isolating
# service restarts and hardware actions from the user's desktop.
cat > "$idle_test_root/bin/systemctl" <<'SH'
#!/bin/sh
exec python3 "$ZEPHYRUS_IDLE_LAUNCHER" run
SH
cat > "$idle_test_root/bin/hypridle" <<'SH'
#!/bin/sh
test "$1" = --config && test -s "$2"
SH
chmod +x "$idle_test_root/bin/systemctl" "$idle_test_root/bin/hypridle"
timeout 20s dbus-run-session quickshell -p "$PWD/session-lock-smoke.qml" --no-color > "$idle_test_root/log" 2>&1 || { cat "$idle_test_root/log"; exit 1; }
cat "$idle_test_root/log"
rg -q 'SESSION LOCK PASS' "$idle_test_root/log"
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|ERROR qml:|SESSION LOCK FAIL|Cannot open:.*assets/lucide' "$idle_test_root/log"; then exit 1; fi
