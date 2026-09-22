import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("audio_devices", Path(__file__).parents[1] / "scripts/audio_devices.py")
audio = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audio)


class AudioTests(unittest.TestCase):
    def test_bad_rule_file_does_not_disable_good_rules(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "bad.json").write_text('[{"label":"Too broad"}]')
            Path(directory, "good.json").write_text(json.dumps([{"label":"Monitor", "match":{"node.name":"monitor"}}]))
            rules, errors = audio.load_rules(directory)
            self.assertEqual(len(rules), 1)
            self.assertEqual(len(errors), 1)

    def test_input_mode_rejects_stale_and_unavailable_configuration(self):
        card = dict(name="card", active_profile="output:analog-stereo", profiles={})
        with patch.object(audio, "read_cards", return_value=[card]), patch.object(audio.subprocess, "run") as run:
            for previous in ("stale", "output:analog-stereo"):
                with self.assertRaises(ValueError):
                    audio.enable_input("card", "output:analog-stereo+input:analog-stereo", previous)
            run.assert_not_called()

    def test_enabling_input_preserves_output_profile(self):
        profile = "output:analog-stereo+input:analog-stereo"
        card = dict(name="card", active_profile="output:analog-stereo", profiles={profile:dict(sources=1,available=True)})
        with patch.object(audio, "read_cards", return_value=[card]), patch.object(audio.subprocess, "run") as run:
            audio.enable_input("card", profile, "output:analog-stereo")
            self.assertEqual(run.call_args.args[0], ["pactl", "set-card-profile", "card", profile])
