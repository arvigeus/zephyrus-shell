import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / 'scripts'))
import machine
import profiles


class SettingsTests(unittest.TestCase):
    def test_cardwire_discovers_supported_modes(self):
        with patch.object(machine.shutil, 'which', return_value='/usr/bin/cardwire'), patch.object(machine, 'command', return_value='Current Mode: Hybrid\nAvailable Mode: integrated, hybrid, smart'):
            self.assertEqual(machine.gpu_status()['modes'], ['integrated', 'hybrid', 'smart'])
            self.assertEqual(machine.gpu_status()['mode'], 'hybrid')

    def test_gpu_rejects_unsupported_modes(self):
        with patch.object(machine, 'gpu_status', return_value={'modes': ['hybrid']}), patch.object(machine, 'command') as command:
            for mode in ['dedicated', 'integrated', 'hybrid; reboot']:
                with self.assertRaises(ValueError): machine.action('gpu', mode)
            command.assert_not_called()

    def test_never_disables_last_display(self):
        with patch.object(machine, 'command', return_value=json.dumps([{'name': 'eDP-1', 'disabled': False}])) as command:
            with self.assertRaisesRegex(ValueError, 'at least one'):
                machine.action('display', json.dumps({'name': 'eDP-1', 'enabled': False}))
            self.assertEqual(command.call_count, 1)

    def test_charge_limit_bounds(self):
        for value in ['49', '101', 'bad']:
            with self.assertRaises(ValueError): machine.action('chargeLimit', value)

    def test_profile_edits_and_battery_assignments_persist(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(profiles, 'FILE', Path(directory) / 'profiles.json'):
            profiles.run('edit', json.dumps({'wifi': False, 'brightness': 65}))
            profiles.run('battery', json.dumps({'low': 'Quiet'}))
            data = profiles.load()
            active = next(p for p in data['profiles'] if p['name'] == data['active'])
            self.assertFalse(active['settings']['wifi'])
            self.assertEqual(active['settings']['brightness'], 65)
            self.assertEqual(data['battery']['low'], 'Quiet')
            with self.assertRaises(ValueError): profiles.run('battery', '{"low":"missing"}')

    def test_profile_partial_failure_is_reported(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(profiles, 'FILE', Path(directory) / 'profiles.json'), patch.object(machine, 'action', side_effect=RuntimeError('Unavailable')):
            result = profiles.run('select', 'Quiet')
            self.assertIn('Unavailable', result['error'])
            self.assertEqual(result['data']['active'], 'Quiet')
