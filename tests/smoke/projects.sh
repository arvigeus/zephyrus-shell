#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
export XDG_PROJECTS_DIR="$SMOKE_ROOT/projects"
mkdir -p "$XDG_PROJECTS_DIR/fixture"
printf '[package]\nname = "fixture"\n' > "$XDG_PROJECTS_DIR/fixture/Cargo.toml"
run_smoke projects "PROJECT DIALOGS" 20s
