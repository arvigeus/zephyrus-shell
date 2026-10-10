#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
for phase in write read; do
    APPS_TEST_PHASE="$phase" run_smoke apps "APPS" 15s
    rg -q "APPS PASS $phase" "$SMOKE_ROOT/apps.log"
done
