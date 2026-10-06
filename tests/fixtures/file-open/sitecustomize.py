"""Stub remote I/O and a default editor; exercise the real Files worker/providers."""

import io
import os
import subprocess
import sys
import time
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

if sys.argv[0].endswith("plugins/files/backend.py"):
    sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
    from plugins.files.cloud import EditConflict, Nextcloud

    fixture = Path(os.environ["ZEPHYRUS_OPEN_FIXTURE"])
    content = b"original"
    revision = 1

    class Response(io.BytesIO):
        def __init__(self, data=b"", headers=None):
            super().__init__(data)
            self.headers = headers or {}

    def init(self):
        self.dav = SimpleNamespace(
            home="https://fixture.test/remote.php/dav/files/me/",
            allowed=lambda url: url.startswith("https://fixture.test/remote.php/dav/files/me/"),
        )

    def request(self, method, path, body=None, headers=None):
        global content, revision
        if method == "PROPFIND":
            if path == "/":
                return Response(b'<d:multistatus xmlns:d="DAV:"/>')
            return Response(
                f'''<d:multistatus xmlns:d="DAV:"><d:response>
              <d:href>/remote.php/dav/files/me/Document.txt</d:href><d:propstat><d:prop>
              <d:resourcetype/><d:getcontentlength>{len(content)}</d:getcontentlength>
              <d:getetag>"{revision}"</d:getetag></d:prop>
              <d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>'''.encode()
            )
        if method == "GET":
            time.sleep(0.5)  # Opening must retain the module before the session exists.
            return Response(content)
        if method == "PUT":
            if headers["If-Match"] != f'"{revision}"':
                raise EditConflict("Fixture conflict")
            content = b""
            while chunk := body.read():
                content += chunk
            revision += 1
            (fixture / "saved").write_bytes(content)
            return Response(headers={"ETag": f'"{revision}"'})
        raise AssertionError((method, path))

    launch_count = int((fixture / "launches").read_text()) if (fixture / "launches").exists() else 0
    original_popen = subprocess.Popen

    def launch(command, **kwargs):
        global launch_count
        if command[0] != "xdg-open":
            return original_popen(command, **kwargs)
        launch_count += 1
        path = Path(command[1])
        (fixture / "opened").write_text(str(path))
        (fixture / "launches").write_text(str(launch_count))
        replacement = path.with_suffix(".replacement")
        replacement.write_bytes(b"edited in default app")
        replacement.replace(path)
        return Mock()

    Nextcloud.__init__ = init
    Nextcloud.open = request
    subprocess.Popen = launch
