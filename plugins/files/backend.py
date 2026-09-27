"""Small, home-scoped filesystem worker for the Files module."""
import json
import os
import shlex
import shutil
import subprocess
import sys
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


def list_directory(value):
    path = safe_path(value)
    if not path.is_dir():
        raise ValueError("That location is not a folder.")
    items = []
    try:
        children = list(path.iterdir())
    except OSError as error:
        raise ValueError(f"Cannot read this folder: {error.strerror or error}") from error
    for child in children:
        try:
            info = child.lstat()
            resolved = child.resolve(strict=True)
            is_directory = child.is_dir() and resolved.is_relative_to(HOME)
            if child.is_symlink() and not resolved.is_relative_to(HOME):
                is_directory = False
            size = info.st_size
            items.append({"name": child.name, "path": str(child), "is_dir": is_directory,
                          "hidden": child.name.startswith("."),
                          "extension": child.suffix.lower(),
                          "size_label": "" if is_directory else human_size(size)})
        except (OSError, RuntimeError):
            continue
    items.sort(key=lambda item: (not item["is_dir"], item["name"].casefold()))
    return {"path": str(path), "entries": items}


def human_size(size):
    units = ("B", "KB", "MB", "GB", "TB")
    value = float(size)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.0f} {unit}" if unit == "B" else f"{value:.1f} {unit}"
        value /= 1024


def spawn(command):
    subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True)


def delete_entry(value):
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
    gio = shutil.which("gio")
    trash = shutil.which("trash-put")
    if not gio and not trash:
        raise ValueError("Install gio or trash-cli to move files to Trash.")
    command = [gio, "trash", "--", str(target)] if gio else [trash, "--", str(target)]
    result = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15, check=False)
    if result.returncode:
        raise ValueError("This entry could not be moved to Trash. Check its permissions.")
    return {"message": "Moved " + target.name + " to Trash"}


def run(request):
    op = request.get("op")
    if op == "list":
        return list_directory(request.get("path"))
    if op == "delete":
        return delete_entry(request.get("path", ""))
    path = safe_path(request.get("path"))
    if op == "open":
        spawn(["xdg-open", str(path)])
        return {"message": f"Opened {path.name or 'Home'}"}
    if op == "reveal":
        location = path if path.is_dir() else path.parent
        spawn(["xdg-open", str(location)])
        return {"message": f"Showing {path.name or 'Home'} in the file manager"}
    if op == "copy":
        for name, arguments in (("wl-copy", []), ("xclip", ["-selection", "clipboard"]), ("xsel", ["--clipboard", "--input"])):
            executable = shutil.which(name)
            if executable:
                subprocess.run([executable, *arguments], input=str(path), text=True,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=3)
                return {"message": "Copied path to clipboard"}
        raise ValueError("No clipboard utility found. Install wl-clipboard, xclip, or xsel.")
    if op == "terminal":
        directory = path if path.is_dir() else path.parent
        terminal = os.environ.get("TERMINAL", "").strip()
        candidates = [shlex.split(terminal)] if terminal else []
        candidates += [[name] for name in ("x-terminal-emulator", "kgx", "gnome-terminal", "konsole", "kitty", "alacritty", "foot")]
        for command in candidates:
            if command and shutil.which(command[0]):
                executable = Path(command[0]).name
                if executable in {"gnome-terminal", "kgx", "ptyxis"}:
                    command += ["--working-directory", str(directory)]
                elif executable == "konsole":
                    command += ["--workdir", str(directory)]
                elif executable == "x-terminal-emulator":
                    command += ["--working-directory", str(directory)]
                else:
                    command += ["--working-directory", str(directory)]
                spawn(command)
                return {"message": "Opened a terminal in " + str(directory)}
        raise ValueError("No terminal was found. Set TERMINAL to your preferred terminal command.")
    raise ValueError("Unsupported file action.")


def main():
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from services.worker import serve
    serve(run, latest=("list",), controls=("delete", "open", "reveal", "copy", "terminal"))


if __name__ == "__main__":
    main()
