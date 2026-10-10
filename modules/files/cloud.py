"""Files-owned Nextcloud DAV and Google Drive providers. No secrets enter QML."""

import base64
import hashlib
import json
import mimetypes
import re
import secrets
import subprocess
import threading
import time
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, quote, unquote, urlencode, urljoin, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

from modules.files.local import human_size
from services.jobs import check_cancelled, progress
from services.nextcloud import DAVClient, config_root, load_account, read_json
from services.storage import atomic_write

CHUNK = 1024 * 1024
FOLDER = "application/vnd.google-apps.folder"
FIELDS = (
    "id,name,mimeType,size,version,webViewLink,shortcutDetails,capabilities(canDownload,canEdit)"
)
EXPORTS = {
    "application/vnd.google-apps.document": (
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        ".docx",
    ),
    "application/vnd.google-apps.spreadsheet": (
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        ".xlsx",
    ),
    "application/vnd.google-apps.presentation": (
        "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        ".pptx",
    ),
    "application/vnd.google-apps.drawing": ("application/pdf", ".pdf"),
}


def name_checked(value):
    if (
        not isinstance(value, str)
        or not value
        or value in (".", "..")
        or any(c in value for c in ("/", "\\", "\0", "\r", "\n"))
    ):
        raise ValueError("Choose a name without slashes or control characters.")
    return value


def unique_name(name, existing):
    name_checked(name)
    path = Path(name)
    for number in range(10001):
        candidate = name if number == 0 else f"{path.stem} ({number}){path.suffix}"
        if candidate not in existing:
            return candidate
    raise ValueError("Too many copies already exist in the destination.")


def entry(name, path, directory, size=0, **extra):
    return {
        "name": name,
        "path": path,
        "is_dir": directory,
        "hidden": name.startswith("."),
        "extension": Path(name).suffix.lower(),
        "size": size,
        "size_label": "" if directory else human_size(size),
        **extra,
    }


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("The cloud service returned an unexpected redirect.")


class EditConflict(ValueError):
    pass


class UploadReader:
    def __init__(self, stream, update):
        self.stream = stream
        self.update = update

    def read(self, count=CHUNK):
        check_cancelled()
        data = self.stream.read(min(count, CHUNK) if count > 0 else CHUNK)
        self.update(len(data))
        return data


