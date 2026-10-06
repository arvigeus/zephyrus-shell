#!/usr/bin/env python3
"""Isolated nmcli boundary fixture for the real Settings worker and QML rows."""

import json
import os
import sys
import time
from pathlib import Path

root = Path(os.environ["XDG_STATE_HOME"])
root.mkdir(parents=True, exist_ok=True)
state_path = root / "vpn-host.json"
state = json.loads(state_path.read_text()) if state_path.exists() else {}
args = sys.argv[1:]
if args == ["host"]:
    import dbus
    import dbus.service
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib  # ty: ignore[unresolved-import]

    DBusGMainLoop(set_as_default=True)

    class Settings(dbus.service.Object):
        @dbus.service.method(
            "org.freedesktop.NetworkManager.Settings",
            in_signature="a{sa{sv}}ua{sv}",
            out_signature="oa{sv}",
        )
        def AddConnection2(self, settings, flags, options):
            assert int(flags) == 34  # IN_MEMORY | BLOCK_AUTOCONNECT
            connection = settings["connection"]
            assert not connection["autoconnect"]
            assert len(connection["permissions"]) == 1
            assert str(connection["permissions"][0]).startswith("user:")
            assert settings["wireguard"]["private-key"]
            uuid = str(connection["uuid"])
            current = json.loads(state_path.read_text()) if state_path.exists() else {}
            current[uuid] = {"name": str(connection["id"]), "active": False}
            state_path.write_text(json.dumps(current))
            with (root / "vpn-calls").open("a") as log:
                log.write(json.dumps(["AddConnection2", int(flags)]) + "\n")
            return "/org/freedesktop/NetworkManager/Settings/1", {}

    bus = dbus.SessionBus()
    name = dbus.service.BusName("org.freedesktop.NetworkManager", bus)
    host = Settings(bus, "/org/freedesktop/NetworkManager/Settings")
    print("VPN HOST READY", flush=True)
    GLib.MainLoop().run()
    sys.exit(0)
elif args == ["remove-config"]:
    (Path(os.environ["XDG_CONFIG_HOME"]) / "zephyrus-shell/vpn/Home VPN.conf").unlink()
elif args == ["deny-next"]:
    (root / "deny-next").touch()
else:
    with (root / "vpn-calls").open("a") as log:
        log.write(json.dumps(args) + "\n")
    if "show" in args:
        for uuid, entry in state.items():
            print(
                f"{uuid}:wireguard:{'yes' if entry['active'] else 'no'}:{'activated' if entry['active'] else ''}:{entry['name']}"
            )
    elif "up" in args or "down" in args:
        deny = root / "deny-next"
        if deny.exists():
            deny.unlink()
            print("Error: Not authorized to control networking.", file=sys.stderr)
            sys.exit(1)
        time.sleep(0.2)
        state[args[args.index("uuid") + 1]]["active"] = "up" in args
    elif "delete" in args:
        del state[args[args.index("uuid") + 1]]
    else:
        raise AssertionError(args)
state_path.write_text(json.dumps(state))
