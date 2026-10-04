#!/usr/bin/env python3
"""Explicit host setup for Zephyrus hardware controls."""

import argparse
import os
import pwd
import subprocess
import sys
from pathlib import Path


def configure_ddc(
    username, root=Path("/"), runner=subprocess.run, user_lookup=pwd.getpwnam, effective_uid=None
):
    if (os.geteuid() if effective_uid is None else effective_uid) != 0:
        raise PermissionError("configure-ddc must run as root")
    try:
        user_lookup(username)
    except KeyError as error:
        raise ValueError(f"Unknown user: {username}") from error

    modules_load = Path(root) / "etc/modules-load.d/zephyrus-ddc.conf"
    modules_load.parent.mkdir(parents=True, exist_ok=True)
    if not modules_load.exists() or modules_load.read_text() != "i2c-dev\n":
        temporary = modules_load.with_suffix(".conf.zephyrus-tmp")
        temporary.write_text("i2c-dev\n")
        temporary.replace(modules_load)

    runner(["modprobe", "i2c-dev"], check=True)
    if runner(["getent", "group", "i2c"], check=False, capture_output=True).returncode:
        runner(["groupadd", "--system", "i2c"], check=True)
    runner(["usermod", "--append", "--groups", "i2c", username], check=True)
    runner(["udevadm", "control", "--reload-rules"], check=True)
    runner(["udevadm", "trigger", "--subsystem-match=i2c-dev"], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)
    ddc = subparsers.add_parser("configure-ddc")
    ddc.add_argument("--user", required=True)
    args = parser.parse_args()
    try:
        if args.action == "configure-ddc":
            configure_ddc(args.user)
    except (OSError, PermissionError, ValueError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
