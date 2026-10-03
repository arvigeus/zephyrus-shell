#!/usr/bin/env python3
"""Capture from Hyprland into XDG Pictures/Screenshots and the clipboard."""
import argparse
from datetime import datetime
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def dismiss_shell():
    subprocess.run(["quickshell", "-p", str(ROOT), "ipc", "call", "shell", "desktop"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
    time.sleep(0.35)


def report_error(title, error):
    if shutil.which("notify-send"):
        subprocess.run(["notify-send", "--app-name=Zephyrus", title, str(error)], timeout=5)
    print(str(error), file=sys.stderr)


def capture(mode, *, dismiss=True, edit=False, active=False):
    if mode not in ("region", "window", "output"):
        raise ValueError("Choose area, window or screen capture.")
    executable = shutil.which("hyprshot")
    if not executable:
        raise ValueError("Install hyprshot to take screenshots.")
    editor = shutil.which("satty") if edit else None
    if edit and not editor:
        raise ValueError("Install satty to annotate screenshots.")
    if active and mode != "window":
        raise ValueError("Active selection is only needed for window capture.")
    if dismiss:
        dismiss_shell()
    result = subprocess.run(["xdg-user-dir", "PICTURES"], capture_output=True, text=True, timeout=5)
    pictures = Path(result.stdout.strip()) if result.returncode == 0 and result.stdout.strip() else Path.home() / "Pictures"
    folder = pictures / "Screenshots"
    folder.mkdir(parents=True, exist_ok=True)
    filename = "Screenshot-" + datetime.now().strftime("%Y-%m-%d-%H%M%S-%f") + ".png"
    command = [executable, "-m", mode, "-o", str(folder), "-f", filename]
    if mode == "output" or active:
        command += ["-m", "active"]
    if edit:
        command += ["--silent"]
    result = subprocess.run(command, timeout=180)
    if result.returncode != 0:
        return None
    image = folder / filename
    if not image.is_file():
        return None
    if editor:
        # Replace the detached helper: the editor outlives any shell surface.
        os.execv(editor, [editor, "--config", str(ROOT / "config/satty.toml"),
                          "--filename", str(image), "--output-filename", str(image)])
    return image


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("region", "window", "output"))
    parser.add_argument("--edit", action="store_true", help="Open the capture in Satty")
    parser.add_argument("--active", action="store_true", help="Capture the active window without selection")
    args = parser.parse_args()
    try:
        capture(args.mode, edit=args.edit, active=args.active)
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        report_error("Screenshot", error)
        sys.exit(1)
