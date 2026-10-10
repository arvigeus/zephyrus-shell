"""Files-owned Google sign-in recovery. Authorization URLs stay in the worker."""

import threading

from modules.files.cloud import GoogleDrive
from services.jobs import current_job


class DriveSignIn:
    def __init__(self, jobs):
        self.jobs = jobs
        self.lock = threading.Lock()
        self.job_id = ""
        self.browser_url = ""
        self.submit_callback = None

    def start_or_reopen(self):
        with self.lock:
            active = next(
                (
                    job
                    for job in self.jobs.snapshots()["jobs"]
                    if job["job_id"] == self.job_id
                    and job["state"] in ("queued", "running")
                    and not job.get("cancel_requested")
                ),
                None,
            )
            if active:
                identifier, url = self.job_id, self.browser_url
            else:
                self.browser_url = ""
                self.submit_callback = None
                result = self.jobs.start("Connect Google Drive", self.connect)
                self.job_id = result["job_id"]
                return result
        if url:
            GoogleDrive.open_browser(url)
        return {"job_id": identifier, "reused": True}

    def connect(self):
        identifier = current_job().id

        def ready(url, callback):
            with self.lock:
                if self.job_id == identifier:
                    self.browser_url = url
                    self.submit_callback = callback

        try:
            return GoogleDrive().connect(on_ready=ready)
        finally:
            with self.lock:
                if self.job_id == identifier:
                    self.browser_url = ""
                    self.submit_callback = None

    def complete(self, url):
        with self.lock:
            active = next(
                (
                    job
                    for job in self.jobs.snapshots()["jobs"]
                    if job["job_id"] == self.job_id
                    and job["state"] == "running"
                    and not job.get("cancel_requested")
                ),
                None,
            )
            callback = self.submit_callback if active else None
        if callback is None:
            raise ValueError(
                "This sign-in attempt expired. Press Connect Google Drive to start again."
            )
        callback(url)
        return {"message": "Sign-in received. Finishing the Google connection…"}
