#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
export ZEPHYRUS_THEME_NO_NOTIFY=1
run_smoke theme "THEME"
# A second process uses the persisted light selection, like a new login.
ZEPHYRUS_THEME_COLD_LIGHT=1 run_smoke theme "THEME"
