#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
run_smoke actions "ACTION CONTROLS" 15s "ERROR"
