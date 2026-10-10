import base64
import hashlib
import io
import json
import os
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlsplit

from modules.files import local
from modules.files import cloud, transfers
from services import jobs


class Response(io.BytesIO):
    def __init__(self, data=b"", headers=None, code=200):
        super().__init__(data)
        self.headers = headers or {}
        self.code = code


def settled(manager, identifier):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        for job in manager.snapshots()["jobs"]:
            if job["job_id"] == identifier and job["state"] not in ("running", "queued"):
                return job
        time.sleep(0.01)
    raise AssertionError("The job did not settle")


class TransferTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.source = self.home / "source"
        self.source.mkdir()
        self.target = self.home / "destination"
        self.target.mkdir()
        self.patch_home = patch.object(local, "HOME", self.home)
        self.patch_home.start()
        self.addCleanup(self.patch_home.stop)
        self.manager = jobs.Jobs()
        self.addCleanup(self.manager.stop)

    def request(self, path, **extra):
        return {
            "source": "local",
            "destination": "local",
            "path": str(path),
            "target": str(self.target),
            **extra,
        }

    def execute(self, request):
        identifier = self.manager.start("Test transfer", lambda: transfers.transfer(request))[
            "job_id"
        ]
        return settled(self.manager, identifier)

    def test_recursive_copy_keeps_hidden_files_empty_folders_and_existing_destination(self):
        (self.source / ".hidden").write_bytes(b"keep")
        (self.source / "empty").mkdir()
        (self.source / "audio.mka").write_bytes(b"audio")
        (self.target / "source").mkdir()
        result = self.execute(self.request(self.source))
        self.assertEqual(result["state"], "finished")
        copied = self.target / "source (1)"
        self.assertEqual((copied / ".hidden").read_bytes(), b"keep")
        self.assertTrue((copied / "empty").is_dir())
        self.assertEqual((copied / "audio.mka").read_bytes(), b"audio")
        self.assertEqual(list((self.target / "source").iterdir()), [])
        self.assertEqual((result["done"], result["total"]), (9, 9))

    def test_file_collision_and_destination_symlink_preserve_original(self):
        path = self.source / "test.txt"
        path.write_text("new")
        (self.target / "test.txt").symlink_to(path)
        result = self.execute(self.request(path))
        self.assertEqual(result["state"], "finished")
        self.assertEqual((self.target / "test (1).txt").read_text(), "new")
        self.assertTrue((self.target / "test.txt").is_symlink())

    def test_move_trashes_source_only_after_committed_copy(self):
        path = self.source / "test.txt"
        path.write_text("new")
        calls = []

        def trash(source):
            self.assertEqual((self.target / "test.txt").read_text(), "new")
            calls.append(source)

        with patch.object(local, "delete_entry", side_effect=trash):
            result = self.execute(self.request(path, move=True))
        self.assertEqual(result["state"], "finished")
        self.assertEqual(calls, [str(path)])

    def test_changed_local_source_is_not_trashed_after_copy(self):
        source = self.source / "test.txt"
        source.write_text("before")
        original_link = os.link

        def commit(temporary, destination):
            original_link(temporary, destination)
            source.write_text("changed during copy")

        with (
            patch.object(transfers.os, "link", side_effect=commit),
            patch.object(local, "delete_entry") as trash,
        ):
            result = self.execute(self.request(source, move=True))
        self.assertEqual(result["state"], "failed")
        self.assertIn("source changed", result["error"])
        self.assertEqual((self.target / "test.txt").read_text(), "before")
        trash.assert_not_called()

    def test_truncated_cloud_download_is_not_committed(self):
        class Remote:
            def metadata(self, path):
                return cloud.entry("cloud.txt", path, False, 10)

            def download(self, item, sink, update):
                sink.write(b"partial")
                update(7)

        with patch.object(transfers, "provider", return_value=Remote()):
            result = self.execute(self.request("cloud-id", source="nextcloud"))
        self.assertEqual(result["state"], "failed")
        self.assertIn("incomplete", result["error"])
        self.assertEqual(list(self.target.iterdir()), [])

    def test_cloud_move_keeps_folder_when_a_new_child_appears(self):
        calls = []

        class Remote:
            def metadata(self, path):
                return cloud.entry("Folder", path, True)

            def list(self, path, cursor=""):
                calls.append(path)
                return {
                    "entries": []
                    if len(calls) == 1
                    else [cloud.entry("new.txt", "new-id", False, 4)]
                }

            def trash(self, *args):
                raise AssertionError("Changed source must be kept")

        with patch.object(transfers, "provider", return_value=Remote()):
            result = self.execute(self.request("cloud-id", source="gdrive", move=True))
        self.assertEqual(result["state"], "failed")
        self.assertIn("source changed", result["error"])

    def test_shortcut_move_trashes_shortcut_and_preserves_its_target(self):
        trashed = []

        class Remote:
            def metadata(self, path):
                return cloud.entry(
                    "Shortcut.txt", path, False, 4, target_path="target-id", version="1"
                )

            def download(self, item, sink, update):
                sink.write(b"data")
                update(4)

            def trash(self, path, etag=None):
                trashed.append(path)

        with patch.object(transfers, "provider", return_value=Remote()):
            result = self.execute(self.request("shortcut-id", source="gdrive", move=True))
        self.assertEqual(result["state"], "finished")
        self.assertEqual(trashed, ["shortcut-id"])
        self.assertEqual((self.target / "Shortcut.txt").read_bytes(), b"data")

    def test_nested_destination_outside_home_and_folder_symlinks_are_rejected(self):
        (self.source / "loop").symlink_to(self.source)
        for request in (
            self.request(self.source),
            self.request(self.source, target=str(self.source)),
            self.request(self.source, target="/tmp"),
        ):
            with self.subTest(request=request):
                self.assertEqual(self.execute(request)["state"], "failed")
        self.assertEqual(list(self.target.iterdir()), [])

    def test_cancelled_download_does_not_commit_partial_file_or_trash_source(self):
        class Remote:
            def metadata(self, path):
                return cloud.entry("cloud.txt", path, False, 10)

            def download(self, item, sink, update):
                sink.write(b"partial")
                jobs.current_job().cancelled.set()
                update(7)

            def trash(self, path):
                raise AssertionError("Cancelled copy must not remove its source")

        with patch.object(transfers, "provider", return_value=Remote()):
            result = self.execute(self.request("cloud-id", source="gdrive", move=True))
        self.assertEqual(result["state"], "cancelled")
        self.assertEqual(list(self.target.iterdir()), [])

    def test_cloud_folder_into_itself_is_rejected_before_writing(self):
        class Remote:
            def metadata(self, path):
                return cloud.entry(path, path, True)

            def list(self, path, cursor=""):
                return {
                    "entries": [cloud.entry("child", "child", True)] if path == "source-id" else []
                }

            def mkdir(self, *args):
                raise AssertionError("Must not write into the source tree")

        with patch.object(transfers, "provider", return_value=Remote()):
            result = self.execute(
                self.request(
                    "source-id", source="gdrive", destination="gdrive", target="child", move=True
                )
            )
        self.assertEqual(result["state"], "failed")
        self.assertIn("outside", result["error"])

    def test_local_to_cloud_upload_streams_files_and_selects_non_conflicting_name(self):
        path = self.source / "test.txt"
        path.write_bytes(b"content")
        calls = []

        class Remote:
            def metadata(self, path):
                return cloud.entry("Cloud", path, True)

            def list(self, *args):
                return {"entries": [cloud.entry("test.txt", "old", False)]}

            def upload(self, source, parent, name, update):
                calls.append((parent, name, source.read_bytes()))
                update(source.stat().st_size)
                return "new-id"

        with patch.object(transfers, "provider", return_value=Remote()):
            result = self.execute(self.request(path, destination="nextcloud", target="/"))
        self.assertEqual(result["state"], "finished")
        self.assertEqual(calls, [("/", "test (1).txt", b"content")])

    def test_cloud_to_cloud_counts_both_legs_and_cleans_staging(self):
        calls = []

        class Remote:
            def metadata(self, path):
                return cloud.entry("test.txt", path, path == "folder", 4)

            def list(self, *args):
                return {"entries": []}

            def download(self, item, sink, update):
                sink.write(b"data")
                update(4)

            def upload(self, source, parent, name, update):
                self_path = source
                calls.append(self_path)
                self.assert_content = source.read_bytes()
                update(4)
                return "uploaded"

        with patch.object(transfers, "provider", return_value=Remote()):
            result = self.execute(
                self.request("id", source="nextcloud", destination="gdrive", target="folder")
            )
        self.assertEqual(result["state"], "finished")
        self.assertEqual((result["done"], result["total"]), (8, 8))
        self.assertFalse(calls[0].exists())


