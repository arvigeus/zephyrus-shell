#!/usr/bin/env python3
"""Capture from Hyprland into XDG Pictures/Screenshots and the clipboard."""
import argparse
from datetime import datetime
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def capture(mode, *, dismiss=True):
    if mode not in ("region", "window", "output"):
        raise ValueError("Choose area, window or screen capture.")
    executable = shutil.which("hyprshot")
    if not executable:
        raise ValueError("Install hyprshot to take screenshots.")
    if dismiss:
        subprocess.run(["quickshell", "-p", str(ROOT), "ipc", "call", "shell", "desktop"],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        time.sleep(0.35)
    result = subprocess.run(["xdg-user-dir", "PICTURES"], capture_output=True, text=True, timeout=5)
    pictures = Path(result.stdout.strip()) if result.returncode == 0 and result.stdout.strip() else Path.home() / "Pictures"
    folder = pictures / "Screenshots"
    folder.mkdir(parents=True, exist_ok=True)
    filename = "Screenshot-" + datetime.now().strftime("%Y-%m-%d-%H%M%S-%f") + ".png"
    command = [executable, "-m", mode, "-o", str(folder), "-f", filename]
    # Screen capture uses the active output. Window capture lets you point at
    # another app after dismissing an overlay that may have held focus.
    if mode == "output": command += ["-m", "active"]
    result = subprocess.run(command, timeout=180)
    return folder / filename if result.returncode == 0 else None


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("region", "window", "output"))
    args = parser.parse_args()
    try:
        capture(args.mode)
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        if shutil.which("notify-send"):
            subprocess.run(["notify-send", "--app-name=Zephyrus", "Screenshot", str(error)], timeout=5)
        print(str(error), file=sys.stderr)
        sys.exit(1)
