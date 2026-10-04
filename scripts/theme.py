#!/usr/bin/env python3
"""Read, apply or restore Zephyrus appearance. All paths honor XDG variables."""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import shutil
import subprocess

from services.theme import (
    Synchronizer,
    atomic_write,
    effective,
    load,
    locations,
    notify,
    run,
    source,
)


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
        root = Path(__file__).resolve().parents[1]
        content = (
            "// Generated from config/theme.json. Regenerate with scripts/theme.py defaults.\n"
            ".pragma library\nvar settings = "
            + (root / "config/theme.json").read_text().strip()
            + ";\n"
        )
        atomic_write(root / "core/theme/Defaults.js", content, 0o644)
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
            theme["mode"] = args.mode
            atomic_write(source(config), json.dumps(theme, indent=2) + "\n")
        changed, warnings = [], []
        if args.action == "apply" and theme["sync_desktop"]:
            flatpak_ids = []
            if not args.no_notify and shutil.which("flatpak"):
                try:
                    flatpak_ids = run(
                        ["flatpak", "list", "--app", "--columns=application"]
                    ).splitlines()
                except (OSError, ValueError, subprocess.TimeoutExpired) as error:
                    warnings.append("Flatpak theme access: " + str(error))
            changed = sync.apply(theme, flatpak_ids)
            if not source(config).exists():
                atomic_write(source(config), json.dumps(theme, indent=2) + "\n")
            if not args.no_notify:
                warnings.extend(notify(theme, sync))
        print(json.dumps({"theme": effective(theme), "changed": changed, "warnings": warnings}))
    except (OSError, ValueError) as error:
        print(json.dumps({"error": str(error)}))
        sys.exit(1)


if __name__ == "__main__":
    main()
