import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from modules.files import local as files


class FileTests(unittest.TestCase):
    def test_listing_preserves_sorting_and_symlink_home_boundary(self):
        with tempfile.TemporaryDirectory() as root:
            home = Path(root) / "home"
            home.mkdir()
            folder = home / "folder"
            folder.mkdir()
            (home / "A.txt").write_text("abc")
            (home / ".hidden").touch()
            (home / "inside").symlink_to(folder)
            (home / "outside").symlink_to(root)
            (home / "broken").symlink_to(home / "missing")
            with patch.object(files, "HOME", home):
                entries = files.list_directory(home)["entries"]
                by_name = {entry["name"]: entry for entry in entries}
                self.assertTrue(by_name["inside"]["is_dir"])
                self.assertFalse(by_name["outside"]["is_dir"])
                self.assertNotIn("broken", by_name)
                self.assertTrue(by_name[".hidden"]["hidden"])
                self.assertEqual(by_name["A.txt"]["size_label"], "3 B")
                self.assertEqual([entry["name"] for entry in entries[:2]], ["folder", "inside"])
                with self.assertRaises(ValueError):
                    files.list_directory(home / "outside")

    def test_removal_uses_trash_and_does_not_follow_symlink(self):
        with tempfile.TemporaryDirectory() as root:
            home = Path(root) / "home"
            home.mkdir()
            target = Path(root) / "outside"
            target.write_text("keep")
            link = home / "link"
            link.symlink_to(target)
            with (
                patch.object(files, "HOME", home),
                patch.object(files.shutil, "which", return_value="/usr/bin/gio"),
                patch.object(files.subprocess, "run", return_value=Mock(returncode=0)) as run,
            ):
                result = files.delete_entry(str(link))
            self.assertEqual(run.call_args.args[0], ["/usr/bin/gio", "trash", "--", str(link)])
            self.assertTrue(target.exists())
            self.assertIn("Trash", result["message"])

    def test_home_and_parent_paths_cannot_be_removed(self):
        with tempfile.TemporaryDirectory() as root, patch.object(files, "HOME", Path(root)):
            with self.assertRaises(ValueError):
                files.delete_entry(root)
            with self.assertRaises(ValueError):
                files.delete_entry(root + "/child/..")
