#!/usr/bin/env python3
"""Run a configured input-language provider, or use Hyprland's XKB layouts."""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def provider_command():
    config = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config")))
    path = config / "zephyrus-shell/input-language.json"
    if not path.exists():
        return None
    settings = json.loads(path.read_text())
    command = settings.get("command") if isinstance(settings, dict) else None
    if (
        not isinstance(command, list)
        or not command
        or not all(isinstance(arg, str) and arg for arg in command)
    ):
        raise ValueError("Input language command must be a nonempty array of strings.")
    return command if shutil.which(command[0]) else None


def main():
    args = sys.argv[1:] or ["status"]
    if args[0] not in ("status", "select"):
        raise ValueError("Input language action must be status or select.")
    if args[0] == "select" and (len(args) != 2 or args[1] not in ("en", "bg", "vi")):
        raise ValueError("Input language selection must be en, bg or vi.")
    command = provider_command()
    if command:
        os.execvp(command[0], [*command, *args])
    if args[0] == "select":
        if args[1] == "vi":
            raise ValueError("Vietnamese input is unavailable.")
        subprocess.run(
            [
                "timeout",
                "--foreground",
                "10s",
                "hyprctl",
                "switchxkblayout",
                "all",
                "1" if args[1] == "bg" else "0",
            ],
            check=True,
            stdout=subprocess.DEVNULL,
        )
    # The UI uses the keyboard from the latest layout event. Reading devices
    # neither starts an input daemon nor needs an external provider.
    os.execvp("timeout", ["timeout", "--foreground", "10s", "hyprctl", "-j", "devices"])


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(json.dumps({"available": False, "error": str(error)}))
        sys.exit(1)
