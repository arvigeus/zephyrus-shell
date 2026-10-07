"""Generic JSON command providers owned by the Books worker."""

import json
import os
import re
import signal
import subprocess
import threading
import urllib.parse

from books.provider_plugins import ProviderError, configured_providers

COMMAND_TIMEOUT = 25
MAX_OUTPUT_BYTES = 8 * 1024 * 1024


def safe_url(value):
    if not isinstance(value, str) or any(c.isspace() or ord(c) < 32 for c in value):
        return ""
    try:
        parsed = urllib.parse.urlsplit(value)
        if (parsed.scheme.lower() in ("https", "http") and parsed.hostname
                and parsed.username is None and parsed.password is None):
            parsed.port  # Validate the optional port before handing the URL to a browser.
            return value
    except ValueError:
        pass
    return ""


def diagnostic(value, provider):
    """Keep diagnostics short, without echoing environment values or URLs."""
    value = str(value or "")
    for secret in sorted(set(provider["env"].values()), key=len, reverse=True):
        if secret:
            value = value.replace(secret, "[redacted]")
    value = re.sub(r"(?:[a-zA-Z][a-zA-Z0-9+.-]*://|www\.)\S+", "[URL omitted]", value)
    return " ".join(value.split())[:200]


def _invalid_constant(_value):
    raise ValueError("Invalid JSON constant")


def normalize_result(row, provider):
    if not isinstance(row, dict) or not isinstance(row.get("title"), str) or not row["title"].strip() or "ref" not in row:
        raise ProviderError("Search returned an invalid book offer.")
    authors = row.get("authors", [])
    if not isinstance(authors, list) or not all(isinstance(author, str) for author in authors):
        raise ProviderError("Search authors must be a list of text values.")
    fields = ("id", "title", "authors", "year", "format", "language", "publisher", "pages",
              "identifiers", "size_bytes", "size", "cover_url", "description", "page_url", "ref")
    result = {key: row[key] for key in fields if key in row}
    result.update(source="provider", provider=provider["name"], authors=authors)
    for key in ("cover_url", "page_url"):
        result[key] = safe_url(row.get(key))
    return result


class CommandProviders:
    def __init__(self):
        self._lock = threading.Lock()
        self._processes = set()
        self._closed = False

    @staticmethod
    def _kill(process):
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    def close(self):
        with self._lock:
            self._closed = True
            for process in self._processes:
                self._kill(process)

    def call(self, provider, request):
        env = os.environ.copy()
        env.update(provider["env"])
        process = None
        try:
            with self._lock:
                if self._closed:
                    raise ProviderError("Books provider service stopped.")
                process = subprocess.Popen(provider["command"], stdin=subprocess.PIPE,
                                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                           env=env, start_new_session=True)
                self._processes.add(process)
            try:
                stdout, stderr = process.communicate(
                    (json.dumps(request, ensure_ascii=False) + "\n").encode(), timeout=COMMAND_TIMEOUT)
            except subprocess.TimeoutExpired:
                self._kill(process)
                process.communicate()
                raise ProviderError("Command timed out. Try again.") from None
            if len(stdout) > MAX_OUTPUT_BYTES:
                raise ProviderError("Command returned too much output.")
            try:
                payload = json.loads(stdout, parse_constant=_invalid_constant)
            except (ValueError, UnicodeDecodeError):
                detail = diagnostic(stderr.decode(errors="replace"), provider) if process.returncode else ""
                if process.returncode:
                    raise ProviderError("Command failed" + (": " + detail if detail else ".")) from None
                raise ProviderError("Command must return exactly one JSON object.") from None
            if not isinstance(payload, dict) or type(payload.get("success")) is not bool:
                raise ProviderError("Command returned an invalid response.")
            if payload["success"] is False:
                raise ProviderError(diagnostic(payload.get("error"), provider) or "Provider request failed.")
            if process.returncode:
                raise ProviderError("Command exited unsuccessfully.")
            return payload
        except OSError:
            raise ProviderError("Cannot start provider command. Check its configuration.") from None
        finally:
            if process is not None:
                self._kill(process)
                with self._lock:
                    self._processes.discard(process)

    def search(self, provider, query, page=0, limit=10):
        payload = self.call(provider, {"op": "search", "query": query, "page": page, "limit": limit})
        if not isinstance(payload.get("results"), list):
            raise ProviderError("Search response must contain a results list.")
        return [normalize_result(row, provider) for row in payload["results"]]

    def resolve(self, provider, ref, purpose=None):
        request = {"op": "resolve", "ref": ref}
        if purpose:
            request["purpose"] = purpose
        payload = self.call(provider, request)
        url = safe_url(payload.get("url"))
        if not url:
            raise ProviderError("Provider returned an invalid web URL.")
        return {"url": url}
