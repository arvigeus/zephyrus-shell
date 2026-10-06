import base64
import importlib.util
import os
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from settings import vpn

CONFIG = (
    b"[Interface]\nPrivateKey = "
    + base64.b64encode(b"\x01" * 32)
    + b"\nAddress = 10.0.0.2/32\n[Peer]\nPublicKey = "
    + base64.b64encode(b"\x02" * 32)
    + b"\nAllowedIPs = 0.0.0.0/0\n"
)
UUID = "12345678-1234-1234-1234-123456789abc"


class VpnTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        environment = patch.dict(os.environ, {"XDG_CONFIG_HOME": temporary.name})
        environment.start()
        self.addCleanup(environment.stop)
        self.directory = vpn.config_dir()
        self.directory.mkdir(parents=True)
        self.path = self.directory / "Home VPN.conf"
        self.path.touch(mode=0o600)
        self.path.write_bytes(CONFIG)

    def owned(self, active=False, name="Home VPN.conf"):
        return {
            "uuid": UUID,
            "filename": name,
            "active": active,
            "state": "activated" if active else "",
        }

    def test_discovers_labels_and_permission_errors_without_reading_keys(self):
        self.path.chmod(0o644)
        with (
            patch.object(vpn, "connections", return_value=[]),
            patch.object(vpn.shutil, "which", return_value="nmcli"),
        ):
            result = vpn.snapshot()
        self.assertEqual(result["profiles"][0]["name"], "Home VPN")
        self.assertIn("600", result["profiles"][0]["error"])
        self.assertNotIn("private-test-key", str(result))

    def test_symlinks_and_unrelated_files_are_not_imported(self):
        (self.directory / "Link.conf").symlink_to(self.path)
        (self.directory / "notes.txt").write_text("text")
        with patch.object(vpn, "connections", return_value=[]):
            result = vpn.snapshot()
        self.assertEqual(len(result["profiles"]), 2)
        self.assertIn("symlink", result["profiles"][1]["error"])
        with self.assertRaises(ValueError):
            vpn.read_config(self.directory / "Link.conf")

    def test_missing_directory_and_missing_nmcli_are_valid_states(self):
        with patch.object(vpn.shutil, "which", return_value=None):
            self.assertIn("Install NetworkManager", vpn.snapshot()["error"])
            self.path.unlink()
            self.directory.rmdir()
            self.assertEqual(vpn.snapshot()["profiles"], [])

    def test_only_owned_wireguard_profiles_are_controlled(self):
        output = "\n".join(
            [
                f"{UUID}:wireguard:yes:activated:{vpn.prefix()}Name: with colon.conf",
                f"{UUID}:wireguard:yes:activated:Other VPN",
                f"{UUID}:802-11-wireless:yes:activated:{vpn.prefix()}Home VPN.conf",
                f"{UUID}:wireguard:yes:activated:{vpn.prefix()}../outside.conf",
            ]
        )
        with patch.object(vpn, "nmcli", return_value=output):
            self.assertEqual(vpn.connections(), [self.owned(True, "Name: with colon.conf")])

    def test_removed_active_config_remains_disconnectable(self):
        self.path.unlink()
        with (
            patch.object(vpn, "connections", return_value=[self.owned(True)]),
            patch.object(vpn.shutil, "which", return_value="nmcli"),
        ):
            result = vpn.snapshot()
        self.assertTrue(result["profiles"][0]["active"])
        self.assertIn("removed", result["profiles"][0]["error"])
        with (
            patch.object(vpn, "connections", return_value=[self.owned(True)]),
            patch.object(vpn, "snapshot", return_value={}),
            patch.object(vpn, "nmcli") as cli,
        ):
            vpn.control(self.path.name, "disconnect")
        self.assertEqual(cli.call_args_list[0].args, ("connection", "down", "uuid", UUID))
        self.assertEqual(cli.call_args_list[1].args, ("connection", "delete", "uuid", UUID))

    def test_connect_uses_private_staging_and_reads_source_on_each_connection(self):
        staged_paths = []

        def importer(staged, name):
            staged_paths.append(staged)
            self.assertEqual(staged.read_bytes(), self.path.read_bytes())
            self.assertEqual(staged.stat().st_mode & 0o777, 0o600)
            self.assertLessEqual(len(staged.stem), 15)
            self.assertEqual(name, self.path.name)
            return UUID

        with (
            patch.object(vpn, "connections", return_value=[self.owned()]),
            patch.object(vpn, "snapshot", return_value={"ok": True}),
            patch.object(vpn, "import_profile", side_effect=importer),
            patch.object(vpn, "nmcli") as command,
        ):
            self.assertEqual(vpn.control(self.path.name, "connect"), {"ok": True})
            self.path.write_bytes(CONFIG + b"# edited\n")
            vpn.control(self.path.name, "connect")
        self.assertFalse(staged_paths[0].exists())
        self.assertEqual(command.call_args_list[0].args, ("connection", "delete", "uuid", UUID))
        self.assertEqual(command.call_args_list[-1].args, ("connection", "up", "uuid", UUID))

    @unittest.skipUnless(importlib.util.find_spec("gi"), "Python GObject bindings unavailable")
    def test_real_parser_adds_private_temporary_profile_atomically(self):
        import gi

        gi.require_version("NM", "1.0")
        from gi.repository import NM, Gio  # ty: ignore[unresolved-import]

        staged = self.directory / "zwgtest.conf"
        staged.write_bytes(CONFIG)
        bus = Mock()
        with patch.object(Gio, "bus_get_sync", return_value=bus):
            uuid = vpn.import_profile(staged, self.path.name)
        arguments = bus.call_sync.call_args.args
        self.assertEqual(arguments[3], "AddConnection2")
        settings, flags, options = arguments[4].unpack()
        self.assertEqual(
            flags,
            int(
                NM.SettingsAddConnection2Flags.IN_MEMORY
                | NM.SettingsAddConnection2Flags.BLOCK_AUTOCONNECT
            ),
        )
        self.assertEqual(settings["connection"]["uuid"], uuid)
        self.assertFalse(settings["connection"]["autoconnect"])
        self.assertEqual(len(settings["connection"]["permissions"]), 1)
        self.assertTrue(settings["connection"]["permissions"][0].startswith("user:"))
        self.assertEqual(settings["connection"]["id"], vpn.prefix() + self.path.name)

    def test_failed_activation_is_cleaned(self):
        def cli(*args, **kwargs):
            if "up" in args:
                raise ValueError("Denied")
            return ""

        with (
            patch.object(vpn, "connections", return_value=[]),
            patch.object(vpn, "import_profile", return_value=UUID),
            patch.object(vpn, "nmcli", side_effect=cli) as command,
        ):
            with self.assertRaisesRegex(ValueError, "Denied"):
                vpn.control(self.path.name, "connect")
        self.assertEqual(command.call_args_list[-1].args, ("connection", "delete", "uuid", UUID))
        self.assertEqual(sum("up" in call.args for call in command.call_args_list), 1)

    @unittest.skipUnless(importlib.util.find_spec("gi"), "Python GObject bindings unavailable")
    def test_invalid_private_key_is_redacted_by_real_parser(self):
        staged = self.directory / "zwgtest.conf"
        staged.write_text(
            "[Interface]\nPrivateKey = private-test-key\n[Peer]\nPublicKey = invalid\n"
        )
        with self.assertRaises(ValueError) as failure:
            vpn.import_profile(staged, self.path.name)
        self.assertNotIn("private-test-key", str(failure.exception))
        self.assertNotIn("invalid", str(failure.exception))

    def test_active_connect_is_idempotent(self):
        with (
            patch.object(vpn, "connections", return_value=[self.owned(True)]),
            patch.object(vpn, "snapshot", return_value={}),
            patch.object(vpn, "nmcli") as command,
        ):
            vpn.control(self.path.name, "connect")
        command.assert_not_called()

    def test_traversal_and_insecure_configs_are_rejected_before_import(self):
        for name in ("../outside.conf", "/outside.conf", "bad\n.conf", None, ".conf"):
            with (
                self.subTest(name=name),
                self.assertRaises(ValueError),
                patch.object(vpn, "nmcli") as command,
            ):
                vpn.control(name, "connect")
            command.assert_not_called()
        self.path.chmod(0o644)
        with (
            patch.object(vpn, "connections", return_value=[]),
            patch.object(vpn, "nmcli") as command,
        ):
            with self.assertRaisesRegex(ValueError, "600"):
                vpn.control(self.path.name, "connect")
        command.assert_not_called()

    def test_hooks_and_oversized_configs_are_rejected(self):
        for field in ("PreUp", "PostUp", "PreDown", "PostDown", "SaveConfig", "Table"):
            self.path.write_bytes(CONFIG + f"{field} = private-test-key\n".encode())
            with (
                self.subTest(field=field),
                self.assertRaisesRegex(ValueError, "NetworkManager-compatible"),
            ):
                vpn.read_config(self.path)
        self.path.write_bytes(b"x" * (vpn.MAX_CONFIG_BYTES + 1))
        with self.assertRaisesRegex(ValueError, "too large"):
            vpn.read_config(self.path)

    def test_command_errors_never_expose_secret_diagnostics(self):
        result = subprocess.CompletedProcess([], 1, "", "Invalid private-test-key")
        with patch.object(vpn.subprocess, "run", return_value=result):
            with self.assertRaises(ValueError) as failure:
                vpn.nmcli("connection", "up")
        self.assertNotIn("private-test-key", str(failure.exception))
        with patch.object(
            vpn.subprocess, "run", side_effect=subprocess.TimeoutExpired("nmcli", 40)
        ):
            with self.assertRaisesRegex(ValueError, "timed out"):
                vpn.nmcli("connection", "up")
