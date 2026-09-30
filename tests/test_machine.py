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


class BatteryDetailsTests(unittest.TestCase):
    def pack(self, root, name="BAT0", **fields):
        pack = Path(root) / name
        pack.mkdir()
        for field, value in {"type": "Battery", **fields}.items():
            (pack / field).write_text(str(value))
        return pack

    def test_energy_health_power_and_estimate(self):
        with tempfile.TemporaryDirectory() as directory:
            self.pack(directory, energy_full=51000000, energy_full_design=60000000,
                      energy_now=25500000, power_now=10000000, capacity=50,
                      status="Discharging", cycle_count=0, temp=315, technology="Li-ion")
            with patch.object(machine, "command") as command:
                pack = machine.battery_details(supply_root=Path(directory))["batteries"][0]
                command.assert_not_called()
        self.assertEqual(pack["healthPercent"], 85)
        self.assertEqual((pack["fullCapacity"], pack["designCapacity"], pack["capacityUnit"]), (51, 60, "Wh"))
        self.assertEqual(pack["watts"], 10)
        self.assertEqual(pack["seconds"], 9180)
        self.assertEqual(pack["cycles"], 0)
        self.assertEqual(pack["temperature"], 31.5)
        self.assertEqual(pack["technology"], "Lithium-ion")

    def test_charge_only_driver_uses_matching_units_and_voltage(self):
        with tempfile.TemporaryDirectory() as directory:
            self.pack(directory, charge_full=4000000, charge_full_design=5000000,
                      charge_now=2000000, current_now=1000000, voltage_now=12000000, status="Charging")
            pack = machine.battery_details(supply_root=Path(directory))["batteries"][0]
        self.assertEqual(pack["healthPercent"], 80)
        self.assertEqual((pack["fullCapacity"], pack["capacityUnit"]), (4000, "mAh"))
        self.assertEqual(pack["watts"], 12)
        self.assertEqual(pack["seconds"], 7200)

    def test_missing_invalid_and_zero_readings_are_not_invented(self):
        with tempfile.TemporaryDirectory() as directory:
            self.pack(directory, energy_full=50000000, energy_full_design=0,
                      cycle_count=-1, temp="nan", power_now=0, capacity="bad", status="Not charging")
            pack = machine.battery_details(supply_root=Path(directory))["batteries"][0]
        for field in ("healthPercent", "designCapacity", "seconds", "temperature", "cycles", "percent"):
            self.assertIsNone(pack[field], field)
        self.assertEqual(pack["fullCapacity"], 50)
        self.assertEqual(pack["watts"], 0)

    def test_charging_estimate_respects_charge_limit(self):
        with tempfile.TemporaryDirectory() as directory:
            pack_path = self.pack(directory, energy_full=60000000, energy_full_design=60000000,
                                  energy_now=36000000, power_now=12000000, status="Charging",
                                  charge_control_end_threshold=80)
            pack = machine.battery_details(supply_root=Path(directory))["batteries"][0]
            self.assertEqual(pack["seconds"], 3600)
            self.assertEqual(pack["chargeLimit"], 80)
            (pack_path / "energy_now").write_text("48000000")
            self.assertIsNone(machine.battery_details(supply_root=Path(directory))["batteries"][0]["seconds"])

    def test_adapter_plugging_updates_source_even_when_pack_stays_discharging(self):
        with tempfile.TemporaryDirectory() as directory:
            self.pack(directory, energy_full=60000000, energy_full_design=60000000,
                      energy_now=40000000, power_now=5700000, status="Discharging")
            adapter = self.pack(directory, "AC0", type="Mains", online=0)
            unplugged = machine.battery_details(supply_root=Path(directory))["batteries"][0]
            self.assertIs(unplugged["externalPower"], False)
            self.assertEqual(unplugged["statusText"], "On battery")
            self.assertGreater(unplugged["seconds"], 0)
            (adapter / "online").write_text("1")
            plugged = machine.battery_details(supply_root=Path(directory))["batteries"][0]
            self.assertIs(plugged["externalPower"], True)
            self.assertEqual(plugged["statusText"], "Plugged in · Battery discharging")
            self.assertIsNone(plugged["seconds"])
            self.assertEqual(plugged["watts"], 5.7)

    def test_usb_adapter_and_missing_source_do_not_guess_from_pack_status(self):
        with tempfile.TemporaryDirectory() as directory:
            self.pack(directory, status="Not charging")
            pack = machine.battery_details(supply_root=Path(directory))["batteries"][0]
            self.assertIsNone(pack["externalPower"])
            self.assertEqual(pack["statusText"], "Not charging")
            self.pack(directory, "AC0", type="Mains", online=0)
            self.pack(directory, "USB0", type="USB_PD", online=1)
            self.pack(directory, "mouse", type="USB", scope="Device", online=0)
            pack = machine.battery_details(supply_root=Path(directory))["batteries"][0]
            self.assertIs(pack["externalPower"], True)
            self.assertEqual(pack["statusText"], "Plugged in · Not charging")

    def test_multiple_system_packs_exclude_peripherals_and_absent_batteries(self):
        with tempfile.TemporaryDirectory() as directory:
            self.pack(directory, "BAT1", status="Full")
            self.pack(directory, "BAT0", status="Charging")
            self.pack(directory, "mouse", scope="Device")
            self.pack(directory, "BAT2", present=0)
            self.pack(directory, "AC", type="Mains")
            packs = machine.battery_details(supply_root=Path(directory))["batteries"]
        self.assertEqual([pack["name"] for pack in packs], ["BAT0", "BAT1"])
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(machine.battery_details(supply_root=Path(directory)), {"batteries": []})


if __name__ == "__main__":
    unittest.main()
