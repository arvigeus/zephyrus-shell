import importlib.util
import json
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.dont_write_bytecode = True
path = Path(__file__).parents[1] / "scripts/warp.py"
spec = importlib.util.spec_from_file_location("warp", path)
warp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(warp)


def result(output="", code=0):
    return subprocess.CompletedProcess([], code, output, "")


class WarpTests(unittest.TestCase):
    def test_off_status_never_contacts_or_starts_daemon(self):
        with (
            patch.object(warp.shutil, "which", return_value="/usr/bin/warp-cli"),
            patch.object(warp, "unit_state", return_value="inactive"),
            patch.object(warp, "cli") as cli,
        ):
            self.assertEqual(warp.status()["state"], "off")
            cli.assert_not_called()

    def test_connect_and_disconnect_use_only_authorized_wrapper(self):
        with (
            patch.object(warp, "run", return_value=result()) as run,
            patch.object(warp, "status", return_value={"enabled": False}),
        ):
            warp.action("connect")
            run.assert_called_once_with(
                ["systemctl", "--no-ask-password", "start", warp.UNIT], timeout=90
            )
            run.reset_mock()
            warp.action("disconnect")
            run.assert_called_once_with(
                ["systemctl", "--no-ask-password", "stop", warp.UNIT], timeout=90
            )

    def test_failed_start_is_an_error_not_success(self):
        with (
            patch.object(warp, "run", return_value=result("Access denied", 1)),
            self.assertRaisesRegex(RuntimeError, "Access denied"),
        ):
            warp.action("connect")

    def test_registration_before_exclusions_and_connect(self):
        calls = []

        def cli(*args):
            calls.append(args)
            if args == ("--json", "registration", "show"):
                return result(json.dumps({"code": "MissingRegistration"}), 1)
            return result("{}" if args == ("--json", "status") else "Success")

        with (
            patch.object(warp.os, "geteuid", return_value=0),
            patch.object(warp, "cli", side_effect=cli),
        ):
            warp.prepare()
        self.assertLess(calls.index(("registration", "new")), calls.index(("mode", "warp+doh")))
        self.assertEqual(calls[-1], ("connect",))
        for subnet in warp.LAN_RANGES:
            self.assertIn(("--json", "tunnel", "ip", "add-range", subnet), calls)

    def test_api_error_does_not_replace_existing_registration(self):
        calls = []

        def cli(*args):
            calls.append(args)
            if args == ("--json", "registration", "show"):
                return result(json.dumps({"code": "ApiError"}), 1)
            return result("{}")

        with (
            patch.object(warp.os, "geteuid", return_value=0),
            patch.object(warp, "cli", side_effect=cli),
            self.assertRaises(RuntimeError),
        ):
            warp.prepare()
        self.assertNotIn(("registration", "new"), calls)
        self.assertNotIn(("connect",), calls)

    def test_existing_exclusions_and_registration_are_idempotent(self):
        def cli(*args):
            return result("\n".join(warp.LAN_RANGES) if args == ("tunnel", "ip", "list") else "{}")

        with (
            patch.object(warp.os, "geteuid", return_value=0),
            patch.object(warp, "cli", side_effect=cli) as call,
        ):
            warp.prepare()
        self.assertNotIn(unittest.mock.call("registration", "new"), call.call_args_list)
        self.assertFalse(any("add-range" in args.args for args in call.call_args_list))

    def test_lan_policy_failure_prevents_connection(self):
        def cli(*args):
            return result("Policy forbids exclusions", 1) if "add-range" in args else result("{}")

        with (
            patch.object(warp.os, "geteuid", return_value=0),
            patch.object(warp, "cli", side_effect=cli) as call,
            self.assertRaisesRegex(RuntimeError, "Policy forbids"),
        ):
            warp.prepare()
        self.assertNotIn(unittest.mock.call("connect"), call.call_args_list)

    def test_connected_status_and_toggle(self):
        with (
            patch.object(warp.shutil, "which", return_value="/usr/bin/warp-cli"),
            patch.object(warp, "unit_state", return_value="active"),
            patch.object(warp, "cli", return_value=result("Status update: Connected\n")),
            patch.object(warp, "run", return_value=result()) as run,
        ):
            self.assertEqual(warp.status()["state"], "connected")
            warp.action("toggle")
            self.assertEqual(
                run.call_args.args[0],
                ["systemctl", "--no-ask-password", "stop", warp.UNIT],
            )

    def test_daemon_reported_duplicates_are_harmless(self):
        def cli(*args):
            return result('{"code":"AlreadyExists"}', 1) if "add-range" in args else result("{}")

        with (
            patch.object(warp.os, "geteuid", return_value=0),
            patch.object(warp, "cli", side_effect=cli) as call,
        ):
            warp.prepare()
        self.assertIn(unittest.mock.call("connect"), call.call_args_list)

    def test_cli_errors_on_stderr_wait_for_ipc_and_register_if_missing(self):
        attempts = 0

        def cli(*args):
            nonlocal attempts
            if args == ("--json", "status"):
                attempts += 1
                if attempts == 1:
                    return subprocess.CompletedProcess(
                        [], 1, "", '{"code":"FailedToConnectToDaemon"}'
                    )
            if args == ("--json", "registration", "show"):
                return subprocess.CompletedProcess([], 1, "", '{"code":"MissingRegistration"}')
            if "add-range" in args:
                return subprocess.CompletedProcess([], 1, "", '{"code":"AlreadyExists"}')
            return result("{}")

        with (
            patch.object(warp.os, "geteuid", return_value=0),
            patch.object(warp, "cli", side_effect=cli) as call,
            patch.object(warp.time, "sleep") as sleep,
        ):
            warp.prepare()
        self.assertEqual(attempts, 2)
        sleep.assert_called_once()
        self.assertIn(unittest.mock.call("registration", "new"), call.call_args_list)
        self.assertIn(unittest.mock.call("connect"), call.call_args_list)


