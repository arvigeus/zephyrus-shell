#!/usr/bin/env python3
"""Owned WireGuard controls. NetworkManager owns tunnels after the drawer closes."""

import hashlib
import os
import pwd
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from services.worker import serve

LOCK = threading.Lock()
MAX_CONFIG_BYTES = 256 * 1024


def config_dir():
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "zephyrus-shell/vpn"


def prefix():
    identity = f"{os.getuid()}:{config_dir().absolute()}"
    return "zephyrus-wg-" + hashlib.sha256(identity.encode()).hexdigest()[:12] + "-"


def valid_name(name):
    return (
        isinstance(name, str)
        and name.endswith(".conf")
        and name != ".conf"
        and not any(character in name for character in "/\\\r\n\x00")
    )


def file_error(path):
    try:
        info = path.lstat()
    except OSError:
        return "Config file is unavailable."
    if not stat.S_ISREG(info.st_mode):
        return "Use a regular config file, not a symlink."
    if info.st_uid != os.getuid():
        return "Config file must belong to your user."
    if info.st_mode & 0o077:
        return "Private keys need a private file. Set this config's permissions to 600."
    if info.st_size > MAX_CONFIG_BYTES:
        return "Config file is too large."
    return ""


def nmcli(*args):
    try:
        result = subprocess.run(
            ["nmcli", "--wait", "30", *args],
            capture_output=True,
            text=True,
            timeout=40,
            env={**os.environ, "LC_ALL": "C"},
        )
    except FileNotFoundError:
        raise ValueError("Install NetworkManager (nmcli) to use WireGuard.") from None
    except subprocess.TimeoutExpired:
        raise ValueError(
            "NetworkManager timed out. Refresh and check the connection status."
        ) from None
    if result.returncode:
        # Import diagnostics can contain a private key or a complete config line.
        # Never send command output to QML, worker logs, or the error boundary.
        diagnostic = (result.stderr + result.stdout).lower()
        if "not authorized" in diagnostic or "permission denied" in diagnostic:
            message = "NetworkManager denied permission. Check your desktop's polkit agent."
        elif "not running" in diagnostic or "could not connect" in diagnostic:
            message = "NetworkManager is unavailable. Start it before connecting."
        else:
            message = (
                "NetworkManager could not complete the VPN action. Check the network and try again."
            )
        raise ValueError(message)
    return result.stdout.strip()


def connections():
    output = nmcli(
        "--terse", "--escape", "no", "--fields", "UUID,TYPE,ACTIVE,STATE,NAME", "connection", "show"
    )
    owned = []
    for line in output.splitlines():
        fields = line.split(":", 4)
        if len(fields) != 5:
            continue
        uuid, kind, active, state, name = fields
        filename = name.removeprefix(prefix())
        if kind != "wireguard" or not name.startswith(prefix()) or not valid_name(filename):
            continue
        if not re.fullmatch(r"[a-fA-F0-9-]{36}", uuid):
            continue
        owned.append(
            {"uuid": uuid, "filename": filename, "active": active == "yes", "state": state}
        )
    return owned


def snapshot():
    directory = config_dir()
    try:
        files = (
            {path.name: path for path in directory.iterdir() if valid_name(path.name)}
            if directory.exists()
            else {}
        )
    except OSError:
        raise ValueError("Could not read the VPN config folder.") from None
    available = bool(shutil.which("nmcli"))
    error = ""
    owned = []
    if available:
        try:
            owned = connections()
        except ValueError as exception:
            error = str(exception)
            available = False
    elif files:
        error = "Install NetworkManager (nmcli) to use WireGuard."
    # Retain a removed/renamed profile's active row so it can still be disconnected.
    names = set(files) | {entry["filename"] for entry in owned if entry["active"]}
    profiles = []
    for name in sorted(names, key=str.casefold):
        connection = next(
            (entry for entry in owned if entry["filename"] == name and entry["active"]), None
        )
        state = connection["state"] if connection else "disconnected"
        profiles.append(
            {
                "id": name,
                "name": name[:-5],
                "connected": state == "activated",
                "active": bool(connection),
                "transitioning": state in ("activating", "deactivating"),
                "status": {
                    "activated": "Connected",
                    "activating": "Connecting…",
                    "deactivating": "Disconnecting…",
                }.get(state, ""),
                "error": file_error(files[name])
                if name in files
                else "Config removed. Disconnect to remove this tunnel.",
            }
        )
    return {
        "profiles": profiles,
        "available": available,
        "error": error,
        "directory": str(directory),
    }


