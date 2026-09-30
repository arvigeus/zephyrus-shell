import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

from scripts import session


def setup_module():
    spec = importlib.util.spec_from_file_location("session_setup", Path(__file__).resolve().parents[1] / "scripts/setup-session.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SetupTests(unittest.TestCase):
    def test_install_repeat_teardown_preserves_existing_files_and_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config, state = root / "config", root / "state"
            hypr = config / "hypr"
            hypr.mkdir(parents=True)
            original = hypr / "hyprland.lua"
            original.write_text("old-config")
            locker = hypr / "hyprlock.conf"
            locker.symlink_to(root / "previous-lock")
            module = setup_module()
            module.install(config, state, root / "repo with space")
            self.assertIn("repo with space/hyprland/hyprland.lua", original.read_text())
            self.assertEqual((hypr / "hyprland.lua.before-zephyrus").read_text(), "old-config")
            module.install(config, state, root / "repo with space")
            module.teardown(state)
            self.assertEqual(original.read_text(), "old-config")
            self.assertEqual(os.readlink(locker), str(root / "previous-lock"))
            self.assertFalse((hypr / "hypridle.conf").is_symlink())
            self.assertFalse((state / "zephyrus-shell/dev-session.json").exists())

    def test_edited_installation_is_not_deleted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config, state = root / "config", root / "state"
            module = setup_module()
            module.install(config, state, root / "repo")
            path = config / "hypr/hyprland.lua"
            path.write_text("user-edit")
            with self.assertRaisesRegex(ValueError, "edited"):
                module.teardown(state)
            self.assertEqual(path.read_text(), "user-edit")
            self.assertTrue((config / "hypr/hyprlock.conf").is_symlink())

    def test_backup_conflict_stops_before_installing_anything(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config = root / "config"
            (config / "hypr").mkdir(parents=True)
            backup = config / "hypr/hyprlock.conf.before-zephyrus"
            backup.write_text("preserve")
            with self.assertRaisesRegex(ValueError, "backup"):
                setup_module().install(config, root / "state", root / "repo")
            self.assertFalse((config / "hypr/hyprland.lua").exists())
            self.assertEqual(backup.read_text(), "preserve")

    def test_manifest_failure_rolls_back(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config, state = root / "config", root / "state"
            (config / "hypr").mkdir(parents=True)
            path = config / "hypr/hyprland.lua"
            path.write_text("preserve")
            original = Path.write_text
            def write(path, *args, **kwargs):
                if path.name == "dev-session.json":
                    raise OSError("failed manifest")
                return original(path, *args, **kwargs)
            with patch.object(Path, "write_text", write), self.assertRaises(OSError):
                setup_module().install(config, state, root / "repo")
            self.assertEqual(path.read_text(), "preserve")
            self.assertFalse((config / "hypr/hyprlock.conf").is_symlink())


class SessionTests(unittest.TestCase):
    def test_startup_and_compositor_disconnect_clean_up_owned_processes(self):
        with tempfile.TemporaryDirectory() as directory:
            env = {"HYPRLAND_INSTANCE_SIGNATURE": "test-instance", "WAYLAND_DISPLAY": "wayland-test",
                   "XDG_RUNTIME_DIR": directory, "XDG_CONFIG_HOME": str(Path(directory) / "config"), "XDG_CURRENT_DESKTOP": "Hyprland"}
            socket = Mock()
            socket.recv.return_value = b""
            socket_context = Mock()
            socket_context.__enter__ = Mock(return_value=socket)
            socket_context.__exit__ = Mock(return_value=False)
            children = [Mock(pid=101), Mock(pid=102)]
            for child in children:
                child.poll.return_value = None
            inactive = subprocess.CompletedProcess([], 3)
            with patch.dict(os.environ, env), \
                 patch.object(session.socket, "socket", return_value=socket_context), \
                 patch.object(session, "systemctl", return_value=inactive) as systemctl, \
                 patch.object(session.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as run, \
                 patch.object(session.subprocess, "Popen", side_effect=children) as spawn, \
                 patch.object(session.select, "select", return_value=([socket], [], [])), \
                 patch.object(session.os, "killpg") as kill:
                session.run()
            self.assertEqual(spawn.call_args_list[0].args[0][0], "hypridle")
            self.assertEqual(spawn.call_args_list[1].args[0][0], "quickshell")
            self.assertEqual([call.args[0] for call in kill.call_args_list], [102, 101])
            self.assertIn(unittest.mock.call("stop", "hyprpolkitagent.service", check=False), systemctl.call_args_list)
            self.assertIn(unittest.mock.call("restart", *session.PORTALS), systemctl.call_args_list)
            self.assertEqual(run.call_args_list[0].args[0][0], "dbus-update-activation-environment")

    def test_refuses_start_outside_hyprland(self):
        with patch.dict(os.environ, {"HYPRLAND_INSTANCE_SIGNATURE": ""}):
            with self.assertRaisesRegex(RuntimeError, "Hyprland"):
                session.run()

    def test_children_are_force_stopped_only_after_graceful_timeout(self):
        child = Mock(pid=123)
        child.poll.return_value = None
        child.wait.side_effect = [subprocess.TimeoutExpired("test", 5), 0]
        with patch.object(session.os, "killpg") as kill:
            session.stop_child(child)
        self.assertEqual([call.args[1] for call in kill.call_args_list], [session.signal.SIGTERM, session.signal.SIGKILL])


class LockBackgroundTests(unittest.TestCase):
    def test_startup_migrates_existing_wallpaper_with_spaces_and_preserves_new_choice(self):
        from services.wallpaper import sync_lock_background, update_lock_background
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)
            folder = config / "zephyrus-shell"
            folder.mkdir()
            image = config / "wallpaper with spaces.png"
            image.touch()
            (folder / "wallpaper.json").write_text(json.dumps({"image": image.as_uri()}))
            self.assertTrue(sync_lock_background(config))
            self.assertEqual((folder / "lock-wallpaper").resolve(), image)
            other = config / "external desktop.png"
            other.touch()
            update_lock_background(other, config)
            sync_lock_background(config)
            self.assertEqual((folder / "lock-wallpaper").resolve(), other)

    def test_missing_or_remote_background_does_not_create_broken_link(self):
        from services.wallpaper import sync_lock_background
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)
            self.assertFalse(sync_lock_background(config))
            folder = config / "zephyrus-shell"
            folder.mkdir()
            (folder / "wallpaper.json").write_text(json.dumps({"image": "https://example.com/image.png"}))
            self.assertFalse(sync_lock_background(config))
            self.assertFalse((folder / "lock-wallpaper").is_symlink())