class CloudTests(unittest.TestCase):
    def test_dav_listing_accepts_only_immediate_children_in_account_scope(self):
        xml = b"""<d:multistatus xmlns:d="DAV:">
          <d:response><d:href>/remote.php/dav/files/me/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
          <d:response><d:href>/remote.php/dav/files/me/A%20B.txt</d:href><d:propstat><d:prop><d:resourcetype/><d:getcontentlength>12</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
          <d:response><d:href>/remote.php/dav/files/other/secret</d:href></d:response>
          <d:response><d:href>/remote.php/dav/files/me/nested/file</d:href><d:propstat><d:prop/><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
        </d:multistatus>"""
        remote = cloud.Nextcloud.__new__(cloud.Nextcloud)
        remote.dav = SimpleNamespace(
            home="https://example.test/remote.php/dav/files/me/",
            allowed=lambda url: url.startswith("https://example.test/remote.php/dav/files/me/"),
        )
        with patch.object(remote, "open", return_value=Response(xml)):
            result = remote.list("/")
        self.assertEqual([x["name"] for x in result["entries"]], ["A B.txt"])
        self.assertEqual(result["entries"][0]["size"], 12)
        with self.assertRaises(ValueError):
            remote.url("/../other/secret")

    def test_nextcloud_upload_uses_exclusive_create_and_streaming_progress(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "upload"
            path.write_bytes(b"a" * (cloud.CHUNK + 17))
            remote = cloud.Nextcloud.__new__(cloud.Nextcloud)
            observed = []

            def upload(method, destination, body, headers):
                self.assertEqual((method, destination), ("PUT", "/upload"))
                self.assertEqual(headers["If-None-Match"], "*")
                self.assertEqual(int(headers["Content-Length"]), path.stat().st_size)
                sizes = []
                while chunk := body.read(cloud.CHUNK):
                    sizes.append(len(chunk))
                self.assertEqual(sizes, [cloud.CHUNK, 17])
                return Response()

            with patch.object(remote, "open", side_effect=upload):
                remote.upload(path, "/", "upload", observed.append)
            self.assertEqual(sum(observed), path.stat().st_size)

    def test_google_listing_preserves_pagination_and_shortcut_identity(self):
        remote = cloud.GoogleDrive()
        item = {
            "id": "shortcut-id",
            "name": "shortcut",
            "mimeType": "application/vnd.google-apps.shortcut",
            "shortcutDetails": {"targetId": "target-id", "targetMimeType": cloud.FOLDER},
        }
        with patch.object(
            remote, "json", return_value={"files": [item], "nextPageToken": "later"}
        ) as request:
            result = remote.list("root", "previous")
        query = parse_qs(urlsplit(request.call_args.args[1]).query)
        self.assertEqual(query["pageToken"], ["previous"])
        self.assertEqual(result["cursor"], "later")
        self.assertEqual(result["entries"][0]["path"], "shortcut-id")
        self.assertEqual(result["entries"][0]["target_path"], "target-id")

    def test_google_upload_uses_bounded_resumable_chunks_and_acknowledgements(self):
        remote = cloud.GoogleDrive()
        observed = []
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "upload"
            path.write_bytes(b"a" * (cloud.CHUNK + 17))

            def upload(method, url, data, headers):
                observed.append((method, url, data, headers))
                if method == "POST":
                    return Response(
                        headers={"Location": "https://www.googleapis.com/upload/session"}
                    )
                if len(observed) == 2:
                    return Response(headers={"Range": f"bytes=0-{cloud.CHUNK - 1}"}, code=308)
                return Response(b'{"id":"new-file"}')

            amounts = []
            with patch.object(remote, "open", side_effect=upload):
                identifier = remote.upload(path, "root", "test.txt", amounts.append)
            self.assertEqual(identifier, "new-file")
            self.assertEqual([len(x[2]) for x in observed[1:]], [cloud.CHUNK, 17])
            self.assertEqual(sum(amounts), path.stat().st_size)
            self.assertEqual(json.loads(observed[0][2])["parents"], ["root"])

    def test_google_workspace_export_and_download_permission(self):
        remote = cloud.GoogleDrive()
        item = cloud.entry(
            "Document", "document", False, mime="application/vnd.google-apps.document"
        )
        self.assertEqual(transfers.download_name(item), "Document.docx")
        with patch.object(remote, "open", return_value=Response(b"content")) as request:
            sink = io.BytesIO()
            remote.download(item, sink, lambda size: None)
        self.assertEqual(sink.getvalue(), b"content")
        self.assertIn("/export?", request.call_args.args[1])
        with self.assertRaisesRegex(ValueError, "disabled"):
            remote.download({**item, "downloadable": False}, io.BytesIO(), lambda size: None)

    def test_google_oauth_uses_pkce_state_and_private_token_storage(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(cloud, "config_root", return_value=Path(directory)),
        ):
            remote = cloud.GoogleDrive()
            callback_status = []
            attempts = []
            browser = Mock()
            browser.return_value.wait.return_value = 0

            class Server:
                server_port = 45555

                def __init__(self, address, handler):
                    self.handler = handler

                def __enter__(self):
                    return self

                def __exit__(self, *args):
                    pass

                def handle_request(self):
                    query = parse_qs(urlsplit(browser.call_args.args[0][1]).query)
                    attempts.append(1)
                    state = "invalid" if len(attempts) == 1 else query["state"][0]
                    fake = SimpleNamespace(
                        path="/?code=authorization&state=" + state,
                        wfile=io.BytesIO(),
                        send_response=callback_status.append,
                        send_header=lambda *args: None,
                        end_headers=lambda: None,
                    )
                    self.handler.do_GET(fake)

            def exchange(values):
                query = parse_qs(urlsplit(browser.call_args.args[0][1]).query)
                challenge = (
                    base64.urlsafe_b64encode(
                        hashlib.sha256(values["code_verifier"].encode()).digest()
                    )
                    .rstrip(b"=")
                    .decode()
                )
                self.assertEqual(query["code_challenge"], [challenge])
                self.assertEqual(query["code_challenge_method"], ["S256"])
                self.assertEqual(values["redirect_uri"], "http://127.0.0.1:45555/")
                self.assertEqual(values["code"], "authorization")
                return {"access_token": "private", "refresh_token": "refresh", "expires_in": 3600}

            with (
                patch.object(
                    remote,
                    "client",
                    return_value={"client_id": "client", "client_secret": "secret"},
                ),
                patch.object(cloud, "HTTPServer", Server),
                patch.object(cloud.subprocess, "Popen", browser),
                patch.object(remote, "token_request", side_effect=exchange),
            ):
                result = remote.connect()
            self.assertEqual(result["provider"], "gdrive")
            self.assertEqual(callback_status, [400, 200])
            self.assertEqual(remote.token_path.stat().st_mode & 0o777, 0o600)

    def test_google_refresh_preserves_refresh_token_and_private_file_mode(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(cloud, "config_root", return_value=Path(directory)),
        ):
            remote = cloud.GoogleDrive()
            remote.token_path.parent.mkdir(parents=True)
            remote.token_path.write_text(json.dumps({"refresh_token": "private", "expires_at": 0}))
            with (
                patch.object(
                    remote,
                    "client",
                    return_value={"client_id": "client", "client_secret": "secret"},
                ),
                patch.object(
                    remote,
                    "token_request",
                    return_value={"access_token": "fresh", "expires_in": 3600},
                ),
            ):
                self.assertEqual(remote.access_token(), "fresh")
            data = json.loads(remote.token_path.read_text())
            self.assertEqual(data["refresh_token"], "private")
            self.assertEqual(remote.token_path.stat().st_mode & 0o777, 0o600)

    def test_google_transport_never_follows_authenticated_redirect_to_other_origin(self):
        remote = cloud.GoogleDrive()
        with patch.object(remote, "access_token", return_value="secret") as token:
            with self.assertRaises(ValueError):
                remote.open("PUT", "https://evil.test/upload")
        token.assert_not_called()
        with self.assertRaises(ValueError):
            cloud.NoRedirect().redirect_request(None, None, 302, "", {}, "https://evil.test")

    def test_google_errors_do_not_expose_response_or_credentials(self):
        remote = cloud.GoogleDrive()
        error = HTTPError(remote.api, 403, "secret message", {}, io.BytesIO(b"private token"))
        with (
            patch.object(remote, "access_token", return_value="private"),
            patch.object(remote.opener, "open", side_effect=error),
        ):
            with self.assertRaises(ValueError) as caught:
                remote.list("root")
        self.assertNotIn("private", str(caught.exception))
        self.assertNotIn("secret message", str(caught.exception))
        error.close()


class JobTests(unittest.TestCase):
    def test_failed_jobs_settle_without_leaking_details(self):
        class ExpectedError(Exception):
            pass

        manager = jobs.Jobs(errors=(ExpectedError, ValueError))
        self.addCleanup(manager.stop)
        identifier = manager.start(
            "Music", lambda: (_ for _ in ()).throw(ExpectedError("Install ffmpeg"))
        )["job_id"]
        result = settled(manager, identifier)
        self.assertEqual(result["error"], "Install ffmpeg")
        identifier = manager.start(
            "Unexpected", lambda: (_ for _ in ()).throw(OSError("sensitive content"))
        )["job_id"]
        result = settled(manager, identifier)
        self.assertNotIn("sensitive", result["error"])

    def test_music_cancel_terminates_process_and_removes_partial_output(self):
        from modules.music import backend as music

        with tempfile.TemporaryDirectory() as directory:
            manager = jobs.Jobs(errors=(music.MusicError, ValueError))
            self.addCleanup(manager.stop)
            process = Mock(returncode=None)
            process.poll = lambda: process.returncode
            process.terminate = lambda: setattr(process, "returncode", -15)
            process.wait = lambda timeout=None: -15

            def communicate(timeout=None):
                jobs.current_job().cancelled.set()
                raise music.subprocess.TimeoutExpired("ffmpeg", timeout)

            process.communicate = communicate
            song = {
                "title": "Track",
                "artist": "Artist",
                "album": "Album",
                "releaseDate": "2020-01-01",
                "duration": 200,
            }
            with (
                patch.object(
                    music, "resolve_track", return_value={"url": "https://example.test/audio"}
                ),
                patch.object(music, "provider_headers", return_value={}),
                patch.object(music.subprocess, "Popen", return_value=process),
            ):
                identifier = manager.start(
                    "Save track", lambda: music.save_stream_track(song, {}, Path(directory))
                )["job_id"]
                result = settled(manager, identifier)
            self.assertEqual(result["state"], "cancelled")
            self.assertEqual(process.returncode, -15)
            self.assertEqual(list(Path(directory).iterdir()), [])
            self.assertNotIn(process, music._download_processes)


if __name__ == "__main__":
    unittest.main()
