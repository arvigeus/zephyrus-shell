#!/usr/bin/env python3
"""Isolated systemd/WARP fixture for the production backend and QML smoke test."""

import os
import signal
import sys
from pathlib import Path

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

DBusGMainLoop(set_as_default=True)
BUS = "org.freedesktop.systemd1"
UNIT = "zephyrus-warp.service"
DAEMON = "warp-svc.service"
MANAGER = "/org/freedesktop/systemd1"
UNIT_INTERFACE = "org.freedesktop.systemd1.Unit"
TEST_INTERFACE = "org.zephyrus.TestWarp"
PATHS = {UNIT: MANAGER + "/unit/owner", DAEMON: MANAGER + "/unit/daemon"}


def log(value):
    path = Path(os.environ["XDG_STATE_HOME"]) / "fake-warp-calls"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as output:
        output.write(value + "\n")


class Unit(dbus.service.Object):
    def __init__(self, bus, path):
        super().__init__(bus, path)
        self.state = "inactive"

    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        return self.state

    @dbus.service.signal("org.freedesktop.DBus.Properties", signature="sa{sv}as")
    def PropertiesChanged(self, interface, properties, invalidated):
        pass

    def set(self, state):
        self.state = state
        self.PropertiesChanged(UNIT_INTERFACE, {"ActiveState": state}, [])


class Manager(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, MANAGER)
        self.units = {name: Unit(bus, path) for name, path in PATHS.items()}
        self.status = "Disconnected"
        self.generation = 0
        self.deny_next = False

    @dbus.service.method("org.freedesktop.systemd1.Manager", in_signature="", out_signature="")
    def Subscribe(self):
        log("subscribe")

    @dbus.service.method("org.freedesktop.systemd1.Manager", in_signature="", out_signature="")
    def Unsubscribe(self):
        pass

    @dbus.service.method("org.freedesktop.systemd1.Manager", in_signature="s", out_signature="o")
    def LoadUnit(self, name):
        return PATHS[name]

    @dbus.service.method(TEST_INTERFACE, in_signature="", out_signature="s")
    def Status(self):
        return self.status

    @dbus.service.signal(TEST_INTERFACE, signature="s")
    def StatusChanged(self, status):
        pass

    def set_connection(self, state):
        self.status = state
        self.StatusChanged(state)

    @dbus.service.method(TEST_INTERFACE, in_signature="", out_signature="")
    def DenyNext(self):
        self.deny_next = True

    @dbus.service.method(TEST_INTERFACE, in_signature="s", out_signature="")
    def Action(self, action):
        self.generation += 1
        generation = self.generation
        if self.deny_next:
            self.deny_next = False
            raise dbus.exceptions.DBusException("Test policy denied connection")
        if action == "disconnect":
            self.units[UNIT].set("deactivating")
            self.set_connection("Disconnected")
            self.units[UNIT].set("inactive")
            self.units[DAEMON].set("inactive")
        else:
            self.units[UNIT].set("activating")
            self.status = "Connecting"
            self.units[DAEMON].set("active")
            self.units[UNIT].set("active")

            # Command completes long before the tunnel: this caught the real bug.
            def connected():
                if generation == self.generation:
                    self.set_connection("Connected")
                return False

            GLib.timeout_add(700, connected)


def main():
    name = Path(sys.argv[0]).name
    bus = dbus.SystemBus()
    if name == "warp_host.py" and len(sys.argv) == 1:
        service_name = dbus.service.BusName(BUS, bus)
        manager = Manager(bus)
        print("HOST READY", flush=True)
        GLib.MainLoop().run()
        return service_name, manager
    if name == "systemctl" and not (
        sys.argv[1:2] == ["show"] or "start" in sys.argv or "stop" in sys.argv
    ):
        return 1
    manager = dbus.Interface(bus.get_object(BUS, MANAGER), TEST_INTERFACE)
    if name == "warp_host.py":
        manager.DenyNext()
        return 0
    if name == "systemctl":
        args = sys.argv[1:]
        if args[0] == "show":
            unit = dbus.Interface(
                bus.get_object(BUS, PATHS[args[-1]]), "org.freedesktop.DBus.Properties"
            )
            print(unit.Get(UNIT_INTERFACE, "ActiveState"))
        else:
            log(args[-2])
            try:
                manager.Action("connect" if args[-2] == "start" else "disconnect")
            except dbus.exceptions.DBusException:
                print("Test policy denied connection", file=sys.stderr)
                return 1
        return 0
    log("listen" if "--listen" in sys.argv else "status")

    def output(state):
        print("Status update: " + state, flush=True)

    output(manager.Status())
    if "--listen" in sys.argv:
        loop = GLib.MainLoop()
        bus.add_signal_receiver(
            output,
            signal_name="StatusChanged",
            dbus_interface=TEST_INTERFACE,
            bus_name=BUS,
            path=MANAGER,
        )
        signal.signal(signal.SIGTERM, lambda *_: loop.quit())
        loop.run()
        log("listener-stopped")
    return 0


if __name__ == "__main__":
    result = main()
    sys.exit(result if isinstance(result, int) else 0)