class WarpSetupTests(unittest.TestCase):
    def test_offline_setup_scopes_policy_and_never_starts_services(self):
        import tempfile
        from types import SimpleNamespace
        from unittest.mock import Mock

        spec = importlib.util.spec_from_file_location("warp_setup", path.with_name("warp_setup.py"))
        setup = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(setup)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            unit = root / "usr/lib/systemd/system/zephyrus-warp.service"
            unit.parent.mkdir(parents=True)
            unit.touch()
            asset = root / "usr/share/zephyrus-shell/systemd/system/warp-on-demand.conf"
            asset.parent.mkdir(parents=True)
            asset.write_text("[Unit]\nPartOf=zephyrus-warp.service\nStopWhenUnneeded=yes\n")
            runner = Mock()
            setup.configure(
                'desktop"user',
                offline=True,
                root=root,
                runner=runner,
                user_lookup=lambda _: SimpleNamespace(pw_uid=1000),
                effective_uid=0,
            )
            policy = (root / "etc/polkit-1/rules.d/90-zephyrus-warp.rules").read_text()
            self.assertIn('subject.user == "desktop\\"user"', policy)
            self.assertIn('"zephyrus-warp.service"', policy)
            self.assertNotIn("manage-unit-files", policy)
            self.assertNotIn("wheel", policy)
            runner.assert_called_once_with(["systemctl", "disable", "warp-svc.service"], check=True)

    def test_nonroot_cannot_write_authorization(self):
        spec = importlib.util.spec_from_file_location("warp_setup", path.with_name("warp_setup.py"))
        setup = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(setup)
        with self.assertRaises(PermissionError):
            setup.configure("tester", effective_uid=1000)


class WarpWatcherTests(unittest.TestCase):
    def setUp(self):
        import sys
        from unittest.mock import Mock

        sys.path.insert(0, str(path.parent))
        import warp_watch

        self.module = warp_watch
        self.emit = Mock()
        self.glib = Mock()
        self.watcher = warp_watch.Watcher(Mock(), self.glib, self.emit)
        self.watcher.paths = {"/owner": warp.UNIT, "/daemon": warp_watch.DAEMON}

    def test_off_daemon_never_spawns_cli_or_schedules_refresh(self):
        with patch.object(self.module.subprocess, "Popen") as popen:
            self.watcher.sync()
            self.watcher.sync()
            popen.assert_not_called()
        self.glib.timeout_add.assert_not_called()
        self.assertEqual(self.emit.call_count, 1)
        self.assertEqual(self.emit.call_args.args[0]["state"], "off")

    def test_delayed_connected_event_and_settings_notification(self):
        self.watcher.states = {warp.UNIT: "active", self.module.DAEMON: "active"}
        self.watcher.receive("Status update: Connecting")
        self.assertEqual(self.emit.call_args.args[0]["state"], "connecting")
        self.watcher.receive("Status update: Connected")
        self.assertEqual(self.emit.call_args.args[0]["state"], "connected")
        self.watcher.receive("Status update: Settings Updated")
        self.assertEqual(self.emit.call_count, 2)

    def test_inactive_signal_releases_listener_and_clears_connected(self):
        from unittest.mock import Mock

        child = Mock()
        self.watcher.child = child
        self.watcher.states = {warp.UNIT: "active", self.module.DAEMON: "active"}
        self.watcher.connection = "connected"
        self.watcher.changed(
            "org.freedesktop.systemd1.Unit", {"ActiveState": "inactive"}, [], "/daemon"
        )
        child.terminate.assert_called_once()
        child.wait.assert_called_once_with(timeout=2)
        self.assertEqual(self.emit.call_args.args[0]["state"], "off")

    def test_unrelated_properties_do_not_trigger_work(self):
        with patch.object(self.watcher, "sync") as sync:
            self.watcher.changed(
                "org.freedesktop.systemd1.Unit", {"ActiveState": "active"}, [], "/unrelated"
            )
            self.watcher.changed(
                "org.freedesktop.systemd1.Service", {"ActiveState": "active"}, [], "/daemon"
            )
            self.watcher.changed(
                "org.freedesktop.systemd1.Unit", {"Description": "different"}, [], "/daemon"
            )
            sync.assert_not_called()


if __name__ == "__main__":
    unittest.main()
