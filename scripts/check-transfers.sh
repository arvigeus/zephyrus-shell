#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
transfer_test_root=$(mktemp -d "$PWD/tests/.transfers-XXXXXX")
transfer_fixture_pid=""
cleanup_transfers() {
    if [[ -n "$transfer_fixture_pid" ]]; then kill "$transfer_fixture_pid" 2>/dev/null || true; wait "$transfer_fixture_pid" 2>/dev/null || true; fi
    rm -rf -- "$transfer_test_root"
}
trap cleanup_transfers EXIT
export ZEPHYRUS_TRANSFER_FIXTURE="$transfer_test_root/fixture" XDG_CONFIG_HOME="$transfer_test_root/config" XDG_DATA_HOME="$transfer_test_root/data" XDG_CACHE_HOME="$transfer_test_root/cache"
export XDG_MUSIC_DIR="$transfer_test_root/music"
export QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
mkdir -p "$ZEPHYRUS_TRANSFER_FIXTURE/target" "$XDG_CONFIG_HOME/zephyrus-shell" tests/artifacts
python3 - <<'PY'
import os
from pathlib import Path
(Path(os.environ['ZEPHYRUS_TRANSFER_FIXTURE'])/'source.txt').write_bytes(b'fixture\n' * 1024 * 1024)
PY
export https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9
unset ALL_PROXY all_proxy
export NO_PROXY=127.0.0.1,localhost no_proxy=127.0.0.1,localhost
python3 tests/fixtures/music-download.py > "$transfer_test_root/fixture-log" 2>&1 &
transfer_fixture_pid=$!
for attempt in {1..50}; do
    [[ -f "$XDG_CONFIG_HOME/zephyrus-shell/music.json" ]] && break
    sleep 0.1
done
[[ -f "$XDG_CONFIG_HOME/zephyrus-shell/music.json" ]]
timeout 30s dbus-run-session quickshell -p "$PWD/transfers-smoke.qml" --no-color > "$transfer_test_root/log" 2>&1 || { cat "$transfer_test_root/log"; exit 1; }
cat "$transfer_test_root/log"
rg -q 'TRANSFERS PASS' "$transfer_test_root/log"
if rg -q 'ReferenceError|TypeError|Cannot assign|Binding loop|Unable to assign|TRANSFERS FAIL|Cannot open:' "$transfer_test_root/log"; then exit 1; fi
cmp "$ZEPHYRUS_TRANSFER_FIXTURE/source.txt" "$ZEPHYRUS_TRANSFER_FIXTURE/target/source.txt"

python3 - <<'PY'
import os
from pathlib import Path
saved = list(Path(os.environ['XDG_MUSIC_DIR']).glob('*.mka'))
assert len(saved) == 1 and saved[0].stat().st_size > 0, 'Music did not save the stream'
assert not list(Path(os.environ['XDG_MUSIC_DIR']).glob('.zephyrus-*')), 'Partial Music output was left behind'
PY