class Nextcloud:
    def __init__(self):
        account = load_account()
        if account is None:
            raise ValueError("Configure your account in nextcloud.json to connect Nextcloud.")
        self.dav = DAVClient(
            account, scope="remote.php/dav/files/" + quote(account["username"], safe="") + "/"
        )

    def url(self, path):
        if (
            not isinstance(path, str)
            or not path.startswith("/")
            or any(p in (".", "..") for p in path.split("/"))
            or "\0" in path
        ):
            raise ValueError("Invalid Nextcloud folder.")
        url = self.dav.home + quote(path.lstrip("/"), safe="/")
        if not self.dav.allowed(url):
            raise ValueError("Invalid Nextcloud folder.")
        return url

    def open(self, method, path, body=None, headers=None):
        request = Request(
            self.url(path),
            data=body,
            method=method,
            headers={
                "Authorization": self.dav.auth,
                "User-Agent": "ZephyrusShell/1.0",
                **(headers or {}),
            },
        )
        try:
            return self.dav.opener.open(request, timeout=30)
        except HTTPError as error:
            if error.code in (401, 403):
                raise ValueError(
                    "Nextcloud rejected account access. Check the DAV app password."
                ) from error
            if error.code == 412:
                if headers and headers.get("If-Match"):
                    raise EditConflict(
                        "The cloud file changed elsewhere. Your local edits were kept."
                    ) from error
                raise ValueError(
                    "An item with this name appeared in the destination. Refresh and try again."
                ) from error
            raise ValueError(
                f"Nextcloud returned HTTP {error.code}. Refresh and try again."
            ) from error
        except (URLError, OSError) as error:
            raise ValueError("Nextcloud is unreachable. Check your connection.") from error

    def properties(self, path, depth):
        body = b'<d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:resourcetype/><d:getcontentlength/><d:getetag/></d:prop></d:propfind>'
        with self.open(
            "PROPFIND", path, body, {"Depth": str(depth), "Content-Type": "application/xml"}
        ) as response:
            raw = response.read(16 * CHUNK + 1)
        if len(raw) > 16 * CHUNK or b"<!DOCTYPE" in raw.upper() or b"<!ENTITY" in raw.upper():
            raise ValueError("The Nextcloud folder response is too large or invalid.")
        try:
            xml = ET.fromstring(raw)
        except ET.ParseError as error:
            raise ValueError("Nextcloud returned an unreadable folder listing.") from error
        result = []
        for item in xml.findall("{DAV:}response"):
            href = item.findtext("{DAV:}href", "")
            url = urljoin(self.dav.home, href)
            if not self.dav.allowed(url):
                continue
            child = "/" + unquote(url[len(self.dav.home) :]).strip("/")
            self.url(child)
            for propstat in item.findall("{DAV:}propstat"):
                if " 200 " not in propstat.findtext("{DAV:}status", ""):
                    continue
                prop = propstat.find("{DAV:}prop")
                if prop is None:
                    continue
                name = child.rstrip("/").rsplit("/", 1)[-1] or "Nextcloud"
                directory = prop.find("{DAV:}resourcetype/{DAV:}collection") is not None
                result.append(
                    entry(
                        name,
                        child,
                        directory,
                        int(prop.findtext("{DAV:}getcontentlength", "0") or 0),
                        etag=prop.findtext("{DAV:}getetag", ""),
                        version=prop.findtext("{DAV:}getetag", ""),
                    )
                )
                break
        return result

    def list(self, path="/", cursor=""):
        path = path or "/"
        items = [x for x in self.properties(path, 1) if x["path"].rstrip("/") != path.rstrip("/")]
        # Only immediate children of the requested folder may be used as sources.
        items = [x for x in items if x["path"].rsplit("/", 1)[0] == path.rstrip("/")]
        items.sort(key=lambda x: (not x["is_dir"], x["name"].casefold()))
        return {"path": path, "entries": items, "cursor": ""}

    def metadata(self, path):
        for item in self.properties(path, 0):
            if item["path"].rstrip("/") == path.rstrip("/"):
                return item
        raise ValueError("This Nextcloud item is no longer available.")

    def account_key(self):
        return hashlib.sha256(self.dav.home.encode()).hexdigest()

    def edit_metadata(self, path):
        return self.metadata(path)

    def replace(self, source, item, update):
        if not item.get("etag"):
            raise ValueError("The server did not supply a revision. Your local edits were kept.")
        with source.open("rb") as stream:
            with self.open(
                "PUT",
                item["path"],
                UploadReader(stream, update),
                {
                    "Content-Length": str(source.stat().st_size),
                    "Content-Type": "application/octet-stream",
                    "If-Match": item["etag"],
                },
            ) as response:
                etag = response.headers.get("ETag", "")
        if not etag:
            raise ValueError(
                "The upload completed without a revision receipt. Your local copy was kept; check the cloud file before continuing."
            )
        return {**item, "etag": etag, "version": etag, "size": source.stat().st_size}

    def mkdir(self, parent, name):
        path = parent.rstrip("/") + "/" + name_checked(name)
        with self.open("MKCOL", path, headers={"If-None-Match": "*"}):
            pass
        return path

    def upload(self, source, parent, name, update):
        path = parent.rstrip("/") + "/" + name_checked(name)
        with source.open("rb") as stream:
            with self.open(
                "PUT",
                path,
                UploadReader(stream, update),
                {
                    "Content-Length": str(source.stat().st_size),
                    "If-None-Match": "*",
                    "Content-Type": "application/octet-stream",
                },
            ):
                pass
        return path

    def download(self, item, sink, update):
        with self.open(
            "GET", item["path"], headers={"If-Match": item["etag"]} if item.get("etag") else {}
        ) as response:
            while True:
                check_cancelled()
                chunk = response.read(CHUNK)
                if not chunk:
                    break
                sink.write(chunk)
                update(len(chunk))

    def trash(self, path, etag=None):
        with self.open("DELETE", path, headers={"If-Match": etag} if etag else {}):
            pass


