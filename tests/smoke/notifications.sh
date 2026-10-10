#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
run_smoke notifications "NOTIFICATIONS" 15s
test -s tests/artifacts/notification-popup.png
test -s tests/artifacts/activity-popup.png
