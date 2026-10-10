#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
run_smoke tray "TRAY CONTROLS" 15s "ERROR|Cannot display PlatformMenuEntry"
