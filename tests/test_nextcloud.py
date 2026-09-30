import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError

from attention import backend, nextcloud as calendar
from services import nextcloud as shared


def migration_module():
    spec = importlib.util.spec_from_file_location("migrate_nextcloud", Path(__file__).resolve().parents[1] / "scripts/migrate-nextcloud.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def account():
    return {"url": "https://cloud.example/nextcloud/", "username": "alice",
            "credentials": {"dav": {"provider": "file", "file": "dav-app-password"},
                            "music": {"provider": "file", "file": "music-api-key"}},
            "capabilities": {"dav": {"credential": "dav"}, "music_subsonic": {"credential": "music"}}}


class AccountTests(unittest.TestCase):
    def test_missing_and_invalid_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assertIsNone(shared.load_account(root))
            for data in ("{", "[]", '{"url":"http://cloud.example", "username":"alice"}'):
                (root / "nextcloud.json").write_text(data)
                with self.assertRaises(shared.NextcloudError):
                    shared.load_account(root)

    def test_instance_and_credential_references_validation(self):
        for url in ("http://cloud.example/", "https://user:secret@cloud.example/",
                    "https://cloud.example/?secret=x", "https://cloud.example/#fragment",
                    "https://cloud.example/a/../", "https://cloud.example/%2e%2e/", "https:///missing"):
            with self.subTest(url=url), self.assertRaises(shared.NextcloudError):
                shared.validate_account({**account(), "url": url})
        for file in ("/tmp/password", "../password", "a/../password", "", "a/./password"):
            value = account()
            value["credentials"]["dav"]["file"] = file
            with self.subTest(file=file), self.assertRaises(shared.NextcloudError):
                shared.validate_account(value)
        value = account()
        value["capabilities"]["dav"]["credential"] = "missing"
        with self.assertRaises(shared.NextcloudError):
            shared.validate_account(value)
        value["capabilities"]["dav"]["credential"] = ["dav"]
        with self.assertRaises(shared.NextcloudError):
            shared.validate_account(value)

    def test_provider_is_replaceable_and_music_is_distinct(self):
        class Provider:
            def read(self, reference):
                return reference["file"]
        self.assertEqual(shared.credential(account(), provider=Provider()), "dav-app-password")
        self.assertEqual(shared.credential(account(), "music_subsonic", Provider()), "music-api-key")

    def test_private_files_missing_empty_permissions_and_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            provider = shared.FileCredentials(root)
            ref = account()["credentials"]["dav"]
            with self.assertRaises(shared.CredentialMissing):
                provider.read(ref)
            path = root / "credentials/nextcloud/dav-app-password"
            path.parent.mkdir(parents=True)
            path.write_text("a-test-password\n")
            path.chmod(0o600)
            self.assertEqual(provider.read(ref), "a-test-password")
            path.chmod(0o644)
            with self.assertRaisesRegex(shared.NextcloudError, "0600"):
                provider.read(ref)
            path.chmod(0o600)
            path.write_text("")
            with self.assertRaisesRegex(shared.NextcloudError, "empty"):
                provider.read(ref)
            path.unlink()
            path.symlink_to(root / "elsewhere")
            (root / "elsewhere").write_text("secret")
            with self.assertRaises(shared.NextcloudError):
                provider.read(ref)

    def test_dav_scope_and_redirects_never_send_credentials_elsewhere(self):
        provider = unittest.mock.Mock()
        provider.read.return_value = "test-password"
        opener = unittest.mock.Mock()
        client = calendar.Client(account(), provider=provider, opener=opener)
        self.assertEqual(client.home, "https://cloud.example/nextcloud/remote.php/dav/calendars/alice/")
        for url in ("http://cloud.example/", "https://evil.example/", client.home + "../bob/a.ics",
                    client.home + "%2e%2e/bob/a.ics", client.home + "a.ics?secret=x",
                    client.home.replace("alice/", "alice2/")):
            with self.subTest(url=url), self.assertRaises(shared.NextcloudError):
                client.request("GET", url)
            with self.assertRaises(shared.NextcloudError):
                shared.SameOriginRedirect(client.allowed).redirect_request(None, None, 302, "", {}, url)
        opener.open.assert_not_called()

    def test_dav_request_auth_and_error_mapping(self):
        provider = unittest.mock.Mock()
        provider.read.return_value = "test-password"
        opener = unittest.mock.Mock()
        response = io.BytesIO(b"calendar")
        response.headers = {"ETag": '"1"'}
        opener.open.return_value = response
        client = calendar.Client(account(), provider=provider, opener=opener)
        raw, headers = client.request("GET", client.home + "personal/a.ics")
        self.assertEqual((raw, headers["ETag"]), (b"calendar", '"1"'))
        self.assertTrue(opener.open.call_args.args[0].get_header("Authorization").startswith("Basic "))
        for code, message in ((401, "rejected"), (403, "rejected"), (412, "changed"), (500, "HTTP 500")):
            error = HTTPError(client.home, code, "secret server detail", {}, io.BytesIO())
            opener.open.side_effect = error
            with self.assertRaisesRegex(shared.NextcloudError, message):
                client.request("GET", client.home)
            error.close()
        opener.open.side_effect = URLError("secret diagnostic")
        with self.assertRaisesRegex(shared.NextcloudError, "unreachable"):
            client.request("GET", client.home)

    def test_attention_loads_account_and_preserves_calendar_selection(self):
        with patch.object(backend, "configuration", return_value={"calendar": {"calendars": ["Work"], "task_lists": []}}), \
             patch.object(shared, "load_account", return_value=account()), \
             patch.object(shared, "credential", return_value="secret"), \
             patch.object(backend, "cloud_snapshot", return_value={"state": "ready"}) as snapshot:
            self.assertEqual(backend.handle({"op": "nextcloud"}), {"state": "ready"})
            cloud = snapshot.call_args.args[0]
            self.assertEqual(cloud["url"], account()["url"])
            self.assertEqual((cloud["calendars"], cloud["task_lists"]), (["Work"], []))
            self.assertNotIn("password_file", cloud)

    def test_attention_unconfigured_missing_and_invalid_secret(self):
        with patch.object(backend, "configuration", return_value={}):
            with patch.object(shared, "load_account", return_value=None):
                self.assertEqual(backend.handle({"op": "nextcloud"})["state"], "unconfigured")
            with patch.object(shared, "load_account", return_value=account()), \
                 patch.object(shared, "credential", side_effect=shared.CredentialMissing("missing")):
                self.assertEqual(backend.handle({"op": "nextcloud"})["state"], "needs_password")
            with patch.object(shared, "load_account", return_value=account()), \
                 patch.object(shared, "credential", side_effect=shared.NextcloudError("bad permissions")):
                with self.assertRaisesRegex(shared.NextcloudError, "permissions"):
                    backend.handle({"op": "nextcloud"})


class MigrationTests(unittest.TestCase):
    def prepare(self, root):
        (root / "attention.json").write_text(json.dumps({"weather": {"name": "keep"}, "nextcloud": {
            "url": account()["url"], "username": "alice", "password_file": str(root / "nextcloud-app-password"),
            "calendars": ["Work"], "task_lists": []}}))
        (root / "nextcloud-app-password").write_text("test-dav")
        (root / "nextcloud-music-password").write_text("test-music-api-key")

    def test_migration_permissions_selection_and_idempotency(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.prepare(root)
            migrate = migration_module().migrate
            self.assertTrue(migrate(root))
            data = shared.load_account(root)
            provider = shared.FileCredentials(root)
            self.assertEqual(shared.credential(data, provider=provider), "test-dav")
            self.assertEqual(shared.credential(data, "music_subsonic", provider), "test-music-api-key")
            attention = json.loads((root / "attention.json").read_text())
            self.assertEqual(attention, {"weather": {"name": "keep"}, "calendar": {"calendars": ["Work"], "task_lists": []}})
            self.assertFalse((root / "nextcloud-app-password").exists())
            self.assertFalse((root / "nextcloud-music-password").exists())
            self.assertEqual((root / "credentials/nextcloud").stat().st_mode & 0o777, 0o700)
            self.assertEqual((root / "credentials/nextcloud/dav-app-password").stat().st_mode & 0o777, 0o600)
            self.assertNotIn("test-dav", (root / "nextcloud.json").read_text())
            self.assertTrue(migrate(root))

    def test_conflict_leaves_originals_untouched(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.prepare(root)
            destination = root / "credentials/nextcloud/music-api-key"
            destination.parent.mkdir(parents=True)
            destination.write_text("different")
            with self.assertRaisesRegex(shared.NextcloudError, "differs"):
                migration_module().migrate(root)
            self.assertTrue((root / "nextcloud-app-password").exists())
            self.assertFalse((destination.parent / "dav-app-password").exists())
            self.assertFalse((root / "nextcloud.json").exists())

    def test_interrupted_migration_can_resume(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.prepare(root)
            module = migration_module()
            original = module.write_private
            def interrupted(path, data):
                if path.name == "attention.json":
                    raise OSError("interrupted")
                original(path, data)
            with patch.object(module, "write_private", side_effect=interrupted), self.assertRaises(OSError):
                module.migrate(root)
            self.assertTrue((root / "nextcloud-app-password").exists())
            self.assertTrue(module.migrate(root))
            self.assertFalse((root / "nextcloud-app-password").exists())

    def test_other_account_is_never_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.prepare(root)
            value = {**account(), "username": "someone-else"}
            (root / "nextcloud.json").write_text(json.dumps(value))
            with self.assertRaisesRegex(shared.NextcloudError, "different account"):
                migration_module().migrate(root)
            self.assertTrue((root / "nextcloud-app-password").exists())

    def test_missing_legacy_account_does_not_move_secrets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.assertFalse(migration_module().migrate(root))
            (root / "nextcloud-app-password").write_text("test-dav")
            with self.assertRaisesRegex(shared.NextcloudError, "URL and username"):
                migration_module().migrate(root)
            self.assertTrue((root / "nextcloud-app-password").exists())
