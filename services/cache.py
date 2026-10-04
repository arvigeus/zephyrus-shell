"""Small bounded cache for public catalogue responses, never tokens or playback URLs."""

import hashlib
import json
import os
import sqlite3
import threading
import time
from contextlib import closing
from pathlib import Path


class JsonCache:
    def __init__(self, name, root=None, limit=512):
        root = (
            Path(root)
            if root is not None
            else Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "zephyrus-shell"
        )
        root.mkdir(parents=True, exist_ok=True)
        self.path = root / (name + ".sqlite")
        self.limit = limit
        self.condition = threading.Condition()
        self.pending = set()
        with closing(sqlite3.connect(self.path, timeout=5)) as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.execute(
                "CREATE TABLE IF NOT EXISTS responses (key TEXT PRIMARY KEY, payload TEXT, updated REAL)"
            )
            db.commit()

    def get(self, key, ttl):
        with closing(sqlite3.connect(self.path, timeout=5)) as db:
            row = db.execute(
                "SELECT payload FROM responses WHERE key=? AND updated>?", (key, time.time() - ttl)
            ).fetchone()
        if row:
            try:
                return json.loads(row[0])
            except ValueError:
                pass
        return None

    def put(self, key, value):
        with closing(sqlite3.connect(self.path, timeout=5)) as db:
            db.execute(
                "INSERT OR REPLACE INTO responses VALUES (?,?,?)",
                (key, json.dumps(value), time.time()),
            )
            db.execute(
                "DELETE FROM responses WHERE key IN (SELECT key FROM responses ORDER BY updated DESC LIMIT -1 OFFSET ?)",
                (self.limit,),
            )
            db.commit()

    def load(self, identity, ttl, fetch):
        key = hashlib.sha256(identity.encode()).hexdigest()
        with self.condition:
            while key in self.pending:
                self.condition.wait()
            cached = self.get(key, ttl)
            if cached is not None:
                return cached
            self.pending.add(key)
        try:
            result = fetch()
            self.put(key, result)
            return result
        finally:
            with self.condition:
                self.pending.remove(key)
                self.condition.notify_all()
