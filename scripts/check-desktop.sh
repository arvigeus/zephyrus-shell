#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
command -v cliphist >/dev/null || { printf 'check-desktop.sh requires cliphist\n' >&2; exit 1; }
desktop_test_root=$(mktemp -d)
trap 'rm -rf -- "$desktop_test_root"' EXIT
export XDG_CONFIG_HOME="$desktop_test_root/config" XDG_DATA_HOME="$desktop_test_root/data" XDG_CACHE_HOME="$desktop_test_root/cache" XDG_STATE_HOME="$desktop_test_root/state"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
printf 'Fixture first entry' | cliphist store
printf 'Fixture second entry' | cliphist store
# Exercise the real history backend without changing the desktop clipboard.
mkdir -p "$desktop_test_root/bin" tests/artifacts
cat > "$desktop_test_root/bin/wl-copy" <<'PY'
#!/usr/bin/env python3
import os
from pathlib import Path
import sys
import time
capture = Path(os.environ['ZEPHYRUS_COPY_CAPTURE'])
capture.write_bytes(sys.stdin.buffer.read())
# Reproduce wl-copy's background owner retaining stdout/stderr after its
# parent exits. Copy must settle and close the popover while this is alive.
if os.fork() == 0:
    deadline = time.monotonic() + 20
    while capture.parent.exists() and time.monotonic() < deadline:
        time.sleep(0.05)
    os._exit(0)
os._exit(0)
PY
chmod +x "$desktop_test_root/bin/wl-copy"
export ZEPHYRUS_COPY_CAPTURE="$desktop_test_root/copied"
export PATH="$desktop_test_root/bin:$PATH"
timeout 18s dbus-run-session quickshell -p "$PWD/desktop-smoke.qml" --no-color > "$desktop_test_root/log" 2>&1 || { cat "$desktop_test_root/log"; exit 1; }
cat "$desktop_test_root/log"
rg -q 'DESKTOP PASS' "$desktop_test_root/log"
test "$(cat "$desktop_test_root/copied")" = 'Fixture second entry'
test -s tests/artifacts/desktop-clipboard.png
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|ERROR|DESKTOP FAIL|Cannot open:.*assets/lucide' "$desktop_test_root/log"; then exit 1; fi
