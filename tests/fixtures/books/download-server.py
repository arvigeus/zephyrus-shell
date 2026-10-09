"""Offline HTTP book files for the real provider download smoke flow."""

import json
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        content = b"%PDF-1.7\n" + b"fixture book content\n" * 60000
        self.send_response(200)
        self.send_header("Content-Type", "application/pdf")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        try:
            for start in range(0, len(content), 32768):
                self.wfile.write(content[start : start + 32768])
                self.wfile.flush()
                time.sleep(0.05)
        except (BrokenPipeError, ConnectionResetError):
            pass


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
path = Path(os.environ["XDG_CONFIG_HOME"]) / "zephyrus-shell/books.json"
config = json.loads(path.read_text())
for provider in config["providers"]:
    provider["env"]["FIXTURE_DOWNLOAD_BASE"] = f"http://127.0.0.1:{server.server_port}"
path.write_text(json.dumps(config))
(path.parent / "book-download-ready").touch()
server.serve_forever()
