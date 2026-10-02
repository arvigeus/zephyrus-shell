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

    def test_suspended_gpu_sensors_are_skipped_until_the_device_is_active(self):
        with tempfile.TemporaryDirectory() as directory:
            sensor = Path(directory) / "hwmon0"
            (sensor / "device/power").mkdir(parents=True)
            (sensor / "name").write_text("amdgpu")
            (sensor / "temp1_input").write_text("72500")
            status = sensor / "device/power/runtime_status"
            status.write_text("suspended")
            with patch.object(machine, "gpu_hardware", return_value=[]), patch.object(machine, "cpu_usage", return_value=0):
                self.assertEqual(machine.hardware(hwmon_root=Path(directory))["temperatures"], [])
                status.write_text("active")
                self.assertEqual(machine.hardware(hwmon_root=Path(directory))["gpuTemperature"]["value"], 72)

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


class DisplayTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        environment = patch.dict(machine.os.environ, {"XDG_CONFIG_HOME": str(self.root)})
        environment.start()
        self.addCleanup(environment.stop)
        self.monitors = [
            {"name": "eDP-2", "width": 1920, "height": 1080, "refreshRate": 60,
             "x": 0, "y": 0, "scale": 1.25, "availableModes": ["1920x1080@60.00Hz"], "disabled": False},
            {"name": "DP-3", "width": 2560, "height": 1440, "refreshRate": 60,
             "x": 1536, "y": 0, "scale": 1, "availableModes": ["2560x1440@60.00Hz"], "disabled": False}]

    def command(self, args, *unused):
        import json
        return json.dumps(self.monitors) if "monitors" in args else "ok"

    def test_aux_ddc_bus_precedes_legacy_adapter_and_explicit_override(self):
        port = self.root / "card2-DP-3"
        (port / "ddc/i2c-dev/i2c-10").mkdir(parents=True)
        (port / "i2c-19/i2c-dev/i2c-19").mkdir(parents=True)
        self.assertEqual(machine.ddc_bus("DP-3", {}, self.root), 19)
        self.assertEqual(machine.ddc_bus("DP-3", {"DP-3": {"ddcBus": 7}}, self.root), 7)
        self.assertIsNone(machine.ddc_bus("DP-9", {}, self.root))

    def test_order_uses_logical_width_and_atomic_persistent_lua(self):
        import json
        with patch.object(machine, "command", side_effect=self.command) as command:
            machine.action("display-order", json.dumps({"order": ["DP-3", "eDP-2"]}))
        script = command.call_args.args[0]
        self.assertEqual(script[:2], ["hyprctl", "eval"])
        self.assertIn('position = "2560x0"', script[2])
        saved = self.root / "zephyrus-shell/display-settings.lua"
        self.assertIn('"DP-3"', saved.read_text())
        self.assertEqual(len(list(saved.parent.iterdir())), 1)

    def test_scale_reflows_neighbors_without_overlap(self):
        import json
        with patch.object(machine, "command", side_effect=self.command) as command:
            machine.action("display-scale", json.dumps({"name": "eDP-2", "scale": 1.5}))
        self.assertIn('position = "1280x0"', command.call_args.args[0][2])

    def test_disable_uses_lua_and_is_session_only(self):
        import json
        with patch.object(machine, "command", side_effect=self.command) as command:
            machine.action("display", json.dumps({"name": "DP-3", "enabled": False}))
        self.assertIn('disabled = true', command.call_args.args[0][2])
        self.assertFalse((self.root / "zephyrus-shell/display-settings.lua").exists())

    def test_last_display_cannot_be_disabled(self):
        import json
        self.monitors[1]["disabled"] = True
        with patch.object(machine, "command", side_effect=self.command) as command:
            with self.assertRaisesRegex(ValueError, "at least one"):
                machine.action("display", json.dumps({"name": "eDP-2", "enabled": False}))
        self.assertEqual(command.call_count, 1)

    def test_unplugging_external_recovers_disabled_internal_without_saving_rules(self):
        self.monitors = [dict(self.monitors[0], disabled=True), {"name": "FALLBACK", "disabled": False}]
        with patch.dict(machine.os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "test"}), \
             patch.object(machine, "command", side_effect=self.command) as command:
            machine.recover_displays()
        self.assertEqual(command.call_count, 3)
        self.assertIn('output = "eDP-2"', command.call_args_list[1].args[0][2])
        self.assertIn('disabled = false', command.call_args_list[1].args[0][2])
        self.assertIn('monitor = "eDP-2"', command.call_args_list[2].args[0][2])
        self.assertFalse((self.root / "zephyrus-shell/display-settings.lua").exists())

    def test_display_recovery_preserves_working_external_only_setup(self):
        self.monitors[0]["disabled"] = True
        with patch.dict(machine.os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "test"}), \
             patch.object(machine, "command", side_effect=self.command) as command:
            machine.recover_displays()
        self.assertEqual(command.call_count, 1)

    def test_display_recovery_wakes_sole_internal_dpms_panel(self):
        self.monitors = [dict(self.monitors[0], dpmsStatus=False)]
        with patch.dict(machine.os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "test"}), \
             patch.object(machine, "command", side_effect=self.command) as command:
            machine.recover_displays()
        self.assertEqual(command.call_count, 2)
        self.assertIn('hl.dsp.dpms', command.call_args.args[0][2])

    def test_display_recovery_handles_no_outputs_and_no_compositor(self):
        self.monitors = []
        with patch.dict(machine.os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": "test"}), \
             patch.object(machine, "command", side_effect=self.command) as command:
            machine.recover_displays()
        self.assertEqual(command.call_count, 1)
        with patch.dict(machine.os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": ""}), \
             patch.object(machine, "command") as command:
            machine.recover_displays()
        command.assert_not_called()

    def test_rejects_duplicate_order_and_unlisted_mode(self):
        import json
        with patch.object(machine, "command", side_effect=self.command) as command:
            for name, data in [("display-order", {"order": ["DP-3", "DP-3"]}),
                               ("display-mode", {"name": "DP-3", "mode": "unsafe; reboot"})]:
                with self.assertRaises(ValueError):
                    machine.action(name, json.dumps(data))
        self.assertEqual(command.call_count, 2)

    def test_failed_compositor_change_does_not_save_rule(self):
        import json
        def fail(args, *unused):
            if "eval" in args:
                raise RuntimeError("rejected")
            return json.dumps(self.monitors)
        with patch.object(machine, "command", side_effect=fail):
            with self.assertRaises(RuntimeError):
                machine.action("display-scale", json.dumps({"name": "DP-3", "scale": 1.25}))
        self.assertFalse((self.root / "zephyrus-shell/display-settings.lua").exists())


class DdcCacheTests(unittest.TestCase):
    def test_cache_reuses_probe_and_explicit_refresh_reads_again(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "i2c-19").touch()
            with patch.object(machine, "STATE", root / "state"), \
                 patch.object(machine.shutil, "which", return_value="ddcutil"), \
                 patch.object(machine, "command", return_value="VCP 10 C 45 100") as query:
                self.assertEqual(machine.ddc_brightness(19, device_root=root), (45, ""))
                self.assertEqual(machine.ddc_brightness(19, device_root=root), (45, ""))
                self.assertEqual(query.call_count, 1)
                self.assertEqual(machine.ddc_brightness(19, refresh=True, device_root=root), (45, ""))
                self.assertEqual(query.call_count, 2)

    def test_unresponsive_monitor_caches_diagnostic_without_repeated_probes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "i2c-19").touch()
            with patch.object(machine, "STATE", root / "state"), \
                 patch.object(machine.shutil, "which", return_value="ddcutil"), \
                 patch.object(machine, "command", side_effect=RuntimeError("No response")) as query:
                value, error = machine.ddc_brightness(19, device_root=root)
                self.assertIsNone(value)
                self.assertIn("No response", error)
                self.assertEqual(machine.ddc_brightness(19, device_root=root), (None, error))
                self.assertEqual(query.call_count, 1)


if __name__ == "__main__":
    unittest.main()
