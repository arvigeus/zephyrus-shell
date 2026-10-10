#!/usr/bin/env python3
"""Read, apply or restore Zephyrus appearance. All paths honor XDG variables."""

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from services.storage import atomic_write
from services.theme import DEFAULTS, Synchronizer, effective, load, locations, notify, run, source


def write_defaults():
    content = (
        "// Generated from config/theme.json. Regenerate with scripts/theme.py defaults.\n"
        ".pragma library\nvar settings = " + DEFAULTS.read_text().strip() + ";\n"
    )
    atomic_write(ROOT / "core/theme/Defaults.js", content, 0o644)


def set_mode(config, mode):
    # Store only the choice; unchanged defaults keep following config/theme.json.
    path = source(config)
    overrides = json.loads(path.read_text()) if path.exists() else {}
    overrides["mode"] = mode
    atomic_write(path, json.dumps(overrides, indent=2) + "\n")


def flatpak_apps(warnings):
    if not shutil.which("flatpak"):
        return []
    try:
        return run(["flatpak", "list", "--app", "--columns=application"]).splitlines()
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        warnings.append("Flatpak theme access: " + str(error))
        return []


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("get", "apply", "restore", "set-mode", "defaults"))
    parser.add_argument("mode", choices=("dark", "light"), nargs="?")
    parser.add_argument(
        "--no-notify",
        action="store_true",
        help="Generate files without contacting desktop services",
    )
    args = parser.parse_args()
    if args.action == "defaults":
        write_defaults()
        return
    config, data, state = locations()
    sync = Synchronizer(config, data, state)
    try:
        if args.action == "restore":
            print(json.dumps({"warnings": sync.restore()}))
            return
        theme = load(config)
        if args.action == "set-mode":
            if not args.mode:
                raise ValueError("set-mode requires dark or light")
            set_mode(config, args.mode)
            theme["mode"] = args.mode
        changed, warnings = [], []
        if args.action == "apply" and theme["sync_desktop"]:
            flatpak_ids = [] if args.no_notify else flatpak_apps(warnings)
            changed = sync.apply(theme, flatpak_ids)
            if not args.no_notify:
                warnings.extend(notify(theme, sync))
        print(json.dumps({"theme": effective(theme), "changed": changed, "warnings": warnings}))
    except (OSError, ValueError) as error:
        print(json.dumps({"error": str(error)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
