import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

ROOT = Path(__file__).parents[1]


def load(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


boost = load("cpu_boost", "scripts/cpu-boost.py")
machine = load("control_machine", "scripts/machine.py")
apps = load("app_gpu", "plugins/apps/backend.py")


class BoostTests(unittest.TestCase):
    def test_invalid_input_never_touches_hardware(self):
        with patch.object(boost, "BOOST_NODE") as node:
            for value in ("on", "1\n", "2", "/tmp/boost", "0; reboot"):
                with self.assertRaises(ValueError):
                    boost.set_boost(value)
            node.read_text.assert_not_called()
            node.write_text.assert_not_called()

    def test_supported_node_switches_both_ways_and_requires_root(self):
        with tempfile.TemporaryDirectory() as directory:
            node = Path(directory) / "boost"
            node.write_text("1")
            with patch.object(boost, "BOOST_NODE", node), patch.object(boost.os, "geteuid", return_value=1000):
                with self.assertRaises(PermissionError): boost.set_boost("0")
                self.assertEqual(node.read_text(), "1")
            with patch.object(boost, "BOOST_NODE", node), patch.object(boost.os, "geteuid", return_value=0):
                boost.set_boost("0")
                self.assertEqual(node.read_text().strip(), "0")
                boost.set_boost("1")
                self.assertEqual(node.read_text().strip(), "1")
                node.write_text("unknown")
                with self.assertRaises(ValueError): boost.set_boost("0")

    def test_action_is_scoped_and_reports_missing_setup(self):
        with patch.object(machine, "boost_control_error", return_value=""), patch.object(machine, "command") as command:
            machine.action("cpu-boost", "off")
            command.assert_called_once_with(["pkexec", "/usr/lib/zephyrus-shell/cpu-boost", "0"], True, 120)
            command.reset_mock()
            with self.assertRaises(ValueError): machine.action("cpu-boost", "1; reboot")
            command.assert_not_called()
        with patch.object(machine, "boost_control_error", return_value="Install helper"), patch.object(machine, "command") as command:
            with self.assertRaisesRegex(ValueError, "Install helper"): machine.action("cpu-boost", "on")
            command.assert_not_called()

    def test_policy_only_authorizes_the_installed_helper(self):
        policy = ET.parse(ROOT / "system/org.zephyrus-shell.cpu-boost.policy").getroot()
        action = policy.find("action")
        self.assertEqual(action.find("annotate").text, "/usr/lib/zephyrus-shell/cpu-boost")
        self.assertEqual(action.find("defaults/allow_active").text, "auth_admin_keep")
        self.assertEqual(action.find("defaults/allow_any").text, "no")
        self.assertEqual(action.find("defaults/allow_inactive").text, "no")


class GpuLaunchTests(unittest.TestCase):
    gpu = {"id": "discovered", "environment": {"DRI_PRIME": "pci-0000_03_00_0", "VK_LOADER_DRIVERS_SELECT": "*radeon*"}}

    def test_disappearing_gpu_is_an_error_instead_of_a_fallback(self):
        with patch.object(apps, "gpu_list", return_value=[]), patch.object(apps.subprocess, "Popen") as spawn:
            with self.assertRaisesRegex(ValueError, "no longer available"):
                apps.handle({"op": "launch", "command": ["true"], "gpu": "discovered"})
            spawn.assert_not_called()

    def test_real_child_gets_scoped_gpu_and_directory_without_shell_expansion(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "result.json"
            marker = Path(directory) / "should-not-exist"
            literal = "$(touch " + str(marker) + "); `false`"
            code = "import json,os,sys;open(sys.argv[1],'w').write(json.dumps([os.getcwd(),dict(os.environ),sys.argv[2]]))"
            original = {"MESA_VK_DEVICE_SELECT": "1002:1681!", "DRI_PRIME": "0", "__GLX_VENDOR_LIBRARY_NAME": "nvidia"}
            children = []
            popen = subprocess.Popen
            def spawn(*args, **kwargs):
                child = popen(*args, **kwargs)
                children.append(child)
                return child
            with patch.object(apps, "gpu_list", return_value=[self.gpu]), patch.dict(os.environ, original), patch.object(apps.subprocess, "Popen", side_effect=spawn):
                result = apps.handle({"op": "launch", "gpu": "discovered", "command": [sys.executable, "-c", code, str(output), literal], "directory": directory})
                self.assertTrue(result["ok"])
                self.assertEqual(os.environ["MESA_VK_DEVICE_SELECT"], original["MESA_VK_DEVICE_SELECT"])
                for _ in range(100):
                    if output.exists() and output.stat().st_size: break
                    time.sleep(.01)
                cwd, environment, argument = json.loads(output.read_text())
                self.assertEqual(cwd, directory)
                self.assertEqual(environment["DRI_PRIME"], "pci-0000_03_00_0!")
                self.assertEqual(environment["VK_LOADER_DRIVERS_SELECT"], "*radeon*")
                self.assertNotIn("MESA_VK_DEVICE_SELECT", environment)
                self.assertNotIn("__GLX_VENDOR_LIBRARY_NAME", environment)
                self.assertEqual(argument, literal)
                self.assertFalse(marker.exists())
                for child in children: child.wait(timeout=5)

    def test_nvidia_selectors_are_preserved_without_mesa_guessing(self):
        environment = apps.launch_environment({"environment": {"__NV_PRIME_RENDER_OFFLOAD": "1", "__GLX_VENDOR_LIBRARY_NAME": "nvidia"}}, {"DRI_PRIME": "1!", "PATH": "/usr/bin"})
        self.assertNotIn("DRI_PRIME", environment)
        self.assertEqual(environment["__GLX_VENDOR_LIBRARY_NAME"], "nvidia")
        self.assertEqual(environment["PATH"], "/usr/bin")

    def test_terminal_apps_keep_the_terminal_and_working_directory(self):
        with patch.object(apps, "gpu_list", return_value=[self.gpu]), patch.object(apps.subprocess, "Popen") as spawn:
            apps.handle({"op": "launch", "gpu": "discovered", "command": ["htop"], "directory": "/tmp", "terminal": True})
            self.assertEqual(spawn.call_args.args[0], ["kitty", "--", "htop"])
            self.assertEqual(spawn.call_args.kwargs["cwd"], "/tmp")


if __name__ == "__main__": unittest.main()
