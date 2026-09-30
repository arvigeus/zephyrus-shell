#!/usr/bin/env python3
"""Own Zephyrus/idle children for one compositor, including crash cleanup."""

import fcntl
import os
from pathlib import Path
import select
import signal
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from services.wallpaper import sync_lock_background
ENVIRONMENT = ("WAYLAND_DISPLAY", "DISPLAY", "XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP",
               "XDG_SESSION_TYPE", "HYPRLAND_INSTANCE_SIGNATURE", "XDG_CONFIG_HOME",
               "XDG_DATA_HOME", "XDG_CACHE_HOME", "PATH", "QT_QPA_PLATFORM")
PORTALS = ("xdg-desktop-portal-hyprland.service", "xdg-desktop-portal-gtk.service",
           "xdg-desktop-portal.service")


def systemctl(*args, check=True):
    return subprocess.run(["systemctl", "--user", *args], check=check,
                          stdout=subprocess.DEVNULL, timeout=20)


def stop_child(child):
    if child.poll() is not None:
        return
    os.killpg(child.pid, signal.SIGTERM)
    try:
        child.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(child.pid, signal.SIGKILL)
        child.wait()


def run():
    config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    os.environ["ZEPHYRUS_LOCK_WALLPAPER"] = str(config / "zephyrus-shell/lock-wallpaper")
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    if not signature or not os.environ.get("WAYLAND_DISPLAY"):
        raise RuntimeError("Start the session supervisor from Hyprland.")
    try:
        sync_lock_background(config)
    except OSError as error:
        print("Could not synchronize the lock wallpaper: " + str(error), file=sys.stderr)
    runtime = Path(os.environ["XDG_RUNTIME_DIR"])
    with (runtime / ("zephyrus-" + signature + ".lock")).open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        # Established before any children, so compositor exit cannot be missed.
        with socket.socket(socket.AF_UNIX) as events:
            events.connect(str(runtime / "hypr" / signature / ".socket2.sock"))
            systemctl("import-environment", *[key for key in ENVIRONMENT if key in os.environ])
            subprocess.run(["dbus-update-activation-environment", "--systemd",
                            *[key for key in ENVIRONMENT if key in os.environ]], check=True, timeout=20)
            children = []
            polkit_owned = systemctl("is-active", "--quiet", "hyprpolkitagent.service", check=False).returncode != 0
            try:
                systemctl("start", "pipewire.socket", "pipewire-pulse.socket", "wireplumber.service")
                if polkit_owned:
                    systemctl("start", "hyprpolkitagent.service")
                # Clear stale activation from another desktop on this user bus.
                systemctl("restart", *PORTALS)
                commands = (["hypridle", "-c", str(ROOT / "hyprland/hypridle.conf")],
                            ["quickshell", "-n", "-p", str(ROOT)])
                restart_after = [0.0, 0.0]
                for command in commands:
                    children.append(subprocess.Popen(command, start_new_session=True))
                while True:
                    ready, _, _ = select.select([events], [], [], 1)
                    if ready and not events.recv(65536):
                        break
                    for index, child in enumerate(children):
                        if child.poll() is None:
                            continue
                        if not restart_after[index]:
                            print(commands[index][0] + " exited; restarting in three seconds.", file=sys.stderr)
                            restart_after[index] = time.monotonic() + 3
                        elif time.monotonic() >= restart_after[index]:
                            children[index] = subprocess.Popen(commands[index], start_new_session=True)
                            restart_after[index] = 0.0
            finally:
                for child in reversed(children):
                    stop_child(child)
                if polkit_owned:
                    systemctl("stop", "hyprpolkitagent.service", check=False)
                systemctl("stop", *PORTALS, check=False)
                systemctl("unset-environment", "WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE",
                          "XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP", "XDG_SESSION_TYPE", check=False)


if __name__ == "__main__":
    log_directory = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "zephyrus-shell"
    log_directory.mkdir(parents=True, exist_ok=True)
    log_path = log_directory / "session.log"
    if log_path.exists():
        log_path.replace(log_directory / "session.previous.log")
    descriptor = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    os.fchmod(descriptor, 0o600)
    os.dup2(descriptor, 1)
    os.dup2(descriptor, 2)
    os.close(descriptor)
    def terminate(_signum, _frame):
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, terminate)
    try:
        run()
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print("Zephyrus session startup failed: " + str(error), file=sys.stderr)
        sys.exit(1)
