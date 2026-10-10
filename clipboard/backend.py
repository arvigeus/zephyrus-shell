"""Owned clipboard popover worker; the session's cliphist watcher owns recording."""

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from services.worker import serve

_thumbnail_directory = tempfile.TemporaryDirectory(prefix="zephyrus-clipboard-")
IMAGE_PREVIEW = re.compile(r"\b(png|jpe?g|gif|webp)\b", re.IGNORECASE)


def command(name, *args, data=None):
    executable = shutil.which(name)
    if not executable:
        raise ValueError(
            "Clipboard history needs cliphist and wl-clipboard. Install the desktop utilities and log in again."
        )
    # wl-copy forks a clipboard owner that outlives this request. Neither of
    # its output streams may be a pipe: communicate would wait for that owner
    # to close them, even after the launching process has successfully exited.
    with tempfile.TemporaryFile() as errors:
        try:
            result = subprocess.run(
                [executable, *args],
                input=data,
                stdout=subprocess.DEVNULL if name == "wl-copy" else subprocess.PIPE,
                stderr=errors,
                check=False,
                timeout=10,
            )
        except subprocess.TimeoutExpired:
            raise ValueError("Clipboard operation timed out. Try again.") from None
        errors.seek(0)
        diagnostic = (
            errors.read().decode("utf-8", errors="replace").strip() if result.returncode else ""
        )
    if result.returncode:
        # cliphist returns failure for a new (or wiped) database. This is an
        # empty history, not a missing package or a broken clipboard.
        if (
            name == "cliphist"
            and args == ("list",)
            and diagnostic == "opening db: please store something first"
        ):
            return b""
        raise ValueError("Clipboard operation failed: " + (diagnostic or "Refresh and try again."))
    return result.stdout or b""


def entries():
    result = []
    for row in command("cliphist", "list").decode("utf-8", errors="replace").splitlines():
        identifier, separator, preview = row.partition("\t")
        if separator and re.fullmatch(r"[0-9]+", identifier):
            binary = preview.startswith("[[ binary data")
            image = bool(binary and IMAGE_PREVIEW.search(preview))
            result.append(
                {
                    "id": identifier,
                    "preview": preview,
                    "label": "Image" if image else preview,
                    "binary": binary,
                    "image": image,
                }
            )
    return result


def mime_type(data):
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith((b"GIF87a", b"GIF89a")):
        return "image/gif"
    if data.startswith(b"RIFF") and data[8:12] == b"WEBP":
        return "image/webp"
    try:
        data.decode("utf-8")
        return "text/plain;charset=utf-8"
    except UnicodeDecodeError:
        return "application/octet-stream"


def checked(identifier):
    identifier = str(identifier)
    if not re.fullmatch(r"[0-9]+", identifier):
        raise ValueError("Choose a clipboard entry.")
    return identifier


def decode(identifier):
    # cliphist 0.7 reads a list row ("id<TAB>preview"); the preview may be empty.
    return command("cliphist", "decode", data=(identifier + "\t\n").encode())


def thumbnail(identifier):
    data = decode(identifier)
    extension = {"image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/webp": "webp"}
    suffix = extension.get(mime_type(data))
    if not suffix:
        return {"image": False, "source": ""}
    path = Path(_thumbnail_directory.name) / (identifier + "." + suffix)
    temporary = path.with_suffix(".tmp")
    temporary.write_bytes(data)
    temporary.replace(path)
    return {"image": True, "source": path.as_uri()}


def run(request):
    op = request["op"]
    if op == "list":
        return {"entries": entries()}
    if op == "clear":
        command("cliphist", "wipe")
        return {"entries": []}
    identifier = checked(request.get("entry_id", ""))
    if op == "thumbnail":
        return thumbnail(identifier)
    if op == "copy":
        data = decode(identifier)
        command("wl-copy", "--type", mime_type(data), data=data)
        return {"copied": True}
    if op == "delete":
        command("cliphist", "delete", data=(identifier + "\n").encode())
        return {"deleted": True}
    raise ValueError("Unknown clipboard operation.")


if __name__ == "__main__":
    serve(run, latest=("list",), controls=("copy", "delete", "clear"), background=("thumbnail",))
