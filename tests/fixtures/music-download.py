"""Slow loopback audio fixture for the real Music download/lifecycle smoke test."""

import io
import json
import os
import time
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

buffer = io.BytesIO()
with wave.open(buffer, "wb") as audio:
    audio.setnchannels(1)
    audio.setsampwidth(2)
    audio.setframerate(8000)
    audio.writeframes(b"\0\0" * 32000)
content = buffer.getvalue()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        if urlsplit(self.path).path == "/search":
            body = json.dumps(
                {"tracks": [{"trackId": "fixture", "title": "Fixture", "artistName": "Artist"}]}
            ).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(200)
        self.send_header("Content-Type", "audio/wav")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        try:
            for offset in range(0, len(content), 8192):
                self.wfile.write(content[offset : offset + 8192])
                self.wfile.flush()
                time.sleep(0.3)
        except (BrokenPipeError, ConnectionResetError):
            pass


with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
    url = f"http://127.0.0.1:{server.server_port}"
    config = {
        "providers": [
            {
                "name": "Fixture",
                "search_url": url + "/search?q={query}",
                "stream_url": url + "/audio/{id}",
                "download": {"track": "stream"},
            }
        ]
    }
    path = Path(os.environ["XDG_CONFIG_HOME"]) / "zephyrus-shell/music.json"
    path.write_text(json.dumps(config))
    server.serve_forever()
