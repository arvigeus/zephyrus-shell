"""Isolated Web UI fixture used by the real media worker/lifecycle smoke check."""

import json
import os
import sys
import time
import urllib.parse
from email.parser import BytesParser
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from test_torrents import FakeQBit

client = FakeQBit()
added_at = 0


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def respond(self, values=None):
        global added_at
        endpoint = self.path.removeprefix("/api/v2/")
        result = client.call(endpoint, values)
        if endpoint == "torrents/add":
            name = (
                "fixture.S01E01.mkv"
                if "series-fixture" in values["urls"]
                else "The.Last.Horizon.2025.mkv"
            )
            source = Path(client.save_path) / name
            source.write_bytes(b"video" * 250000)
            client.files = [{"name": name, "priority": 1}]
            added_at = time.monotonic()
        if endpoint == "torrents/info" and result:
            result[0]["progress"] = 1 if time.monotonic() - added_at > 3 else 0.25
            result[0]["state"] = "uploading" if result[0]["progress"] == 1 else "downloading"
        encoded = (
            json.dumps(result).encode()
            if isinstance(result, (dict, list))
            else str(result).encode()
        )
        self.send_response(200)
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self):
        self.respond()

    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        if self.headers.get("Content-Type", "").startswith("multipart/"):
            message = BytesParser().parsebytes(
                ("Content-Type: " + self.headers["Content-Type"] + "\r\n\r\n").encode() + body
            )
            values = {
                part.get_param("name", header="content-disposition"): part.get_payload(
                    decode=True
                ).decode()
                for part in message.get_payload()
            }
        else:
            values = {key: row[0] for key, row in urllib.parse.parse_qs(body.decode()).items()}
        self.respond(values)


server = HTTPServer(("127.0.0.1", 0), Handler)
config = Path(os.environ["XDG_CONFIG_HOME"]) / "zephyrus-shell/torrents.json"
config.write_text(json.dumps({"url": f"http://127.0.0.1:{server.server_port}"}))
server.serve_forever()