def read_config(path):
    # O_NOFOLLOW + fstat bind the checks to the exact file read, including replacements.
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(descriptor, "rb") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
                raise ValueError("Use a private config owned by your user, with permissions 600.")
            data = stream.read(MAX_CONFIG_BYTES + 1)
    except OSError:
        raise ValueError("Could not read the VPN config. Use a regular, readable file.") from None
    if len(data) > MAX_CONFIG_BYTES:
        raise ValueError("Config file is too large.")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        raise ValueError("WireGuard configs must be UTF-8 text.") from None
    # NetworkManager does not implement wg-quick shell hooks. Refuse rather than
    # silently dropping firewall/routing commands the config may rely on.
    if re.search(
        r"^\s*(PreUp|PostUp|PreDown|PostDown|SaveConfig|Table)\s*=",
        text,
        re.MULTILINE | re.IGNORECASE,
    ):
        raise ValueError(
            "This config uses wg-quick hooks, SaveConfig or Table. Use a NetworkManager-compatible config."
        )
    if not re.search(r"^\s*\[Interface\]\s*$", text, re.MULTILINE) or not re.search(
        r"^\s*\[Peer\]\s*$", text, re.MULTILINE
    ):
        raise ValueError("WireGuard config needs Interface and Peer sections.")
    return data


def import_profile(staged, name):
    try:
        import gi

        gi.require_version("NM", "1.0")
        from gi.repository import NM, Gio, GLib  # ty: ignore[unresolved-import]
    except (ImportError, ValueError):
        raise ValueError(
            "Install python-gobject and NetworkManager to import WireGuard configs."
        ) from None
    try:
        connection = NM.conn_wireguard_import(str(staged))
        setting = connection.get_setting_connection()
        setting.set_property("id", prefix() + name)
        setting.set_property("autoconnect", False)
        setting.add_permission("user", pwd.getpwuid(os.getuid()).pw_name, None)
        # Add settings in one operation; never expose an unrestricted or
        # autoconnect-enabled profile between an import and a later modification.
        flags = (
            NM.SettingsAddConnection2Flags.IN_MEMORY
            | NM.SettingsAddConnection2Flags.BLOCK_AUTOCONNECT
        )
        parameters = GLib.Variant.new_tuple(
            connection.to_dbus(NM.ConnectionSerializationFlags.ALL),
            GLib.Variant("u", int(flags)),
            GLib.Variant("a{sv}", {}),
        )
        bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        bus.call_sync(
            "org.freedesktop.NetworkManager",
            "/org/freedesktop/NetworkManager/Settings",
            "org.freedesktop.NetworkManager.Settings",
            "AddConnection2",
            parameters,
            GLib.VariantType.new("(oa{sv})"),
            Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION,
            30000,
            None,
        )
        return connection.get_uuid()
    except GLib.Error as exception:
        diagnostic = str(exception).lower()
        if "not authorized" in diagnostic or "permission denied" in diagnostic:
            raise ValueError(
                "NetworkManager denied permission. Check your desktop's polkit agent."
            ) from None
        raise ValueError(
            "Could not import WireGuard config. Check NetworkManager, keys, addresses and peer settings."
        ) from None


def control(name, action):
    if not valid_name(name):
        raise ValueError("Select a config from the VPN folder.")
    matches = [entry for entry in connections() if entry["filename"] == name]
    active = [entry for entry in matches if entry["active"]]
    if action == "disconnect":
        for entry in active:
            nmcli("connection", "down", "uuid", entry["uuid"])
        for entry in matches:
            nmcli("connection", "delete", "uuid", entry["uuid"])
        return snapshot()
    if active:
        return snapshot()
    path = config_dir() / name
    data = read_config(path)
    for entry in matches:
        nmcli("connection", "delete", "uuid", entry["uuid"])
    interface = "zwg" + hashlib.sha256(str(path.absolute()).encode()).hexdigest()[:12]
    with tempfile.TemporaryDirectory(prefix="zephyrus-vpn-") as temporary:
        staged = Path(temporary) / (interface + ".conf")
        staged.touch(mode=0o600)
        staged.write_bytes(data)
        uuid = import_profile(staged, name)
    try:
        nmcli("connection", "up", "uuid", uuid)
    except ValueError:
        # Remove failed imports; a retry always reads the current source file.
        try:
            nmcli("connection", "delete", "uuid", uuid)
        except ValueError:
            pass
        raise
    return snapshot()


def handle(request):
    with LOCK:
        operation = request["op"]
        if operation == "status":
            return snapshot()
        if operation in ("connect", "disconnect"):
            return control(request.get("profile"), operation)
        raise ValueError("Unknown VPN operation.")


if __name__ == "__main__":
    serve(handle, controls=("connect", "disconnect"), latest=("status",), workers=1)
