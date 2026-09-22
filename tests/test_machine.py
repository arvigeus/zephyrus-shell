import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("machine", Path(__file__).parents[1] / "scripts/machine.py")
machine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(machine)


class ActionTests(unittest.TestCase):
    def test_rejects_invalid_actions_without_execution(self):
        with patch.object(machine, "command") as command:
            for name, value in [("shell", "echo hi"), ("wifi", "on; reboot"), ("profile", "unknown"), ("brightness", "0"), ("brightness", "101")]:
                with self.assertRaises(ValueError):
                    machine.action(name, value)
            command.assert_not_called()

    def test_wifi_uses_argument_array(self):
        with patch.object(machine, "command") as command:
            machine.action("wifi", "off")
            command.assert_called_once_with(["nmcli", "radio", "wifi", "off"], True)

    def test_logout_refuses_other_desktops(self):
        with patch.dict(machine.os.environ, {}, clear=True), patch.object(machine, "command") as command:
            with self.assertRaises(ValueError):
                machine.action("logout", "")
            command.assert_not_called()


if __name__ == "__main__":
    unittest.main()
