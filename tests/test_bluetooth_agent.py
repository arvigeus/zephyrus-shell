import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("bluetooth_pair", Path(__file__).parents[1] / "scripts/bluetooth_pair.py")
pair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pair)


class PairingTests(unittest.TestCase):
    def setUp(self):
        self.agent = pair.Agent.__new__(pair.Agent)
        self.replies = []
        self.errors = []

    def pending(self, kind):
        self.agent.pending = (kind, lambda *args: self.replies.append(args), self.errors.append)

    def test_confirmation_is_never_implicitly_accepted(self):
        self.pending("confirm")
        self.agent.answer({})
        self.assertFalse(self.replies)
        self.assertEqual(len(self.errors), 1)

    def test_passkey_bounds_and_leading_zeroes(self):
        self.pending("passkey")
        self.agent.answer({"accept":True,"value":"000123"})
        self.assertEqual(int(self.replies[0][0]), 123)
        self.pending("passkey")
        self.agent.answer({"accept":True,"value":"1000000"})
        self.assertEqual(len(self.errors), 1)

    def test_pin_length_is_validated(self):
        self.pending("pin")
        self.agent.answer({"accept":True,"value":""})
        self.assertFalse(self.replies)
        self.assertEqual(len(self.errors), 1)
