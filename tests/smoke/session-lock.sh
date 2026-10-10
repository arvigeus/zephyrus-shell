#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
export XDG_RUNTIME_DIR="$SMOKE_ROOT/runtime" HYPRLAND_INSTANCE_SIGNATURE=fixture-session
export ZEPHYRUS_IDLE_PROFILE="$XDG_RUNTIME_DIR/zephyrus-shell/idle-fixture-session/hypridle.conf"
export ZEPHYRUS_IDLE_LAUNCHER="$PWD/scripts/idle.py"
mkdir -p "$XDG_RUNTIME_DIR" "$SMOKE_ROOT/bin"
chmod 700 "$XDG_RUNTIME_DIR"
python3 - <<'PYCONFIG'
import os
from pathlib import Path
(Path(os.environ["XDG_CONFIG_HOME"]) / "zephyrus-shell/theme.json").write_text('{"mode":"light"}')
PYCONFIG
export PATH="$SMOKE_ROOT/bin:$PATH"
# Exercise real policy changes and the service entry point while isolating
# service restarts and hardware actions from the user's desktop.
cat > "$SMOKE_ROOT/bin/systemctl" <<'SH'
#!/bin/sh
exec python3 "$ZEPHYRUS_IDLE_LAUNCHER" run
SH
cat > "$SMOKE_ROOT/bin/hypridle" <<'SH'
#!/bin/sh
test "$1" = --config && test -s "$2"
SH
chmod +x "$SMOKE_ROOT/bin/systemctl" "$SMOKE_ROOT/bin/hypridle"
run_smoke session-lock "SESSION LOCK" 20s
