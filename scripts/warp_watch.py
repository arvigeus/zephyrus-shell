"""Passive systemd signals plus WARP's status stream; no periodic status queries."""

import json
import os
import shutil
import signal
import subprocess

from warp import UNIT, connection_state

DAEMON = "warp-svc.service"
ACTIVE = ("active", "reloading")


class Watcher:
    def __init__(self, bus, glib, emit):
        self.bus, self.glib, self.emit = bus, glib, emit
        self.states = {UNIT: "inactive", DAEMON: "inactive"}
        self.paths = {}
        self.child = None
        self.io = None
        self.retry = None
        self.attempts = 0
        self.buffer = b""
        self.connection = "connecting"
        self.message = ""
        self.previous = None
        self.closed = False

    def publish(self, error=""):
        owner, daemon = self.states[UNIT], self.states[DAEMON]
        state = self.connection
        enabled = owner in (*ACTIVE, "activating")
        if owner == "deactivating" or daemon == "deactivating":
            state, enabled = "disconnecting", False
        elif daemon not in ACTIVE:
            state = "connecting" if daemon == "activating" or owner == "activating" else "off"
        elif owner == "activating":
            state = "connecting"
        if state == "off":
            enabled = False
        data = {
            "ok": not bool(error),
            "available": True,
            "state": state,
            "enabled": enabled or state in ("connected", "connecting"),
            "message": self.message if state != "off" else "Off · daemon stopped",
        }
        if error:
            data["error"] = error
            data["state"] = "error"
        if data != self.previous:
            self.previous = data
            self.emit(data)

    def changed(self, interface, changed, invalidated, path=None):
        if interface != "org.freedesktop.systemd1.Unit" or path not in self.paths:
            return
        unit = self.paths[path]
        state = changed.get("ActiveState")
        if state is None and "ActiveState" in invalidated:
            state = self.properties(path).Get(interface, "ActiveState")
        if state is None or str(state) == self.states[unit]:
            return
        self.states[unit] = str(state)
        self.sync()

    def properties(self, path):
        import dbus

        return dbus.Interface(
            self.bus.get_object("org.freedesktop.systemd1", path), "org.freedesktop.DBus.Properties"
        )

    def sync(self):
        if self.states[DAEMON] in ACTIVE:
            if self.child is None and self.retry is None:
                self.start_stream()
        else:
            self.stop_stream()
            self.attempts = 0
            self.connection, self.message = "connecting", ""
        self.publish()

    def start_stream(self):
        self.attempts += 1
        self.buffer = b""
        self.child = subprocess.Popen(
            ["warp-cli", "--accept-tos", "--no-ansi", "--no-paginate", "--listen", "status"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env={**os.environ, "LC_ALL": "C"},
        )
        assert self.child.stdout is not None
        os.set_blocking(self.child.stdout.fileno(), False)
        self.io = self.glib.io_add_watch(
            self.child.stdout.fileno(),
            self.glib.IO_IN | self.glib.IO_HUP | self.glib.IO_ERR,
            self.read_stream,
        )

    def read_stream(self, fd, condition):
        try:
            data = os.read(fd, 65536)
        except BlockingIOError:
            return True
        if data:
            self.buffer += data
            while b"\n" in self.buffer:
                line, self.buffer = self.buffer.split(b"\n", 1)
                self.receive(line.decode("utf-8", errors="replace"))
            return True
        if self.buffer:
            self.receive(self.buffer.decode("utf-8", errors="replace"))
        self.io = None  # GLib removes this source when the callback returns False.
        child, self.child = self.child, None
        assert child is not None and child.stdout is not None
        child.stdout.close()
        child.wait(timeout=2)
        if not self.closed and self.states[DAEMON] in ACTIVE:
            # Type=simple becomes active before IPC is ready. Retry only this
            # bounded startup/failure window, never the idle daemon state.
            if self.attempts < 6:
                self.retry = self.glib.timeout_add(
                    250 * 2 ** (self.attempts - 1), self.retry_stream
                )
            else:
                self.publish("WARP status listener stopped; reopen the shell to retry")
        return False

    def receive(self, line):
        state = connection_state(line)
        if state:
            self.connection, self.message = state, line.strip()
            self.attempts = 0
            self.publish()

    def retry_stream(self):
        self.retry = None
        if not self.closed and self.states[DAEMON] in ACTIVE:
            self.start_stream()
        return False

    def stop_stream(self):
        if self.retry is not None:
            self.glib.source_remove(self.retry)
            self.retry = None
        if self.io is not None:
            self.glib.source_remove(self.io)
            self.io = None
        if self.child is not None:
            child, self.child = self.child, None
            child.terminate()
            try:
                child.wait(timeout=2)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
            assert child.stdout is not None
            child.stdout.close()

    def close(self):
        self.closed = True
        self.stop_stream()


def watch():
    def emit(data):
        print(json.dumps(data), flush=True)

    if not shutil.which("warp-cli"):
        emit({"ok": True, "available": False, "state": "unavailable", "enabled": False})
        return
    import dbus
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib  # ty: ignore[unresolved-import]

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    manager = dbus.Interface(
        bus.get_object("org.freedesktop.systemd1", "/org/freedesktop/systemd1"),
        "org.freedesktop.systemd1.Manager",
    )
    observer = Watcher(bus, GLib, emit)
    loop = GLib.MainLoop()
    # Subscribe before reading initial state so starts/stops cannot be missed.
    receiver = bus.add_signal_receiver(
        observer.changed,
        signal_name="PropertiesChanged",
        dbus_interface="org.freedesktop.DBus.Properties",
        bus_name="org.freedesktop.systemd1",
        path_keyword="path",
    )
    manager.Subscribe()
    try:
        for unit in (UNIT, DAEMON):
            path = str(manager.LoadUnit(unit))
            observer.paths[path] = unit
            observer.states[unit] = str(
                observer.properties(path).Get("org.freedesktop.systemd1.Unit", "ActiveState")
            )
        observer.sync()

        def terminate(*_):
            loop.quit()

        signal.signal(signal.SIGTERM, terminate)
        signal.signal(signal.SIGINT, terminate)
        loop.run()
    finally:
        observer.close()
        receiver.remove()
        manager.Unsubscribe()
        bus.close()
