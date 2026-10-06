"""Default-app cloud opening and durable, conflict-safe editing sessions."""

import io
import json
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import Mock, patch
from urllib.error import HTTPError

from plugins.files import backend, cloud, working_copies
from services.jobs import Jobs


class Response(io.BytesIO):
    def __init__(self, data=b"", headers=None):
        super().__init__(data)
        self.headers = headers or {}


class Remote:
    def __init__(self):
        self.content = b"original"
        self.revision = 1
        self.account = "account"
        self.downloads = 0
        self.writes = []
        self.after_replace = None
        self.after_download = None

    def edit_metadata(self, path):
        return {
            "path": path,
            "name": "Document.txt",
            "size": len(self.content),
            "is_dir": False,
            "etag": str(self.revision),
            "version": str(self.revision),
        }

    def account_key(self):
        return self.account

    def download(self, item, sink, update):
        self.downloads += 1
        sink.write(self.content)
        update(len(self.content))
        if self.after_download:
            self.after_download()

    def replace(self, source, item, update):
        if item["etag"] != str(self.revision):
            raise cloud.EditConflict("Conflict; local edits kept")
        self.content = source.read_bytes()
        self.writes.append(self.content)
        self.revision += 1
        update(len(self.content))
        if self.after_replace:
            self.after_replace()
        return self.edit_metadata(item["path"])


def settled(manager):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        snapshot = manager.snapshots()["jobs"]
        if snapshot and all(j["state"] not in ("queued", "running") for j in snapshot):
            return snapshot[-1]
        time.sleep(0.01)
    raise AssertionError("Jobs did not settle")


class EditingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.jobs = Jobs()
        self.addCleanup(self.jobs.stop)
        self.opener = Mock()
        self.remote = Remote()
        self.directory = Path(self.temp.name) / "copies"
        self.edits = working_copies.WorkingCopies(self.jobs, self.opener, self.directory)
        self.provider = patch.object(working_copies, "provider", return_value=self.remote)
        self.provider.start()
        self.addCleanup(self.provider.stop)

    def open(self):
        result = self.edits.open("nextcloud", "/Document.txt")
        return Path(result["path"])

    def sync(self):
        self.edits.poll()
        self.edits.poll()
        return settled(self.jobs)

    def test_open_downloads_once_and_passes_local_path_to_default_app(self):
        path = self.open()
        self.assertEqual(path.read_bytes(), b"original")
        self.opener.assert_called_with(["xdg-open", str(path)])
        self.assertEqual(self.open(), path)
        self.assertEqual(self.remote.downloads, 1)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.remote.writes, [])

    def test_atomic_editor_save_updates_original_and_advances_revision(self):
        path = self.open()
        replacement = path.with_suffix(".new")
        replacement.write_bytes(b"edited")
        replacement.replace(path)
        self.assertEqual(self.sync()["state"], "finished")
        self.assertEqual(self.remote.writes, [b"edited"])
        path.write_bytes(b"another edit")
        self.sync()
        self.assertEqual(self.remote.writes, [b"edited", b"another edit"])
        self.edits.poll()
        self.edits.poll()
        self.assertEqual(len(self.remote.writes), 2)

    def test_save_during_upload_is_sent_in_next_job(self):
        path = self.open()
        path.write_bytes(b"first save")
        self.remote.after_replace = lambda: path.write_bytes(b"second save")
        self.sync()
        self.remote.after_replace = None
        self.sync()
        self.assertEqual(self.remote.writes, [b"first save", b"second save"])

    def test_cloud_conflict_preserves_both_versions_and_retry_does_not_force(self):
        path = self.open()
        path.write_bytes(b"my edit")
        self.remote.content = b"someone else's edit"
        self.remote.revision += 1
        self.assertEqual(self.sync()["state"], "failed")
        self.assertEqual(self.remote.writes, [])
        self.assertEqual(path.read_bytes(), b"my edit")
        session = self.edits.poll()["sessions"][0]
        self.assertIn(str(path), session["error"])
        self.edits.action(session["job_id"])
        self.assertEqual(self.remote.content, b"someone else's edit")
        self.assertEqual(self.remote.writes, [])
        self.edits.action(session["job_id"], pause=True)
        self.assertFalse(self.edits.poll()["sessions"][0]["active"])

    def test_restart_keeps_unsynced_edits_and_resumes_with_original_revision(self):
        path = self.open()
        path.write_bytes(b"saved while Files was closed")
        self.edits.stop()
        self.edits = working_copies.WorkingCopies(self.jobs, self.opener, self.directory)
        session = self.edits.poll()["sessions"][0]
        self.assertFalse(session["active"])
        self.assertEqual(self.open(), path)
        self.sync()
        self.assertEqual(self.remote.content, b"saved while Files was closed")
        self.assertEqual(self.remote.downloads, 1)

    def test_stopping_flushes_pending_save_and_reopening_fetches_fresh_file(self):
        path = self.open()
        session = self.edits.poll()["sessions"][0]
        path.write_bytes(b"last save")
        self.edits.action(session["job_id"])
        self.sync()
        self.assertEqual(self.edits.poll()["sessions"], [])
        self.assertEqual(path.read_bytes(), b"last save")
        self.remote.content = b"updated after stopping"
        self.remote.revision += 1
        reopened = self.open()
        self.assertNotEqual(reopened, path)
        self.assertEqual(reopened.read_bytes(), self.remote.content)
        self.assertEqual(path.read_bytes(), b"last save")

    def test_account_change_never_receives_previous_account_edits(self):
        path = self.open()
        path.write_bytes(b"private")
        self.remote.account = "other-account"
        self.assertEqual(self.sync()["state"], "failed")
        self.assertEqual(self.remote.writes, [])
        self.assertEqual(path.read_bytes(), b"private")

    def test_cloud_change_during_download_never_launches_stale_copy(self):
        self.remote.after_download = lambda: setattr(self.remote, "revision", 2)
        with self.assertRaises(cloud.EditConflict):
            self.open()
        self.opener.assert_not_called()
        self.assertEqual(self.edits.poll()["sessions"], [])

    def test_network_failure_keeps_copy_and_can_resume(self):
        path = self.open()
        path.write_bytes(b"offline edit")
        with patch.object(self.remote, "replace", side_effect=ValueError("Offline")):
            self.assertEqual(self.sync()["state"], "failed")
        self.assertEqual(path.read_bytes(), b"offline edit")
        self.edits.action(self.edits.poll()["sessions"][0]["job_id"])
        self.sync()
        self.assertEqual(self.remote.content, b"offline edit")

    def test_cancelled_queued_save_can_resume(self):
        path = self.open()
        gate = threading.Event()
        self.addCleanup(gate.set)
        for _ in range(2):
            self.jobs.start("Blocker", lambda: gate.wait(3))
        path.write_bytes(b"queued edit")
        self.edits.poll()
        self.edits.poll()
        save = next(j for j in self.jobs.snapshots()["jobs"] if j["title"] == "Save Document.txt")
        self.jobs.cancel(save["job_id"])
        gate.set()
        settled(self.jobs)
        session = self.edits.poll()["sessions"][0]
        self.assertTrue(session["error"])
        self.assertEqual(self.remote.writes, [])
        self.edits.action(session["job_id"])
        self.sync()
        self.assertEqual(self.remote.content, b"queued edit")

    def test_clean_recovered_copy_fetches_new_cloud_revision(self):
        old = self.open()
        self.edits = working_copies.WorkingCopies(self.jobs, self.opener, self.directory)
        self.remote.content = b"new remote revision"
        self.remote.revision += 1
        new = self.open()
        self.assertNotEqual(old, new)
        self.assertEqual(new.read_bytes(), self.remote.content)
        self.assertEqual(old.read_bytes(), b"original")

    def test_file_named_session_json_does_not_collide_with_manifest(self):
        metadata = self.remote.edit_metadata
        with patch.object(
            self.remote,
            "edit_metadata",
            side_effect=lambda path: {**metadata(path), "name": "session.json"},
        ):
            path = self.open()
        self.assertEqual(path.name, "session.json")
        self.assertEqual(path.read_bytes(), b"original")
        manifest = json.loads((path.parent.parent / "session.json").read_text())
        self.assertEqual(manifest["item"]["name"], "session.json")

    def test_backend_open_uses_owned_jobs_and_real_entry_point(self):
        with patch.object(backend, "EDITS", self.edits), patch.object(backend, "JOBS", self.jobs):
            response = backend.run({"op": "open", "provider": "nextcloud", "path": "/Document.txt"})
            self.assertIn("job_id", response)
            self.assertEqual(settled(self.jobs)["state"], "finished")
            self.assertEqual(len(backend.run({"op": "edit_sessions"})["sessions"]), 1)

    def test_read_only_drive_file_opens_default_app_without_save_back(self):
        metadata = self.remote.edit_metadata
        with patch.object(
            self.remote,
            "edit_metadata",
            side_effect=lambda path: {**metadata(path), "editable": False},
        ):
            result = self.edits.open("gdrive", "file")
        path = Path(result["path"])
        self.assertEqual(path.read_bytes(), b"original")
        self.assertEqual(path.stat().st_mode & 0o777, 0o400)
        self.opener.assert_called_once_with(["xdg-open", str(path)])
        self.assertEqual(self.edits.poll()["sessions"], [])

    def test_google_workspace_opens_browser_without_download_or_edit_session(self):
        with patch.object(
            self.remote,
            "edit_metadata",
            return_value={
                "path": "doc",
                "name": "Doc",
                "is_dir": False,
                "mime": "application/vnd.google-apps.document",
                "web_url": "https://docs.google.com/document/d/doc/edit",
            },
        ):
            self.edits.open("gdrive", "doc")
        self.opener.assert_called_once_with(
            ["xdg-open", "https://docs.google.com/document/d/doc/edit"]
        )
        self.assertEqual(self.remote.downloads, 0)
        self.assertEqual(self.edits.poll()["sessions"], [])


