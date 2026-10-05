#!/usr/bin/env python3
"""On-demand consumer WARP control, shared by terminals and desktop shells."""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time

UNIT = "zephyrus-warp.service"
LAN_RANGES = (
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "169.254.0.0/16",
    "fc00::/7",
    "fe80::/10",
    "224.0.0.0/4",
    "ff00::/8",
    "255.255.255.255/32",
)


def run(args, timeout=10):
    return subprocess.run(
        args,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
        env={**os.environ, "LC_ALL": "C"},
    )


def checked(result):
    if result.returncode:
        raise RuntimeError((result.stderr or result.stdout).strip() or "Command failed")
    return result.stdout.strip()


def cli(*args):
    return run(["warp-cli", "--accept-tos", "--no-ansi", "--no-paginate", *args])


def prepare():
    if os.geteuid() != 0:
        raise RuntimeError("--prepare is an internal root-only service action")
    # A running daemon process does not guarantee its IPC socket is ready.
    deadline = time.monotonic() + 15
    while True:
        result = cli("--json", "status")
        data = json.loads(result.stdout or result.stderr or "{}")
        if data.get("code") != "FailedToConnectToDaemon":
            break
        if time.monotonic() >= deadline:
            raise RuntimeError("WARP daemon did not become ready")
        time.sleep(0.3)

    registration = cli("--json", "registration", "show")
    if registration.returncode:
        data = json.loads(registration.stdout or registration.stderr or "{}")
        if data.get("code") != "MissingRegistration":
            checked(registration)
        checked(cli("registration", "new"))

    # Registration precedes settings. Existing registration/account identity
    # survives rebuilds; no API failure is interpreted as a missing identity.
    checked(cli("mode", "warp+doh"))
    exclusions = checked(cli("tunnel", "ip", "list"))
    existing = set(re.findall(r"[\da-fA-F:.]+/\d+", exclusions))
    for subnet in LAN_RANGES:
        if subnet not in existing:
            addition = cli("--json", "tunnel", "ip", "add-range", subnet)
            if addition.returncode:
                try:
                    code = json.loads(addition.stdout or addition.stderr).get("code")
                except ValueError:
                    code = None
                # Some client versions display a host exclusion without /32
                # or /128. Let the daemon confirm duplicates in that case.
                if code != "AlreadyExists":
                    checked(addition)
    checked(cli("connect"))


def unit_state(unit):
    return checked(run(["systemctl", "show", "--property=ActiveState", "--value", unit]))


def status():
    if not shutil.which("warp-cli"):
        return {
            "available": False,
            "state": "unavailable",
            "enabled": False,
            "message": "WARP is not installed",
        }
    state = unit_state(UNIT)
    daemon = unit_state("warp-svc.service")
    enabled = state in ("active", "activating", "reloading")
    if state == "activating":
        return {
            "available": True,
            "state": "connecting",
            "enabled": True,
            "message": "Setting up WARP…",
        }
    if state == "deactivating" or daemon == "deactivating":
        return {
            "available": True,
            "state": "disconnecting",
            "enabled": False,
            "message": "Stopping WARP…",
        }
    if daemon not in ("active", "activating", "reloading"):
        return {
            "available": True,
            "state": "off",
            "enabled": False,
            "message": "Off · daemon stopped",
        }
    result = cli("status")
    checked(result)
    output = (result.stdout or result.stderr).strip()
    connection = connection_state(output)
    if connection is None:
        raise RuntimeError("Unrecognized WARP status: " + output)
    return {
        "available": True,
        "state": connection,
        "enabled": enabled or connection in ("connected", "connecting"),
        "message": output,
    }


def connection_state(output):
    match = re.search(r"^Status update:\s*(\w+)", output, re.MULTILINE)
    state = match.group(1).lower() if match else None
    return (
        state
        if state in ("connected", "connecting", "disconnected", "disconnecting", "unable", "error")
        else None
    )


def action(name):
    if name == "toggle":
        name = "disconnect" if status()["enabled"] else "connect"
    if name in ("connect", "disconnect"):
        verb = "start" if name == "connect" else "stop"
        result = run(["systemctl", "--no-ask-password", verb, UNIT], timeout=90)
        if result.returncode:
            raise RuntimeError(
                (result.stderr or result.stdout).strip()
                + "\nDetails: journalctl -u zephyrus-warp.service -b --no-pager"
            )
    return status()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        nargs="?",
        default="status",
        choices=("connect", "disconnect", "toggle", "status", "watch", "setup"),
    )
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--prepare", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--user", help="Desktop account authorized by setup")
    parser.add_argument(
        "--offline", action="store_true", help="Provision without a running systemd"
    )
    args = parser.parse_args()
    try:
        if args.prepare:
            prepare()
            return 0
        if args.command == "watch":
            from warp_watch import watch

            watch()
            return 0
        if args.command == "setup":
            from warp_setup import configure

            if not args.user:
                raise ValueError("setup requires --user")
            configure(args.user, args.offline)
            result = {"ok": True, "message": "WARP setup complete; daemon remains off"}
        else:
            result = {"ok": True, **action(args.command)}
    except (
        OSError,
        RuntimeError,
        subprocess.TimeoutExpired,
        ValueError,
        ImportError,
        subprocess.CalledProcessError,
        KeyError,
    ) as error:
        result = {"ok": False, "state": "error", "error": str(error)}
    if args.json or args.command == "watch":
        print(json.dumps(result), flush=True)
    else:
        print(result.get("error") or result["message"])
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
