#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
command -v cliphist >/dev/null || { printf 'desktop smoke check requires cliphist\n' >&2; exit 1; }
printf 'Fixture first entry' | cliphist store
printf 'Fixture second entry' | cliphist store
# Exercise the real history backend without changing the desktop clipboard.
mkdir -p "$SMOKE_ROOT/bin"
cat > "$SMOKE_ROOT/bin/wl-copy" <<'PY'
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
chmod +x "$SMOKE_ROOT/bin/wl-copy"
export ZEPHYRUS_COPY_CAPTURE="$SMOKE_ROOT/copied"
export PATH="$SMOKE_ROOT/bin:$PATH"
run_smoke desktop "DESKTOP" 18s "ERROR"
test "$(cat "$SMOKE_ROOT/copied")" = 'Fixture second entry'
test -s tests/artifacts/desktop-clipboard.png
