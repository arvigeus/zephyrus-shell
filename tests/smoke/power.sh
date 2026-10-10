#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
run_smoke power "POWER" 15s
test -s tests/artifacts/battery-details.png
