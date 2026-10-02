import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch



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

    def test_legacy_manifest_requires_migration_instead_of_skipping_new_units(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            module = setup_module()
            module.install(root / "config", root / "state", root / "repo")
            manifest = root / "state/zephyrus-shell/dev-session.json"
            data = json.loads(manifest.read_text())
            data["files"] = data["files"][:4]
            manifest.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, "migration"):
                module.install(root / "config", root / "state", root / "repo")

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
