"""Shared account, replaceable file credentials, and scoped Nextcloud DAV transport.

Calendar parsing and CalDAV operations belong to attention/nextcloud.py.
"""

import base64
import json
import os
from pathlib import Path
import stat
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


class NextcloudError(ValueError):
    pass


class CredentialMissing(NextcloudError):
    pass


def config_root():
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "zephyrus-shell"


def read_json(path):
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError) as error:
        raise NextcloudError(f"Cannot read {path.name}. Check its JSON syntax and permissions.") from error
    if not isinstance(data, dict):
        raise NextcloudError(f"{path.name} must contain a JSON object.")
    return data


def validate_account(data):
    url = data.get("url", "")
    username = data.get("username", "")
    if not isinstance(url, str) or not isinstance(username, str):
        raise NextcloudError("Set an HTTPS URL and username in nextcloud.json.")
    parsed = urlsplit(url)
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password
            or parsed.query or parsed.fragment or not username.strip()
            or ":" in username or any(char.isspace() for char in url)
            or any(part in (".", "..") for part in unquote(parsed.path).split("/"))):
        raise NextcloudError("Set an HTTPS instance URL and username in nextcloud.json.")
    credentials = data.get("credentials", {})
    capabilities = data.get("capabilities", {})
    if not isinstance(credentials, dict) or not isinstance(capabilities, dict):
        raise NextcloudError("Nextcloud credentials and capabilities must be named objects.")
    for reference in credentials.values():
        if not isinstance(reference, dict) or reference.get("provider") != "file":
            raise NextcloudError("Nextcloud credentials require the file provider.")
        file = reference.get("file")
        if (not isinstance(file, str) or not file or Path(file).is_absolute()
                or any(part in (".", "..") for part in file.split("/"))):
            raise NextcloudError("Credential file references must stay inside credentials/nextcloud.")
    for capability in capabilities.values():
        if (not isinstance(capability, dict) or not isinstance(capability.get("credential"), str)
                or capability["credential"] not in credentials):
            raise NextcloudError("Each Nextcloud capability must reference a named credential.")
    return {**data, "url": url.rstrip("/") + "/", "username": username.strip(),
            "credentials": credentials, "capabilities": capabilities}


def load_account(root=None):
    path = (root or config_root()) / "nextcloud.json"
    if not path.exists():
        return None
    return validate_account(read_json(path))


class FileCredentials:
    """Only read(reference) is required of a future Secret Service provider."""

    def __init__(self, root=None):
        self.directory = (root or config_root()) / "credentials/nextcloud"

    def read(self, reference):
        # Validate even when called directly instead of through load_account.
        validate_account({"url": "https://credential.invalid/", "username": "check",
                          "credentials": {"check": reference}})
        path = self.directory / reference["file"]
        if not path.resolve().is_relative_to(self.directory.resolve()):
            raise NextcloudError("The Nextcloud credential path escapes its directory.")
        try:
            descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        except FileNotFoundError as error:
            raise CredentialMissing("Save the referenced Nextcloud credential with mode 0600.") from error
        except OSError as error:
            raise NextcloudError("Cannot open the Nextcloud credential file.") from error
        with os.fdopen(descriptor) as source:
            info = os.fstat(source.fileno())
            if (not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) != 0o600
                    or info.st_uid != os.getuid()):
                raise NextcloudError("Nextcloud credential files must be owned by you with mode 0600.")
            try:
                secret = source.read(65537).strip()
            except (OSError, UnicodeError) as error:
                raise NextcloudError("Cannot read the Nextcloud credential.") from error
        if not secret or len(secret) > 65536 or "\n" in secret or "\r" in secret:
            raise NextcloudError("The Nextcloud credential is empty or invalid.")
        return secret


def credential(account, capability="dav", provider=None):
    config = account.get("capabilities", {}).get(capability)
    if not config:
        raise NextcloudError(f"Enable the {capability} capability in nextcloud.json.")
    reference = account["credentials"][config["credential"]]
    return (provider or FileCredentials()).read(reference)


class SameOriginRedirect(HTTPRedirectHandler):
    def __init__(self, allowed):
        self.allowed = allowed

    def redirect_request(self, request, fp, code, msg, headers, newurl):
        if not self.allowed(newurl):
            raise NextcloudError("Nextcloud redirected outside the configured DAV scope.")
        return super().redirect_request(request, fp, code, msg, headers, newurl)


class DAVClient:
    def __init__(self, account, *, scope, provider=None, opener=None):
        self.account = validate_account(account)
        self.base = self.account["url"]
        self.username = self.account["username"]
        self.origin = urlsplit(self.base).netloc
        self.home = self.base + scope.lstrip("/")
        password = credential(self.account, provider=provider)
        self.auth = "Basic " + base64.b64encode((self.username + ":" + password).encode()).decode()
        self.opener = opener or build_opener(SameOriginRedirect(self.allowed))

    def allowed(self, url):
        parsed = urlsplit(url)
        return (parsed.scheme == "https" and parsed.netloc == self.origin
                and not parsed.query and not parsed.fragment and url.startswith(self.home)
                and not any(part in (".", "..") for part in unquote(parsed.path).split("/")))

    def request(self, method, url, body=None, headers=None):
        if not self.allowed(url):
            raise NextcloudError("The Nextcloud DAV URL is outside the configured account scope.")
        request = Request(url, data=body, method=method, headers={
            "User-Agent": "ZephyrusShell/1.0", "Accept": "application/xml, text/calendar",
            **(headers or {}), "Authorization": self.auth,
        })
        try:
            with self.opener.open(request, timeout=18) as response:
                return response.read(), response.headers
        except HTTPError as error:
            if error.code in (401, 403):
                raise NextcloudError("Nextcloud rejected the app password or account access.") from error
            if error.code == 412:
                raise NextcloudError("The item changed on Nextcloud. Refresh and try again.") from error
            raise NextcloudError("Nextcloud returned HTTP " + str(error.code) + ".") from error
        except (URLError, OSError) as error:
            raise NextcloudError("Nextcloud is unreachable. Check your connection.") from error
