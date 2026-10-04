"""Session-scoped automatic locking, using the existing hypridle service."""

import fcntl
import os
import re
import subprocess
from pathlib import Path

from services.storage import atomic_write

ROOT = Path(__file__).resolve().parents[1]


def session_directory():
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    instance = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if not runtime or not re.fullmatch(r"[A-Za-z0-9_.-]+", instance):
        return None
    return Path(runtime) / "zephyrus-shell" / ("idle-" + instance)


def state():
    directory = session_directory()
    return {
        "available": directory is not None,
        "paused": bool(directory and (directory / "unlocked").exists()),
    }


def configuration(paused):
    content = (ROOT / "hyprland/hypridle.conf").read_text()
    if not paused:
        return content
    # Keep the shared blank/wake and explicit lock commands. Only automatic
    # locking and timed suspend are omitted while this session is unlocked.
    content = re.sub(r"^\s*before_sleep_cmd = .*\n", "", content, flags=re.M)
    content = content.replace("inhibit_sleep = 3", "inhibit_sleep = 1")

    def listener(match):
        block = match.group()
        return (
            ""
            if (
                "on-timeout = loginctl lock-session" in block
                or "on-timeout = systemctl --check-inhibitors=yes suspend" in block
            )
            else block
        )

    return re.sub(r"^listener \{\n.*?^\}\n", listener, content, flags=re.M | re.S)


def set_paused(paused):
    directory = session_directory()
    if directory is None:
        raise ValueError("Automatic locking requires a Hyprland session.")
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    marker = directory / "unlocked"
    with (directory / "policy.lock").open("a") as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        previous = marker.exists()
        if paused:
            atomic_write(marker, "Session-only automatic lock pause\n")
        else:
            marker.unlink(missing_ok=True)
        try:
            subprocess.run(
                ["systemctl", "--user", "restart", "hypridle.service"],
                check=True,
                capture_output=True,
                text=True,
                timeout=15,
            )
        except (OSError, subprocess.SubprocessError) as error:
            if previous:
                atomic_write(marker, "Session-only automatic lock pause\n")
            else:
                marker.unlink(missing_ok=True)
            # A restart may have stopped the old process before failing.
            try:
                subprocess.run(
                    ["systemctl", "--user", "restart", "hypridle.service"],
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=15,
                )
            except (OSError, subprocess.SubprocessError):
                pass
            raise ValueError("Could not change automatic locking: " + str(error)) from error
    return state()


def run_idle():
    directory = session_directory()
    if directory is None:
        raise ValueError("hypridle requires the Hyprland session environment.")
    path = directory / "hypridle.conf"
    atomic_write(path, configuration(state()["paused"]))
    os.execvp("hypridle", ["hypridle", "--config", str(path)])


def lock_on_lid():
    if not state()["paused"]:
        subprocess.run(["loginctl", "lock-session"], check=True, timeout=8)
