#!/usr/bin/env python3
"""Test real keyboard delivery in a temporary nested Hyprland session."""

import argparse
import json
import os
import signal
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def stop(process):
    if process is None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--window-controls",
        action="store_true",
        help="Exercise native window controls and screen removal",
    )
    args = parser.parse_args()
    fixture = "window-controls-smoke.qml" if args.window_controls else "focus-smoke.qml"
    marker = "WINDOW CONTROLS PASS" if args.window_controls else "FOCUS PASS"
    parent_display = os.environ.get("WAYLAND_DISPLAY")
    if not parent_display:
        raise SystemExit("A parent Wayland session is required for the isolated compositor.")
    if not parent_display.startswith("/"):
        parent_display = str(Path(os.environ["XDG_RUNTIME_DIR"]) / parent_display)
    # Hyprland's IPC socket includes a long instance signature; keep this path short.
    with tempfile.TemporaryDirectory(prefix="zf-") as directory:
        temporary = Path(directory)
        temporary.chmod(0o700)
        keyboard = temporary / "keyboard"
        flags = subprocess.check_output(
            ["pkg-config", "--cflags", "--libs", "wayland-client", "xkbcommon"], text=True
        ).split()
        subprocess.run(
            [
                "cc",
                "-Wall",
                "-Wextra",
                "-Werror",
                str(ROOT / "tests/native/keyboard.c"),
                "-o",
                str(keyboard),
                *flags,
            ],
            check=True,
        )
        config = temporary / "hyprland.lua"
        config.write_text(
            "hl.monitor({output='', mode='1280x800@60', position='auto', scale=1})\n"
            "hl.config({animations={enabled=false}, input={follow_mouse=2}, "
            "misc={disable_hyprland_logo=true, disable_splash_rendering=true}, "
            "ecosystem={enforce_permissions=false}})\n"
            + "dofile("
            + json.dumps(str(ROOT / "hyprland/windows.lua"))
            + ")\n"
        )
        env = dict(os.environ)
        env.update(
            XDG_RUNTIME_DIR=directory,
            XDG_CONFIG_HOME=str(temporary / "config"),
            XDG_DATA_HOME=str(temporary / "data"),
            XDG_STATE_HOME=str(temporary / "state"),
            XDG_CACHE_HOME=str(temporary / "cache"),
            XDG_CONFIG_DIRS=str(temporary / "empty"),
            XDG_DATA_DIRS=str(temporary / "empty"),
            WAYLAND_DISPLAY=parent_display,
            AQ_DRM_DEVICES="/dev/null",
            QT_QPA_PLATFORM="wayland",
            QT_NO_XDG_DESKTOP_PORTAL="1",
            DBUS_SESSION_BUS_ADDRESS="unix:path=" + str(temporary / "no-session-bus"),
            DBUS_SYSTEM_BUS_ADDRESS="unix:path=" + str(temporary / "no-system-bus"),
            https_proxy="http://127.0.0.1:9",
            http_proxy="http://127.0.0.1:9",
            ZEPHYRUS_FOCUS_INPUT=str(keyboard),
        )
        for key in (
            "HYPRLAND_INSTANCE_SIGNATURE",
            "ALL_PROXY",
            "all_proxy",
            "NO_PROXY",
            "no_proxy",
        ):
            env.pop(key, None)
        compositor = shell = None
        try:
            with (temporary / "compositor.log").open("w") as log:
                compositor = subprocess.Popen(
                    ["Hyprland", "-c", str(config)],
                    env=env,
                    stdout=log,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
                deadline = time.monotonic() + 15
                while time.monotonic() < deadline and compositor.poll() is None:
                    instances = list((temporary / "hypr").glob("*/.socket.sock"))
                    sockets = [path for path in temporary.glob("wayland-*") if path.is_socket()]
                    if instances and sockets:
                        break
                    time.sleep(0.1)
                else:
                    raise RuntimeError(
                        "Test compositor did not start:\n"
                        + (temporary / "compositor.log").read_text()
                    )
                env["HYPRLAND_INSTANCE_SIGNATURE"] = instances[0].parent.name
                env["WAYLAND_DISPLAY"] = sockets[0].name
                subprocess.run(
                    [
                        "hyprctl",
                        "output",
                        "create",
                        "headless",
                        "ZEPHYRUS-TEST" if args.window_controls else "ZEPHYRUS-FOCUS",
                    ],
                    env=env,
                    check=True,
                    capture_output=True,
                )
                with (temporary / "shell.log").open("w") as output:
                    shell = subprocess.Popen(
                        [
                            "dbus-run-session",
                            "--",
                            "quickshell",
                            "-p",
                            str(ROOT / fixture),
                            "--no-color",
                        ],
                        env=env,
                        cwd=ROOT,
                        stdout=output,
                        stderr=subprocess.STDOUT,
                        start_new_session=True,
                    )
                    shell.wait(timeout=60)
                content = (temporary / "shell.log").read_text()
                if (
                    shell.returncode
                    or marker not in content
                    or any(
                        error in content
                        for error in (
                            "FOCUS FAIL",
                            "WINDOW CONTROLS FAIL",
                            "ReferenceError",
                            "TypeError",
                            "Binding loop",
                            "Cannot assign",
                        )
                    )
                ):
                    raise RuntimeError(content)
                print(next(line for line in content.splitlines() if marker in line))
        finally:
            stop(shell)
            stop(compositor)


if __name__ == "__main__":
    main()
