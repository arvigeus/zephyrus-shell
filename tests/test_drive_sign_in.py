import io
import json
import socket
import tempfile
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import Mock, patch
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import urlopen

from plugins.files import cloud
from plugins.files.drive_sign_in import DriveSignIn
from services.jobs import Jobs
from services.worker import serve


class DriveSignInTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.config = patch.object(cloud, "config_root", return_value=Path(self.temp.name))
        self.config.start()
        self.addCleanup(self.config.stop)
        self.client = patch.object(
            cloud.GoogleDrive,
            "client",
            return_value={"client_id": "fixture", "client_secret": "fixture"},
        )
        self.client.start()
        self.addCleanup(self.client.stop)
        self.exchange = patch.object(
            cloud.GoogleDrive,
            "token_request",
            return_value={
                "access_token": "fixture",
                "refresh_token": "fixture",
                "expires_in": 3600,
            },
        )
        self.exchange.start()
        self.addCleanup(self.exchange.stop)
        self.manager = Jobs()
        self.addCleanup(self.manager.stop)
        self.sign_in = DriveSignIn(self.manager)
        self.opened = threading.Event()
        self.urls = []

        def open_browser(url):
            self.urls.append(url)
            self.opened.set()

        self.browser = patch.object(cloud.GoogleDrive, "open_browser", side_effect=open_browser)
        self.browser.start()
        self.addCleanup(self.browser.stop)

    def start(self):
        self.opened.clear()
        identifier = self.sign_in.start_or_reopen()["job_id"]
        self.assertTrue(self.opened.wait(2), "The browser was never opened")
        return identifier

    def settle(self, identifier):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            job = next(j for j in self.manager.snapshots()["jobs"] if j["job_id"] == identifier)
            if job["state"] not in ("queued", "running"):
                return job
            time.sleep(0.01)
        self.fail("Sign-in did not settle")

    def callback(self, url=None, **values):
        query = parse_qs(urlsplit(url or self.urls[-1]).query)
        return (
            query["redirect_uri"][0]
            + "?"
            + urlencode({"state": query["state"][0], "code": "fixture", **values})
        )

    def test_real_loopback_callback_reopen_same_job_and_private_token(self):
        identifier = self.start()
        result = self.sign_in.start_or_reopen()
        self.assertEqual(result, {"job_id": identifier, "reused": True})
        self.assertEqual(len(self.manager.snapshots()["jobs"]), 1)
        self.assertEqual(self.urls[0], self.urls[1])
        with urlopen(self.callback(), timeout=4) as response:
            self.assertEqual(response.status, 200)
            self.assertNotIn(b"fixture", response.read())
        self.assertEqual(self.settle(identifier)["state"], "finished")
        token = cloud.GoogleDrive().token_path
        self.assertEqual(token.stat().st_mode & 0o777, 0o600)
        self.assertEqual(json.loads(token.read_text())["access_token"], "fixture")

    def test_waiting_for_consent_does_not_block_token_access_or_cancellation(self):
        identifier = self.start()
        executor = ThreadPoolExecutor(max_workers=1)
        try:
            future = executor.submit(cloud.GoogleDrive().access_token)
            with self.assertRaisesRegex(ValueError, "Connect Google Drive"):
                future.result(timeout=1)
        finally:
            self.manager.cancel(identifier)
            self.assertEqual(self.settle(identifier)["error"], "Google sign-in cancelled.")
            executor.shutdown()
        with self.assertRaisesRegex(ValueError, "expired"):
            self.sign_in.complete(self.callback())
        self.assertFalse(cloud.GoogleDrive().token_path.exists())

    def test_cancelled_attempt_can_restart_and_old_callback_is_rejected(self):
        first = self.start()
        old_callback = self.callback()
        self.manager.cancel(first)
        second = self.start()
        self.assertNotEqual(first, second)
        with self.assertRaisesRegex(ValueError, "current sign-in attempt") as error:
            self.sign_in.complete(old_callback)
        self.assertNotIn(old_callback, str(error.exception))
        self.sign_in.complete(self.callback())
        self.assertEqual(self.settle(first)["state"], "cancelled")
        self.assertEqual(self.settle(second)["state"], "finished")

    def test_manual_fallback_validates_origin_state_and_duplicate_fields(self):
        identifier = self.start()
        valid = self.callback()
        for invalid in (
            valid.replace("127.0.0.1", "example.com"),
            valid.replace("http:", "https:"),
            self.callback(state="wrong"),
            self.callback(state="invalid-非-ascii"),
            valid + "&state=wrong",
            valid + "&error=access_denied",
            "not a callback",
        ):
            with self.assertRaisesRegex(ValueError, "current sign-in attempt") as error:
                self.sign_in.complete(invalid)
            self.assertNotIn(invalid, str(error.exception))
        self.sign_in.complete(valid)
        self.assertEqual(self.settle(identifier)["state"], "finished")

    def test_half_open_browser_connection_cannot_stall_callback(self):
        identifier = self.start()
        redirect = urlsplit(parse_qs(urlsplit(self.urls[-1]).query)["redirect_uri"][0])
        with socket.create_connection((redirect.hostname, redirect.port), timeout=1) as stalled:
            stalled.sendall(b"GET / HTTP/1.1\r\n")
            time.sleep(0.1)
            with urlopen(self.callback(), timeout=5) as response:
                self.assertEqual(response.status, 200)
        self.assertEqual(self.settle(identifier)["state"], "finished")

    def test_expired_attempt_restarts_and_browser_launch_failure_is_retryable(self):
        original = cloud.GoogleDrive.connect

        def short_attempt(remote, **args):
            return original(remote, timeout=0.05, **args)

        with patch.object(cloud.GoogleDrive, "connect", short_attempt):
            first = self.start()
            self.assertIn("timed out", self.settle(first)["error"])
        with patch.object(
            cloud.GoogleDrive,
            "open_browser",
            side_effect=ValueError("Could not open your browser."),
        ):
            second = self.sign_in.start_or_reopen()["job_id"]
            self.assertIn("Could not open", self.settle(second)["error"])
        third = self.start()
        self.assertEqual(len({first, second, third}), 3)
        self.sign_in.complete(self.callback())
        self.assertEqual(self.settle(third)["state"], "finished")

    def test_launcher_reports_nonzero_exit_without_logging_authorization_url(self):
        self.browser.stop()
        process = Mock()
        process.wait.return_value = 1
        with patch.object(cloud.subprocess, "Popen", return_value=process):
            with self.assertRaisesRegex(ValueError, "Could not open your browser") as error:
                cloud.GoogleDrive.open_browser("https://fixture.invalid/private-state")
        self.assertNotIn("private-state", str(error.exception))

    def test_folder_error_identifies_sign_in_recovery_without_matching_message(self):
        output = io.StringIO()
        serve(
            lambda request: cloud.GoogleDrive().list("root"),
            stream=io.StringIO('{"id":1,"op":"list"}\n'),
            output=output,
        )
        response = json.loads(output.getvalue())
        self.assertEqual(response["error_code"], "google_drive_sign_in_required")
        self.assertIn("Connect Google Drive", response["error"])


if __name__ == "__main__":
    unittest.main()
