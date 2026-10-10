"""Stub only Google/browser endpoints; run the real Files worker and callback."""

import io
import json
import os
import sys
import threading
import time
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlsplit
from urllib.request import urlopen

if sys.argv[0].endswith("modules/files/backend.py"):
    sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
    from modules.files.cloud import GoogleDrive
    from services.jobs import current_job
    from services.storage import atomic_write

    launches = 0

    def open_browser(url):
        global launches
        launches += 1
        query = parse_qs(urlsplit(url).query)
        callback = (
            query["redirect_uri"][0]
            + "?"
            + urlencode({"state": query["state"][0], "code": "fixture"})
        )
        path = Path(os.environ["ZEPHYRUS_DRIVE_FIXTURE"])
        job = current_job()
        identifier = job.id if job else json.loads(path.read_text())["job_id"]
        atomic_write(path, json.dumps({"job_id": identifier, "callback": callback}))
        path.chmod(0o600)
        if launches != 2:
            return  # Initial consent waits; Continue reopens the same attempt.

        def complete():
            time.sleep(1)
            with urlopen(callback, timeout=5) as response:
                assert response.status == 200

        threading.Thread(target=complete, daemon=True).start()

    def token_request(self, values):
        assert values["code"] == "fixture" and values["code_verifier"]
        return {"access_token": "fixture", "refresh_token": "fixture", "expires_in": 3600}

    def drive_request(self, method, url, data=None, headers=None):
        self.access_token()
        assert method == "GET" and url.startswith(self.api + "?")
        return io.BytesIO(
            json.dumps(
                {
                    "files": [
                        {"id": "fixture", "name": "Connected fixture", "mimeType": "text/plain"}
                    ]
                }
            ).encode()
        )

    GoogleDrive.open_browser = staticmethod(open_browser)
    GoogleDrive.token_request = token_request
    GoogleDrive.open = drive_request