class GoogleSignInRequired(ValueError):
    code = "google_drive_sign_in_required"


class GoogleDrive:
    api = "https://www.googleapis.com/drive/v3/files"
    upload_api = "https://www.googleapis.com/upload/drive/v3/files"
    auth_uri = "https://accounts.google.com/o/oauth2/v2/auth"
    token_uri = "https://oauth2.googleapis.com/token"
    lock = threading.RLock()

    def __init__(self):
        self.opener = build_opener(NoRedirect())
        self.token_path = config_root() / "credentials/google-drive/token.json"

    @staticmethod
    def client():
        config = config_root() / "files.json"
        data = read_json(config) if config.exists() else {}
        reference = data.get("google_drive", {}).get("client_secret_file")
        path = (
            Path(reference).expanduser()
            if reference
            else config_root() / "credentials/google-drive/client.json"
        )
        if not path.exists():
            raise ValueError(
                "Set google_drive.client_secret_file in files.json to your desktop OAuth client JSON."
            )
        client = read_json(path).get("installed", {})
        if not isinstance(client, dict) or not all(
            isinstance(client.get(k), str) and client[k] for k in ("client_id", "client_secret")
        ):
            raise ValueError(
                "Google Drive requires a desktop OAuth client JSON (installed application)."
            )
        return client

    @staticmethod
    def identifier(value):
        if not isinstance(value, str) or not re.fullmatch(r"[\w-]{1,256}", value, flags=re.ASCII):
            raise ValueError("Invalid Google Drive item.")
        return value

    def token_request(self, values):
        try:
            with self.opener.open(
                Request(self.token_uri, data=urlencode(values).encode()), timeout=30
            ) as response:
                return json.load(response)
        except (HTTPError, URLError, OSError, ValueError) as error:
            raise GoogleSignInRequired(
                "Google sign-in expired or was rejected. Connect Google Drive again."
            ) from error

    def access_token(self):
        with self.lock:
            if not self.token_path.exists():
                raise GoogleSignInRequired(
                    "Connect Google Drive to sign in with your Google account."
                )
            token = read_json(self.token_path)
            if token.get("expires_at", 0) > time.time() + 60:
                return token["access_token"]
            client = self.client()
            if not token.get("refresh_token"):
                raise GoogleSignInRequired("Connect Google Drive again to renew access.")
            fresh = self.token_request(
                {
                    "client_id": client["client_id"],
                    "client_secret": client["client_secret"],
                    "grant_type": "refresh_token",
                    "refresh_token": token["refresh_token"],
                }
            )
            token.update(fresh)
            token["expires_at"] = time.time() + int(fresh.get("expires_in", 3600))
            atomic_write(self.token_path, json.dumps(token))
            return token["access_token"]

    @staticmethod
    def open_browser(url):
        try:
            process = subprocess.Popen(
                ["xdg-open", url],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            try:
                code = process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                return
            if code:
                raise ValueError(
                    "Could not open your browser. Check your default browser and press Connect again."
                )
        except OSError as error:
            raise ValueError(
                "Could not open your browser. Check your default browser and press Connect again."
            ) from error

    def connect(self, *, on_ready=None, timeout=600):
        # Browser consent must not hold the token lock: browsing, polling, and
        # retry controls must stay responsive while the user is signing in.
        client = self.client()
        verifier = secrets.token_urlsafe(64)
        challenge = (
            base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest())
            .rstrip(b"=")
            .decode()
        )
        state = secrets.token_urlsafe(32)
        reply = {}
        reply_lock = threading.Lock()

        def accept_callback(value):
            try:
                if not isinstance(value, str) or len(value) > 16384:
                    raise ValueError()
                parsed = urlsplit(value)
                query = parse_qs(parsed.query, max_num_fields=20)
                valid = (
                    parsed.scheme == "http"
                    and parsed.hostname in ("127.0.0.1", "localhost")
                    and parsed.port == server.server_port
                    and parsed.path == "/"
                    and not parsed.username
                    and not parsed.password
                    and not parsed.fragment
                    and len(query.get("state", [])) == 1
                    and secrets.compare_digest(query["state"][0], state)
                    and ((len(query.get("code", [])) == 1) != (len(query.get("error", [])) == 1))
                )
                if not valid:
                    raise ValueError()
            except (ValueError, KeyError, TypeError):
                raise ValueError(
                    "This callback does not match the current sign-in attempt. Press Connect again and use its newest browser tab."
                ) from None
            with reply_lock:
                if reply:
                    raise ValueError(
                        "This sign-in response was already received. Check Files for the result."
                    )
                reply.update(query)

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format, *args):
                pass

            def setup(self):
                super().setup()
                self.connection.settimeout(3)

            def do_GET(self):
                try:
                    accept_callback(redirect.rstrip("/") + self.path)
                    status, text = (
                        200,
                        b"Sign-in received. Return to Zephyrus Files to check the connection.",
                    )
                except ValueError:
                    status, text = (
                        400,
                        b"This sign-in attempt is invalid or was already received. Return to Files and press Connect again.",
                    )
                try:
                    self.send_response(status)
                    self.send_header("Content-Type", "text/plain; charset=utf-8")
                    self.send_header("Content-Length", str(len(text)))
                    self.send_header("Cache-Control", "no-store")
                    self.end_headers()
                    self.wfile.write(text)
                except OSError:
                    # A browser closing the callback page must not discard the grant.
                    pass

        with HTTPServer(("127.0.0.1", 0), Handler) as server:
            server.timeout = 0.5
            redirect = f"http://127.0.0.1:{server.server_port}/"
            url = (
                self.auth_uri
                + "?"
                + urlencode(
                    {
                        "client_id": client["client_id"],
                        "redirect_uri": redirect,
                        "response_type": "code",
                        "scope": "https://www.googleapis.com/auth/drive",
                        "access_type": "offline",
                        "prompt": "consent",
                        "state": state,
                        "code_challenge": challenge,
                        "code_challenge_method": "S256",
                    }
                )
            )
            if on_ready:
                on_ready(url, accept_callback)
            progress(
                kind="authorization",
                cancel_message="Google sign-in cancelled.",
                detail="Complete Google sign-in in your browser. Connect reopens this attempt.",
            )
            self.open_browser(url)
            deadline = time.monotonic() + timeout
            while True:
                check_cancelled()
                with reply_lock:
                    received = dict(reply)
                if received:
                    break
                if time.monotonic() >= deadline:
                    raise ValueError(
                        "Google sign-in timed out. Press Connect Google Drive to start a fresh attempt."
                    )
                server.handle_request()
            if "code" not in received:
                raise ValueError(
                    "Google sign-in was declined. Press Connect Google Drive to try again."
                )
            progress(detail="Finishing Google sign-in…")
            token = self.token_request(
                {
                    "client_id": client["client_id"],
                    "client_secret": client["client_secret"],
                    "code": received["code"][0],
                    "code_verifier": verifier,
                    "redirect_uri": redirect,
                    "grant_type": "authorization_code",
                }
            )
            check_cancelled()
            token["expires_at"] = time.time() + int(token.get("expires_in", 3600))
            with self.lock:
                atomic_write(self.token_path, json.dumps(token))
            return {"message": "Google Drive connected", "provider": "gdrive"}

    def open(self, method, url, data=None, headers=None):
        parsed = urlsplit(url)
        if (
            parsed.scheme != "https"
            or parsed.hostname != "www.googleapis.com"
            or parsed.username
            or parsed.password
        ):
            raise ValueError("Google Drive returned an invalid upload URL.")
        request = Request(
            url,
            method=method,
            data=data,
            headers={
                "Authorization": "Bearer " + self.access_token(),
                "User-Agent": "ZephyrusShell/1.0",
                **(headers or {}),
            },
        )
        try:
            return self.opener.open(request, timeout=30)
        except HTTPError as error:
            if error.code == 308:
                return error  # Resumable acknowledgement, not a redirect.
            if error.code in (401, 403):
                raise ValueError(
                    "Google Drive denied access. Check Drive API access and reconnect if needed."
                ) from error
            if error.code == 412:
                raise EditConflict(
                    "The cloud file changed elsewhere. Your local edits were kept."
                ) from error
            raise ValueError(
                f"Google Drive returned HTTP {error.code}. Refresh and try again."
            ) from error
        except (URLError, OSError) as error:
            raise ValueError("Google Drive is unreachable. Check your connection.") from error

    def json(self, method, url, body=None):
        data = None if body is None else json.dumps(body).encode()
        with self.open(method, url, data, {"Content-Type": "application/json"}) as response:
            return json.load(response)

    def normalize(self, item):
        shortcut = item.get("shortcutDetails", {})
        identifier = item["id"]
        mime = shortcut.get("targetMimeType", item.get("mimeType", ""))
        name = item["name"]
        return entry(
            name,
            identifier,
            mime == FOLDER,
            int(item.get("size", 0)),
            mime=mime,
            web_url=item.get("webViewLink", ""),
            downloadable=item.get("capabilities", {}).get("canDownload", True),
            editable=item.get("capabilities", {}).get("canEdit", True),
            target_path=shortcut.get("targetId", ""),
            version=str(item.get("version", "")),
        )

    def list(self, path="root", cursor=""):
        path = self.identifier(path or "root")
        params = {
            "q": f"'{path}' in parents and trashed = false",
            "pageSize": 200,
            "fields": f"nextPageToken,files({FIELDS})",
            "orderBy": "folder,name_natural",
            "supportsAllDrives": "true",
            "includeItemsFromAllDrives": "true",
        }
        if cursor:
            params["pageToken"] = cursor
        data = self.json("GET", self.api + "?" + urlencode(params))
        return {
            "path": path,
            "entries": [self.normalize(x) for x in data.get("files", [])],
            "cursor": data.get("nextPageToken", ""),
        }

    def metadata(self, path):
        def fetch(identifier):
            return self.json(
                "GET",
                self.api
                + "/"
                + self.identifier(identifier)
                + "?"
                + urlencode({"fields": FIELDS, "supportsAllDrives": "true"}),
            )

        result = self.normalize(fetch(path))
        if result.get("target_path"):
            target = self.normalize(fetch(result["target_path"]))
            if target.get("target_path"):
                raise ValueError("Nested Google Drive shortcuts cannot be transferred.")
            # Preserve the shortcut's identity for move/trash; download its target.
            result = {
                **target,
                "path": result["path"],
                "target_path": target["path"],
                "name": result["name"],
            }
        return result

    def account_key(self):
        # A different grant must never inherit another account's working copies.
        token = read_json(self.token_path)
        return hashlib.sha256(str(token.get("refresh_token", "")).encode()).hexdigest()

    def edit_metadata(self, path):
        item = self.metadata(path)
        if item.get("target_path"):
            item = self.metadata(item["target_path"])
        if item.get("mime", "").startswith("application/vnd.google-apps."):
            return item
        # v3 omits file ETags. v2 supplies them and accepts conditional media PUTs.
        revision = self.json(
            "GET",
            "https://www.googleapis.com/drive/v2/files/"
            + self.identifier(item["path"])
            + "?fields=etag,version&supportsAllDrives=true",
        )
        if str(revision.get("version", "")) != item.get("version", ""):
            raise EditConflict("The cloud file changed while opening. Try again.")
        return {**item, "etag": revision.get("etag", "")}

    def replace(self, source, item, update):
        if not item.get("etag"):
            raise ValueError("Google Drive did not supply a revision. Your local edits were kept.")
        url = (
            "https://www.googleapis.com/upload/drive/v2/files/"
            + self.identifier(item["path"])
            + "?uploadType=media&supportsAllDrives=true&fields=etag,version"
        )
        with source.open("rb") as stream:
            with self.open(
                "PUT",
                url,
                UploadReader(stream, update),
                {
                    "Content-Length": str(source.stat().st_size),
                    "Content-Type": item.get("mime") or "application/octet-stream",
                    "If-Match": item["etag"],
                },
            ) as response:
                revision = json.load(response)
        if not revision.get("etag"):
            raise ValueError(
                "The upload completed without a revision receipt. Your local copy was kept; check the cloud file before continuing."
            )
        return {
            **item,
            "etag": revision["etag"],
            "version": str(revision.get("version", "")),
            "size": source.stat().st_size,
        }

    def mkdir(self, parent, name):
        return self.json(
            "POST",
            self.api + "?supportsAllDrives=true",
            {"name": name_checked(name), "mimeType": FOLDER, "parents": [self.identifier(parent)]},
        )["id"]

    def upload(self, source, parent, name, update):
        size = source.stat().st_size
        mime = mimetypes.guess_type(name)[0] or "application/octet-stream"
        metadata = json.dumps(
            {"name": name_checked(name), "parents": [self.identifier(parent)]}
        ).encode()
        with self.open(
            "POST",
            self.upload_api + "?uploadType=resumable&supportsAllDrives=true",
            metadata,
            {
                "Content-Type": "application/json",
                "X-Upload-Content-Type": mime,
                "X-Upload-Content-Length": str(size),
            },
        ) as response:
            session = response.headers.get("Location", "")
        with source.open("rb") as stream:
            offset = 0
            while offset < size or size == 0:
                check_cancelled()
                stream.seek(offset)
                chunk = stream.read(CHUNK)
                end = offset + len(chunk)
                byte_range = f"bytes {offset}-{end - 1}/{size}" if size else "bytes */0"
                with self.open(
                    "PUT",
                    session,
                    chunk,
                    {
                        "Content-Length": str(len(chunk)),
                        "Content-Type": mime,
                        "Content-Range": byte_range,
                    },
                ) as response:
                    if response.code == 308:
                        acknowledged = response.headers.get("Range", "")
                        next_offset = (
                            int(acknowledged.rsplit("-", 1)[-1]) + 1 if acknowledged else 0
                        )
                        if next_offset <= offset or next_offset > end:
                            raise ValueError(
                                "Google Drive did not acknowledge the upload. Try again."
                            )
                        update(next_offset - offset)
                        offset = next_offset
                    else:
                        result = json.load(response)
                        update(len(chunk))
                        return result["id"]
        raise ValueError("Google Drive did not complete the upload. Try again.")

    def download(self, item, sink, update):
        if not item.get("downloadable", True):
            raise ValueError("The owner has disabled downloading this Google Drive item.")
        mime = item.get("mime", "")
        url = self.api + "/" + self.identifier(item.get("target_path") or item["path"])
        if mime in EXPORTS:
            url += "/export?" + urlencode({"mimeType": EXPORTS[mime][0]})
        elif mime.startswith("application/vnd.google-apps."):
            raise ValueError(
                "This Google Workspace item cannot be exported. Open it in your browser."
            )
        else:
            url += "?alt=media&supportsAllDrives=true"
        with self.open("GET", url) as response:
            while True:
                check_cancelled()
                chunk = response.read(CHUNK)
                if not chunk:
                    break
                sink.write(chunk)
                update(len(chunk))

    def trash(self, path, etag=None):
        self.json(
            "PATCH",
            self.api + "/" + self.identifier(path) + "?supportsAllDrives=true",
            {"trashed": True},
        )


def provider(name):
    if name == "nextcloud":
        return Nextcloud()
    if name == "gdrive":
        return GoogleDrive()
    raise ValueError("Choose Local, Nextcloud, or Google Drive.")
