#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
export ZEPHYRUS_PREVIEW_CAPTURE=1
log="$SMOKE_ROOT/preview.log"
timeout 45s dbus-run-session quickshell -p "$PWD/preview.qml" --no-color >"$log" 2>&1 || { cat "$log"; exit 1; }
cat "$log"
for step in {0..11}; do
    rg -q "CAPTURE .*preview-$step.png true" "$log"
    test -s "tests/artifacts/preview-$step.png"
done
if rg "$SMOKE_ERRORS" "$log" >&2; then exit 1; fi
