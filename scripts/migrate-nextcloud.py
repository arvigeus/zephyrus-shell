#!/usr/bin/env python3
"""Explicit, restartable migration. Never log configuration or credential values."""

import json
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from services.nextcloud import (
    NextcloudError,
    config_root,
    load_account,
    read_json,
    validate_account,
)


def write_private(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as output:
        temporary = Path(output.name)
        try:
            os.fchmod(output.fileno(), 0o600)
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)


def migrate(root=None):
    root = root or config_root()
    attention_path = root / "attention.json"
    attention = read_json(attention_path) if attention_path.exists() else {}
    legacy = attention.get("nextcloud", {})
    if not isinstance(legacy, dict):
        raise NextcloudError("Legacy nextcloud configuration must be an object.")
    account = load_account(root)
    sources = {
        "dav-app-password": root / "nextcloud-app-password",
        "music-api-key": root / "nextcloud-music-password",
    }
    if legacy.get("password_file"):
        sources["dav-app-password"] = Path(legacy["password_file"]).expanduser()
    if not account:
        if not legacy.get("url") or not legacy.get("username"):
            if any(path.exists() for path in sources.values()):
                raise NextcloudError(
                    "Set the account URL and username before migrating credentials."
                )
            return False
        account = validate_account(
            {
                "url": legacy["url"],
                "username": legacy["username"],
                "credentials": {"dav": {"provider": "file", "file": "dav-app-password"}},
                "capabilities": {"dav": {"credential": "dav"}},
            }
        )
    elif legacy.get("url") and (
        legacy["url"].rstrip("/") + "/" != account["url"]
        or legacy.get("username") != account["username"]
    ):
        raise NextcloudError(
            "Existing nextcloud.json describes a different account; migration stopped."
        )
    if sources["music-api-key"].exists():
        account["credentials"].setdefault("music", {"provider": "file", "file": "music-api-key"})
        account["capabilities"].setdefault("music_subsonic", {"credential": "music"})
    directory = root / "credentials/nextcloud"
    for private in (root / "credentials", directory):
        if private.is_symlink():
            raise NextcloudError("Credential directories must not be symlinks.")
        private.mkdir(parents=True, exist_ok=True, mode=0o700)
        private.chmod(0o700)
    pending = []
    # Preflight every conflict before modifying any credential.
    for filename, source in sources.items():
        if not source.exists():
            continue
        credential_id = "dav" if filename == "dav-app-password" else "music"
        reference = account["credentials"].get(credential_id, {})
        if reference != {"provider": "file", "file": filename}:
            raise NextcloudError(
                "Existing credential references conflict with migration; no secrets removed."
            )
        target = directory / filename
        if source.is_symlink() or target.is_symlink():
            raise NextcloudError("Migration refuses symlinked credentials.")
        data = source.read_bytes()
        if not data.strip():
            raise NextcloudError("A legacy credential is empty; migration stopped.")
        if target.exists() and target.read_bytes() != data:
            raise NextcloudError(
                "A destination credential differs; migration will not overwrite it."
            )
        pending.append((source, target, data))
    for _, target, data in pending:
        write_private(target, data)
    write_private(root / "nextcloud.json", (json.dumps(account, indent=2) + "\n").encode())
    if legacy:
        backup = root / "attention.before-nextcloud.json"
        if not backup.exists():
            write_private(backup, attention_path.read_bytes())
        options = {key: legacy[key] for key in ("calendars", "task_lists") if key in legacy}
        attention.setdefault("calendar", options)
        attention.pop("nextcloud", None)
        write_private(attention_path, (json.dumps(attention, indent=2) + "\n").encode())
    # Originals stay available until both configurations have been committed.
    for source, target, _ in pending:
        if source != target:
            source.unlink()
    return True


if __name__ == "__main__":
    try:
        changed = migrate()
        print(
            "Nextcloud migration complete."
            if changed
            else "No legacy Nextcloud account to migrate."
        )
    except (NextcloudError, OSError) as error:
        # OSError paths can reveal usernames; report a constant for filesystem failures.
        print(
            str(error)
            if isinstance(error, NextcloudError)
            else "Nextcloud migration failed; check file permissions.",
            file=sys.stderr,
        )
        sys.exit(1)
