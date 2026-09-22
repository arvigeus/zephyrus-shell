import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("plugins", Path(__file__).parents[1] / "scripts/plugins.py")
plugins = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plugins)


class DiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def add(self, name, **overrides):
        directory = self.root / name
        directory.mkdir()
        # Deliberately invalid QML: discovery must never parse/instantiate it.
        (directory / "Main.qml").write_text("not executable QML")
        data = dict(apiVersion=1, id=name, name=name, entry="Main.qml")
        data.update(overrides)
        (directory / "manifest.json").write_text(json.dumps(data))

    def test_metadata_only_order_and_disabled(self):
        self.add("later", order=20)
        self.add("first", order=1)
        self.add("disabled", enabled=False)
        result = plugins.discover(self.root)
        self.assertEqual([p["id"] for p in result["entries"]], ["first", "later"])
        self.assertFalse(result["errors"])

    def test_bad_plugin_does_not_break_others(self):
        self.add("valid")
        self.add("bad", apiVersion=2)
        self.add("escape", entry="../valid/Main.qml")
        self.add("duplicate", id="valid")
        result = plugins.discover(self.root)
        self.assertEqual(len(result["entries"]), 1)
        self.assertEqual(len(result["errors"]), 3)

    def test_removal_is_detected(self):
        self.add("removable")
        (self.root / "removable/manifest.json").unlink()
        self.assertEqual(plugins.discover(self.root)["entries"], [])


if __name__ == "__main__":
    unittest.main()
