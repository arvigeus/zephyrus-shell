"""Files-owned editing sessions with durable copies and conditional save-back."""

import hashlib
import json
import os
import tempfile
import threading
from pathlib import Path

from plugins.files.cloud import CHUNK, EditConflict, name_checked, provider
from services.jobs import check_cancelled, progress
from services.storage import atomic_write


def signature(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError("The working copy is missing or is no longer a regular file.")
    info = path.stat()
    return (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


class WorkingCopies:
    def __init__(self, jobs, opener, directory=None):
        self.jobs = jobs
        self.opener = opener
        data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
        self.directory = directory or data / "zephyrus-shell/files/working-copies"
        self.sessions = {}
        self.lock = threading.RLock()
        self.loaded = False
        self.stopped = False

    def load(self):
        if self.loaded:
            return
        self.loaded = True
        if not self.directory.exists():
            return
        for manifest in self.directory.glob("*/session.json"):
            try:
                record = json.loads(manifest.read_text())
                identifier = manifest.parent.name
                if len(identifier) != 64 or any(c not in "0123456789abcdef" for c in identifier):
                    continue
                name_checked(record["item"]["name"])
                if any(
                    not isinstance(record.get(key), str)
                    for key in ("key", "provider", "account", "digest")
                ):
                    continue
                record.update(
                    id=identifier,
                    active=False,
                    saving=False,
                    stopping=False,
                    observed=None,
                    error="Sync paused. Resume to continue saving this working copy.",
                )
                self.sessions[identifier] = record
            except (OSError, ValueError, KeyError, TypeError):
                continue

    def path(self, record):
        return self.directory / record["id"] / "content" / name_checked(record["item"]["name"])

    def persist(self, record):
        atomic_write(
            self.directory / record["id"] / "session.json",
            json.dumps(
                {key: record[key] for key in ("id", "key", "provider", "account", "item", "digest")}
            ),
        )

    def open(self, kind, path):
        with self.lock:
            self.load()
            remote = provider(kind)
            item = remote.edit_metadata(path)
            if item["is_dir"]:
                raise ValueError("Choose a file to open.")
            if item.get("mime", "").startswith("application/vnd.google-apps."):
                url = (
                    item.get("web_url")
                    or "https://drive.google.com/file/d/"
                    + remote.identifier(item["path"])
                    + "/view"
                )
                self.opener(["xdg-open", url])
                return {"message": "Opened " + item["name"] + " in your browser", "opened": True}
            if not item.get("downloadable", True):
                raise ValueError("The owner has disabled downloading this Google Drive item.")
            if not item.get("etag"):
                raise ValueError(
                    "The server did not supply a revision for safe editing. Use Copy to for a local copy."
                )
            name_checked(item["name"])
            account = remote.account_key()
            key = hashlib.sha256((kind + "\0" + account + "\0" + item["path"]).encode()).hexdigest()
            record = next((r for r in self.sessions.values() if r["key"] == key), None)
            if record and not record["active"] and item["etag"] != record["item"]["etag"]:
                working = self.path(record)
                before = signature(working)
                with working.open("rb") as stream:
                    unchanged = (
                        hashlib.file_digest(stream, "sha256").hexdigest() == record["digest"]
                    )
                if unchanged and before == signature(working):
                    # A clean recovered copy can be replaced by a fresh session.
                    # Its old path remains available to any still-open editor.
                    self.finish(record)
                    record = None
            if record:
                working = self.path(record)
                signature(working)
                # Never replace an existing working copy, including unsynced edits.
                if not record["active"] and not record.get("conflict"):
                    record.update(active=True, error="", observed=None)
            else:
                identifier = hashlib.sha256((key + os.urandom(16).hex()).encode()).hexdigest()
                folder = self.directory / identifier
                folder.mkdir(parents=True, exist_ok=True, mode=0o700)
                os.chmod(folder, 0o700)
                (folder / "content").mkdir(mode=0o700)
                working = folder / "content" / item["name"]
                digest = hashlib.sha256()
                done = 0
                progress(total=item.get("size", 0), detail="Downloading " + item["name"])
                with tempfile.NamedTemporaryFile(
                    dir=folder, prefix=".download-", delete=False
                ) as sink:
                    temporary = Path(sink.name)
                    try:

                        def update(count):
                            nonlocal done
                            done += count
                            progress(done=done)

                        remote.download(item, sink, update)
                        sink.flush()
                        os.fsync(sink.fileno())
                        if sink.tell() != item.get("size", sink.tell()):
                            raise ValueError("The cloud download was incomplete. Try again.")
                        if remote.edit_metadata(item["path"]).get("etag") != item["etag"]:
                            raise EditConflict("The cloud file changed while opening. Try again.")
                        check_cancelled()
                        # Never overwrite an orphaned working copy after a manifest failure.
                        os.link(temporary, working)
                    finally:
                        temporary.unlink(missing_ok=True)
                with working.open("rb") as stream:
                    while chunk := stream.read(CHUNK):
                        check_cancelled()
                        digest.update(chunk)
                if not item.get("editable", True):
                    os.chmod(working, 0o400)
                    check_cancelled()
                    self.opener(["xdg-open", str(working)])
                    return {
                        "message": "Opened read-only copy of " + item["name"],
                        "path": str(working),
                        "opened": True,
                    }
                record = {
                    "id": identifier,
                    "key": key,
                    "provider": kind,
                    "account": account,
                    "item": item,
                    "digest": digest.hexdigest(),
                    "active": True,
                    "saving": False,
                    "stopping": False,
                    "error": "",
                    "observed": None,
                    "synced_signature": signature(working),
                }
                self.persist(record)
                self.sessions[identifier] = record
            if self.stopped:
                raise ValueError("Files closed. The working copy was kept.")
            check_cancelled()
            self.opener(["xdg-open", str(working)])
            return {
                "message": "Opened "
                + item["name"]
                + ("; syncing is paused" if record["error"] else "; saves sync to the cloud"),
                "path": str(working),
                "opened": True,
            }

    def poll(self):
        with self.lock:
            self.load()
            jobs = {job["job_id"]: job for job in self.jobs.snapshots()["jobs"]}
            for record in list(self.sessions.values()):
                job = jobs.get(record.get("save_job"))
                if record["saving"] and job and job["state"] in ("failed", "cancelled"):
                    record.update(
                        saving=False,
                        error=job.get("error") or "Sync stopped. Your local edits were kept.",
                    )
                if self.stopped or not record["active"] or record["saving"] or record["error"]:
                    continue
                try:
                    current = signature(self.path(record))
                    if current == record.get("synced_signature"):
                        if record["stopping"]:
                            self.finish(record)
                        continue
                    if current != record.get("observed"):
                        record["observed"] = current
                        continue  # Debounce writes, including atomic editor replacement.
                    record["saving"] = True
                    accepted = self.jobs.start(
                        "Save " + record["item"]["name"], lambda r=record: self.save(r)
                    )
                    record["save_job"] = accepted["job_id"]
                except ValueError as error:
                    record.update(saving=False, error=str(error))
            return {"sessions": [self.snapshot(record) for record in self.sessions.values()]}

    def snapshot(self, record):
        return {
            "job_id": record["id"],
            "kind": "editing",
            "title": record["item"]["name"],
            "state": "running" if record["active"] and not record["error"] else "failed",
            "active": record["active"],
            "cancellable": False,
            "detail": "Finishing sync…"
            if record["stopping"]
            else "Saved changes sync automatically",
            "error": (record["error"] + " Local copy: " + str(self.path(record)))
            if record["error"]
            else "",
            "path": str(self.path(record)),
            "actionLabel": "Stop syncing"
            if record["active"] and not record["error"]
            else "Open working copy"
            if record.get("conflict")
            else "Resume syncing",
            "secondaryActionLabel": "Pause syncing" if record["error"] and record["active"] else "",
            "progressVisible": False,
            "done": 0,
            "total": 0,
        }

    def save(self, record):
        try:
            remote = provider(record["provider"])
            if remote.account_key() != record["account"]:
                raise ValueError("The cloud account changed. Your local edits were kept.")
            working = self.path(record)
            before = signature(working)
            digest = hashlib.sha256()
            progress(total=before[2], detail="Saving " + record["item"]["name"])
            with tempfile.TemporaryDirectory(prefix=".save-", dir=working.parent) as temporary:
                staging = Path(temporary) / working.name
                with working.open("rb") as stream, staging.open("wb") as sink:
                    while chunk := stream.read(CHUNK):
                        check_cancelled()
                        sink.write(chunk)
                        digest.update(chunk)
                if before != signature(working):
                    return {"message": "Waiting for the editor to finish saving"}
                if digest.hexdigest() != record["digest"]:
                    current = remote.edit_metadata(record["item"]["path"])
                    if current.get("etag") != record["item"].get("etag"):
                        raise EditConflict(
                            "The cloud file changed elsewhere. Your local edits were kept."
                        )
                    done = 0

                    def update(count):
                        nonlocal done
                        done += count
                        progress(done=done)

                    receipt = remote.replace(staging, record["item"], update)
                    with self.lock:
                        record.update(item=receipt, digest=digest.hexdigest())
                        self.persist(record)
                with self.lock:
                    record.update(synced_signature=before, observed=before)
            return {"message": "Saved " + record["item"]["name"] + " to the cloud"}
        except Exception as error:
            with self.lock:
                record.update(
                    error=str(error)
                    if isinstance(error, ValueError)
                    else "Sync failed. Your local edits were kept.",
                    conflict=isinstance(error, EditConflict),
                )
            raise
        finally:
            with self.lock:
                record["saving"] = False

    def finish(self, record):
        (self.directory / record["id"] / "session.json").unlink(missing_ok=True)
        self.sessions.pop(record["id"], None)

    def action(self, identifier, pause=False):
        with self.lock:
            self.load()
            record = self.sessions.get(identifier)
            if not record:
                raise ValueError("That editing session is no longer available.")
            if pause:
                record.update(active=False, stopping=False)
                return {"message": "Sync paused; the working copy was kept"}
            if record["active"] and not record["error"]:
                record["stopping"] = True
                return {"message": "Sync will stop after pending saves finish"}
            self.opener(["xdg-open", str(self.path(record))])
            if record.get("conflict"):
                return {
                    "message": "Opened your local edits. Copy them to a new cloud file to resolve the conflict.",
                    "opened": True,
                }
            # Conflicts keep their original revision. A retry can never silently
            # accept the new cloud revision and overwrite someone else's edits.
            record.update(active=True, error="", observed=None, stopping=False)
            return {"message": "Resumed saving " + record["item"]["name"], "opened": True}

    def stop(self):
        self.stopped = True