class ProviderEditingTests(unittest.TestCase):
    def test_nextcloud_replace_streams_if_match_and_uses_response_revision(self):
        remote = cloud.Nextcloud.__new__(cloud.Nextcloud)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.txt"
            path.write_bytes(b"a" * (cloud.CHUNK + 9))

            def replace(method, destination, body, headers):
                self.assertEqual((method, destination), ("PUT", "/test.txt"))
                self.assertEqual(headers["If-Match"], '"old"')
                self.assertNotIn("If-None-Match", headers)
                chunks = []
                while chunk := body.read():
                    chunks.append(chunk)
                self.assertEqual([len(c) for c in chunks], [cloud.CHUNK, 9])
                return Response(headers={"ETag": '"new"'})

            with patch.object(remote, "open", side_effect=replace):
                item = remote.replace(
                    path, {"path": "/test.txt", "etag": '"old"'}, lambda count: None
                )
            self.assertEqual(item["etag"], '"new"')

    def test_google_replace_uses_conditional_media_update_of_same_id(self):
        remote = cloud.GoogleDrive()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.txt"
            path.write_bytes(b"changed")

            def replace(method, url, body, headers):
                self.assertEqual(method, "PUT")
                self.assertIn("/upload/drive/v2/files/existing-id?uploadType=media", url)
                self.assertEqual(headers["If-Match"], '"old"')
                self.assertEqual(body.read(), b"changed")
                return Response(b'{"etag":"new","version":"2"}')

            with patch.object(remote, "open", side_effect=replace):
                item = remote.replace(
                    path, {"path": "existing-id", "etag": '"old"'}, lambda count: None
                )
            self.assertEqual(item["version"], "2")

    def test_google_edit_metadata_resolves_shortcut_target_and_acquires_etag(self):
        remote = cloud.GoogleDrive()
        shortcut = {"path": "shortcut", "target_path": "target"}
        target = {"path": "target", "version": "7", "mime": "text/plain"}
        with (
            patch.object(remote, "metadata", side_effect=[shortcut, target]),
            patch.object(remote, "json", return_value={"etag": "revision", "version": "7"}),
        ):
            item = remote.edit_metadata("shortcut")
        self.assertEqual((item["path"], item["etag"]), ("target", "revision"))

    def test_google_precondition_failure_is_edit_conflict(self):
        remote = cloud.GoogleDrive()
        error = HTTPError(remote.upload_api, 412, "Changed", {}, None)
        with (
            patch.object(remote, "access_token", return_value="test"),
            patch.object(remote.opener, "open", side_effect=error),
        ):
            with self.assertRaises(cloud.EditConflict):
                remote.open("PUT", remote.upload_api)

    def test_manifest_references_original_identity_and_contains_no_credentials(self):
        with tempfile.TemporaryDirectory() as directory:
            jobs = Jobs()
            self.addCleanup(jobs.stop)
            edits = working_copies.WorkingCopies(jobs, Mock(), Path(directory))
            with patch.object(working_copies, "provider", return_value=Remote()):
                result = edits.open("nextcloud", "/Document.txt")
            data = json.loads((Path(result["path"]).parent.parent / "session.json").read_text())
            self.assertEqual(data["item"]["path"], "/Document.txt")
            self.assertNotIn("token", data)


if __name__ == "__main__":
    unittest.main()
