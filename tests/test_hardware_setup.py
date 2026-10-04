import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock


def setup_module():
    path = Path(__file__).resolve().parents[1] / "scripts/setup-hardware.py"
    spec = importlib.util.spec_from_file_location("hardware_setup", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class HardwareSetupTests(unittest.TestCase):
    def test_ddc_setup_is_explicit_idempotent_and_scoped_to_supplied_root(self):
        module = setup_module()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runs = []

            def runner(arguments, **kwargs):
                runs.append(arguments)
                if arguments[:3] == ["getent", "group", "i2c"]:
                    return subprocess.CompletedProcess(arguments, 1 if runs.count(arguments) == 1 else 0)
                return subprocess.CompletedProcess(arguments, 0)

            lookup = Mock()
            module.configure_ddc("tester", root, runner, lookup, effective_uid=0)
            module.configure_ddc("tester", root, runner, lookup, effective_uid=0)
            self.assertEqual((root / "etc/modules-load.d/zephyrus-ddc.conf").read_text(), "i2c-dev\n")
            self.assertEqual(runs.count(["groupadd", "--system", "i2c"]), 1)
            self.assertEqual(runs.count(["usermod", "--append", "--groups", "i2c", "tester"]), 2)
            self.assertTrue(all(Path(path).is_relative_to(root) for path in
                                [root / "etc/modules-load.d/zephyrus-ddc.conf"]))

    def test_ddc_setup_refuses_non_root_before_host_changes(self):
        module = setup_module()
        runner = Mock()
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(PermissionError, "must run as root"):
                module.configure_ddc("tester", Path(directory), runner, effective_uid=1000)
        runner.assert_not_called()


if __name__ == "__main__":
    unittest.main()
