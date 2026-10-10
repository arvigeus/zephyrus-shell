import io
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import HTTPError, URLError

from attention import backend
from attention import nextcloud as calendar
from services import nextcloud as shared


def account():
    return {
        "url": "https://cloud.example/nextcloud/",
        "username": "alice",
        "credentials": {
            "dav": {"provider": "file", "file": "dav-app-password"},
            "music": {"provider": "file", "file": "music-api-key"},
        },
        "capabilities": {"dav": {"credential": "dav"}, "music_subsonic": {"credential": "music"}},
    }


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
        for url in (
            "http://cloud.example/",
            "https://user:secret@cloud.example/",
            "https://cloud.example/?secret=x",
            "https://cloud.example/#fragment",
            "https://cloud.example/a/../",
            "https://cloud.example/%2e%2e/",
            "https:///missing",
        ):
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

    def test_capabilities_select_distinct_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            folder = root / "credentials/nextcloud"
            folder.mkdir(parents=True)
            for name in ("dav-app-password", "music-api-key"):
                (folder / name).write_text(name + "-secret")
                (folder / name).chmod(0o600)
            self.assertEqual(shared.credential(account(), root=root), "dav-app-password-secret")
            self.assertEqual(
                shared.credential(account(), "music_subsonic", root), "music-api-key-secret"
            )
            with self.assertRaisesRegex(shared.NextcloudError, "capability"):
                shared.credential(account(), "missing", root)

    def test_private_files_missing_empty_permissions_and_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            ref = account()["credentials"]["dav"]
            with self.assertRaises(shared.CredentialMissing):
                shared.read_credential(ref, root)
            path = root / "credentials/nextcloud/dav-app-password"
            path.parent.mkdir(parents=True)
            path.write_text("a-test-password\n")
            path.chmod(0o600)
            self.assertEqual(shared.read_credential(ref, root), "a-test-password")
            path.chmod(0o644)
            with self.assertRaisesRegex(shared.NextcloudError, "0600"):
                shared.read_credential(ref, root)
            path.chmod(0o600)
            path.write_text("")
            with self.assertRaisesRegex(shared.NextcloudError, "empty"):
                shared.read_credential(ref, root)
            path.unlink()
            path.symlink_to(root / "elsewhere")
            (root / "elsewhere").write_text("secret")
            with self.assertRaises(shared.NextcloudError):
                shared.read_credential(ref, root)

    def test_dav_scope_and_redirects_never_send_credentials_elsewhere(self):
        opener = unittest.mock.Mock()
        with patch.object(shared, "credential", return_value="test-password"):
            client = calendar.Client(account(), opener=opener)
        self.assertEqual(
            client.home, "https://cloud.example/nextcloud/remote.php/dav/calendars/alice/"
        )
        for url in (
            "http://cloud.example/",
            "https://evil.example/",
            client.home + "../bob/a.ics",
            client.home + "%2e%2e/bob/a.ics",
            client.home + "a.ics?secret=x",
            client.home.replace("alice/", "alice2/"),
        ):
            with self.subTest(url=url), self.assertRaises(shared.NextcloudError):
                client.request("GET", url)
            with self.assertRaises(shared.NextcloudError):
                shared.SameOriginRedirect(client.allowed).redirect_request(
                    None, None, 302, "", {}, url
                )
        opener.open.assert_not_called()

    def test_dav_request_auth_and_error_mapping(self):
        opener = unittest.mock.Mock()
        response = io.BytesIO(b"calendar")
        response.headers = {"ETag": '"1"'}
        opener.open.return_value = response
        with patch.object(shared, "credential", return_value="test-password"):
            client = calendar.Client(account(), opener=opener)
        raw, headers = client.request("GET", client.home + "personal/a.ics")
        self.assertEqual((raw, headers["ETag"]), (b"calendar", '"1"'))
        self.assertTrue(
            opener.open.call_args.args[0].get_header("Authorization").startswith("Basic ")
        )
        for code, message in (
            (401, "rejected"),
            (403, "rejected"),
            (412, "changed"),
            (500, "HTTP 500"),
        ):
            error = HTTPError(client.home, code, "secret server detail", {}, io.BytesIO())
            opener.open.side_effect = error
            with self.assertRaisesRegex(shared.NextcloudError, message):
                client.request("GET", client.home)
            error.close()
        opener.open.side_effect = URLError("secret diagnostic")
        with self.assertRaisesRegex(shared.NextcloudError, "unreachable"):
            client.request("GET", client.home)

    def test_attention_loads_account_and_preserves_calendar_selection(self):
        with (
            patch.object(
                backend,
                "configuration",
                return_value={"calendar": {"calendars": ["Work"], "task_lists": []}},
            ),
            patch.object(shared, "load_account", return_value=account()),
            patch.object(shared, "credential", return_value="secret"),
            patch.object(backend, "cloud_snapshot", return_value={"state": "ready"}) as snapshot,
        ):
            self.assertEqual(backend.handle({"op": "nextcloud"}), {"state": "ready"})
            cloud = snapshot.call_args.args[0]
            self.assertEqual(cloud["url"], account()["url"])
            self.assertEqual((cloud["calendars"], cloud["task_lists"]), (["Work"], []))
            self.assertNotIn("password_file", cloud)

    def test_attention_unconfigured_missing_and_invalid_secret(self):
        with patch.object(backend, "configuration", return_value={}):
            with patch.object(shared, "load_account", return_value=None):
                self.assertEqual(backend.handle({"op": "nextcloud"})["state"], "unconfigured")
            with (
                patch.object(shared, "load_account", return_value=account()),
                patch.object(shared, "credential", side_effect=shared.CredentialMissing("missing")),
            ):
                self.assertEqual(backend.handle({"op": "nextcloud"})["state"], "needs_password")
            with (
                patch.object(shared, "load_account", return_value=account()),
                patch.object(
                    shared, "credential", side_effect=shared.NextcloudError("bad permissions")
                ),
            ):
                with self.assertRaisesRegex(shared.NextcloudError, "permissions"):
                    backend.handle({"op": "nextcloud"})
