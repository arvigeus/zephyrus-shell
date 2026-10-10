"""Home-scoped local filesystem access shared by the Files worker and transfers."""

import os
import shutil
import subprocess
from pathlib import Path

HOME = Path(os.environ.get("HOME", "/")).expanduser().resolve()


def safe_path(value):
    path = Path(value or HOME)
    if not path.is_absolute():
        path = HOME / path
    resolved = path.resolve(strict=True)
    if not resolved.is_relative_to(HOME):
        raise ValueError("You can only browse files inside your home folder.")
    return resolved


def human_size(size):
    units = ("B", "KB", "MB", "GB", "TB")
    value = float(size)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.0f} {unit}" if unit == "B" else f"{value:.1f} {unit}"
        value /= 1024


def list_directory(value):
    path = safe_path(value)
    if not path.is_dir():
        raise ValueError("That location is not a folder.")
    items = []
    try:
        # scandir avoids a stat per entry; only symlinks need the home-boundary check.
        with os.scandir(path) as children:
            for entry in children:
                try:
                    if entry.is_symlink():
                        resolved = Path(entry.path).resolve(strict=True)
                        is_directory = entry.is_dir() and resolved.is_relative_to(HOME)
                    else:
                        is_directory = entry.is_dir(follow_symlinks=False)
                    size = 0 if is_directory else entry.stat(follow_symlinks=False).st_size
                except (OSError, RuntimeError):
                    continue
                items.append(
                    {
                        "name": entry.name,
                        "path": entry.path,
                        "is_dir": is_directory,
                        "hidden": entry.name.startswith("."),
                        "extension": Path(entry.name).suffix.lower(),
                        "size_label": "" if is_directory else human_size(size),
                        "size": size,
                    }
                )
    except OSError as error:
        raise ValueError(f"Cannot read this folder: {error.strerror or error}") from error
    items.sort(key=lambda item: (not item["is_dir"], item["name"].casefold()))
    return {"path": str(path), "entries": items}


def delete_entry(value):
    """Move one entry inside home to Trash without following a final symlink."""
    requested = Path(value)
    if ".." in requested.parts:
        raise ValueError("Cannot delete a path containing parent-folder references.")
    if not requested.is_absolute():
        requested = HOME / requested
    parent = requested.parent.resolve(strict=True)
    if not parent.is_relative_to(HOME):
        raise ValueError("You can only delete entries inside your home folder.")
    target = parent / requested.name
    if target == HOME or not target.exists() and not target.is_symlink():
        raise ValueError("That entry no longer exists or cannot be deleted.")
    if gio := shutil.which("gio"):
        command = [gio, "trash", "--", str(target)]
    elif trash_put := shutil.which("trash-put"):
        command = [trash_put, "--", str(target)]
    else:
        raise ValueError("Install gio or trash-cli to move files to Trash.")
    result = subprocess.run(
        command, stdin=subprocess.DEVNULL, capture_output=True, timeout=15, check=False
    )
    if result.returncode:
        raise ValueError("This entry could not be moved to Trash. Check its permissions.")
    return {"message": "Moved " + target.name + " to Trash"}
