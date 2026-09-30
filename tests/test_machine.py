import importlib.util
from pathlib import Path
import unittest
import tempfile
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


class TemperatureTests(unittest.TestCase):
    def test_hardware_reads_millidegrees_and_refreshes_changed_sensor(self):
        with tempfile.TemporaryDirectory() as directory:
            sensor = Path(directory) / "hwmon0"
            sensor.mkdir()
            (sensor / "name").write_text("k10temp")
            (sensor / "temp1_label").write_text("Tctl")
            reading = sensor / "temp1_input"
            reading.write_text("54500")
            with patch.object(machine, "gpu_hardware", return_value=[]), patch.object(machine, "cpu_usage", return_value=0):
                first = machine.hardware(hwmon_root=Path(directory))
                reading.write_text("58000")
                second = machine.hardware(hwmon_root=Path(directory))
            self.assertEqual(first["cpuTemperature"], {"driver": "k10temp", "label": "Tctl", "value": 54})
            self.assertEqual(second["cpuTemperature"]["value"], 58)
            self.assertIsNone(first["gpuTemperature"])

    def test_combined_gpu_card_prefers_hottest_edge_over_memory_or_junction(self):
        sensors = [{"driver": "amdgpu", "label": label, "value": value}
                   for label, value in [("mem", 82), ("junction", 91), ("edge", 53), ("edge", 49)]]
        self.assertEqual(machine.temperature_summary(sensors, "gpu")["value"], 53)
        self.assertEqual(machine.temperature_summary(list(reversed(sensors)), "gpu")["value"], 53)

    def test_package_preferred_over_individual_cores_and_unrelated_sensors(self):
        sensors = [{"driver": driver, "label": label, "value": value} for driver, label, value in
                   [("coretemp", "Core 0", 65), ("coretemp", "Package id 0", 60), ("nvme", "Composite", 70)]]
        self.assertEqual(machine.temperature_summary(sensors, "cpu")["value"], 60)
        self.assertIsNone(machine.temperature_summary(sensors, "gpu"))


if __name__ == "__main__":
    unittest.main()
