#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
offline
run_smoke workers "WORKER" 15s
