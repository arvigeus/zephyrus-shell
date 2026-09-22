"""One owned BlueZ pairing operation. Confirmation travels over stdin, never argv."""
import json
import re
import sys
import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib


def emit(kind, **fields):
    print(json.dumps(dict(kind=kind, **fields)), flush=True)


class Rejected(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Rejected"


class Agent(dbus.service.Object):
    pending = None

    def ask(self, kind, ok, fail, **fields):
        if self.pending:
            self.pending[2](Rejected("Superseded request"))
        self.pending = (kind, ok, fail)
        emit(kind, **fields)

    @dbus.service.method("org.bluez.Agent1", in_signature="ou", out_signature="", async_callbacks=("ok", "fail"))
    def RequestConfirmation(self, device, passkey, ok, fail):
        self.ask("confirm", ok, fail, code=f"{int(passkey):06d}")

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="s", async_callbacks=("ok", "fail"))
    def RequestPinCode(self, device, ok, fail):
        self.ask("pin", ok, fail)

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="u", async_callbacks=("ok", "fail"))
    def RequestPasskey(self, device, ok, fail):
        self.ask("passkey", ok, fail)

    @dbus.service.method("org.bluez.Agent1", in_signature="o", out_signature="", async_callbacks=("ok", "fail"))
    def RequestAuthorization(self, device, ok, fail):
        self.ask("confirm", ok, fail, code="Allow pairing with this device?")

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="", async_callbacks=("ok", "fail"))
    def AuthorizeService(self, device, uuid, ok, fail):
        self.ask("confirm", ok, fail, code="Allow service " + str(uuid) + "?")

    @dbus.service.method("org.bluez.Agent1", in_signature="ouq", out_signature="")
    def DisplayPasskey(self, device, passkey, entered):
        emit("display", code=f"{int(passkey):06d}", entered=int(entered))

    @dbus.service.method("org.bluez.Agent1", in_signature="os", out_signature="")
    def DisplayPinCode(self, device, pincode):
        emit("display", code=str(pincode))

    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Cancel(self):
        if self.pending:
            self.pending[2](Rejected("Cancelled"))
            self.pending = None
        emit("cancelled")

    @dbus.service.method("org.bluez.Agent1", in_signature="", out_signature="")
    def Release(self):
        self.Cancel()

    def answer(self, response):
        if not self.pending:
            return
        kind, ok, fail = self.pending
        self.pending = None
        if not response.get("accept", False):
            fail(Rejected("Declined by user"))
        elif kind == "pin" and 1 <= len(str(response.get("value", ""))) <= 16:
            ok(str(response["value"]))
        elif kind == "passkey" and re.fullmatch(r"\d{1,6}", str(response.get("value", ""))):
            ok(dbus.UInt32(int(response["value"])))
        elif kind == "confirm":
            ok()
        else:
            fail(Rejected("Invalid PIN or passkey"))


def main(path):
    if not re.fullmatch(r"/org/bluez/hci\d+/dev_[0-9A-Fa-f_]+", path):
        raise ValueError("Invalid Bluetooth device path")
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    loop = GLib.MainLoop()
    agent_path = "/org/drawershell/PairingAgent"
    agent = Agent(bus, agent_path)
    manager = dbus.Interface(bus.get_object("org.bluez", "/org/bluez"), "org.bluez.AgentManager1")
    device = dbus.Interface(bus.get_object("org.bluez", path), "org.bluez.Device1")
    manager.RegisterAgent(agent_path, "KeyboardDisplay")

    def finish(error=None):
        emit("error", message=str(error)) if error else emit("paired")
        loop.quit()

    def read_input(source, condition):
        line = sys.stdin.readline()
        if not line:
            device.CancelPairing(reply_handler=lambda: None, error_handler=lambda e: None)
            loop.quit()
            return False
        try:
            agent.answer(json.loads(line))
        except (ValueError, TypeError):
            agent.answer({"accept": False})
        return True

    def timeout():
        device.CancelPairing(reply_handler=lambda: None, error_handler=lambda e: None)
        finish("Pairing timed out")
        return False

    GLib.io_add_watch(sys.stdin, GLib.IO_IN | GLib.IO_HUP, read_input)
    GLib.timeout_add_seconds(90, timeout)
    device.Pair(reply_handler=lambda: finish(), error_handler=finish, timeout=95)
    try:
        loop.run()
    finally:
        manager.UnregisterAgent(agent_path)


if __name__ == "__main__":
    try:
        main(sys.argv[1])
    except Exception as error:
        emit("error", message=str(error))
        sys.exit(1)
