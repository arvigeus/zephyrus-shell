"""Small, home-scoped filesystem worker for the Files module."""

import atexit
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
if __name__ == "__main__":
    sys.modules["plugins.files.backend"] = sys.modules[__name__]
from plugins.files.cloud import name_checked, provider
from plugins.files.drive_sign_in import DriveSignIn
from plugins.files.transfers import transfer
from plugins.files.working_copies import WorkingCopies
from services.jobs import Jobs

JOBS = Jobs()
DRIVE_SIGN_IN = DriveSignIn(JOBS)
HOME = Path(os.environ.get("HOME", "/")).expanduser().resolve()
ACTION_PLACEHOLDER = re.compile(r"\{(path|name|directory|stem|extension)\}")
ACTION_PROCESSES = {}


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
        # scandir supplies directory/type metadata without resolving and statting
        # every ordinary entry. Only symlinks need the home-boundary check.
        with os.scandir(path) as children:
            for entry in children:
                try:
                    child = Path(entry.path)
                    if entry.is_symlink():
                        resolved = child.resolve(strict=True)
                        is_directory = entry.is_dir() and resolved.is_relative_to(HOME)
                    else:
                        is_directory = entry.is_dir(follow_symlinks=False)
                    size = 0 if is_directory else entry.stat(follow_symlinks=False).st_size
                    items.append(
                        {
                            "name": entry.name,
                            "path": entry.path,
                            "is_dir": is_directory,
                            "hidden": entry.name.startswith("."),
                            "extension": child.suffix.lower(),
                            "size_label": "" if is_directory else human_size(size),
                            "size": size,
                        }
                    )
                except (OSError, RuntimeError):
                    continue
    except OSError as error:
        raise ValueError(f"Cannot read this folder: {error.strerror or error}") from error
    items.sort(key=lambda item: (not item["is_dir"], str(item["name"]).casefold()))
    return {"path": str(path), "entries": items}


def human_size(size):
    units = ("B", "KB", "MB", "GB", "TB")
    value = float(size)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.0f} {unit}" if unit == "B" else f"{value:.1f} {unit}"
        value /= 1024


def spawn(command):
    subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


EDITS = WorkingCopies(JOBS, spawn)


def custom_action_configuration():
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    path = config_home / "zephyrus-shell/files.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with path.open("x", encoding="utf-8") as file:
            file.write('{"actions": []}\n')
    except FileExistsError:
        pass
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, UnicodeError) as error:
        raise ValueError(f"Fix the JSON in {path} to load file actions.") from error
    if not isinstance(data, dict) or not isinstance(data.get("actions"), list):
        raise ValueError("Files configuration must contain an actions array.")

    actions = []
    for index, item in enumerate(data["actions"]):
        if not isinstance(item, dict) or any(
            not isinstance(item.get(key), str) or not item[key].strip()
            for key in ("name", "command")
        ):
            raise ValueError(f"Action {index + 1} needs a nonempty name and command.")
        if any(character in item["command"] for character in ("\0", "\x1b", "\r")):
            raise ValueError(f"Action {index + 1} contains unsupported control characters.")
        match = item.get("match")
        if (
            not isinstance(match, dict)
            or not isinstance(match.get("kind"), str)
            or not isinstance(match.get("value"), str)
            or not match["value"].strip()
        ):
            raise ValueError(f"Action {index + 1} needs a match kind and value.")

        kind = match["kind"]
        value = match["value"].strip()
        action = {"name": item["name"].strip(), "command": item["command"], "kind": kind}
        if kind == "extension":
            if not value.startswith(".") or "/" in value or "\\" in value:
                raise ValueError(f"Action {index + 1} extension values must look like .mka.")
            action["value"] = value.casefold()
        elif kind in ("file", "directory"):
            target = Path(value).expanduser()
            if not target.is_absolute():
                target = HOME / target
            try:
                target = target.resolve(strict=False)
            except (OSError, RuntimeError) as error:
                raise ValueError(f"Action {index + 1} has an invalid match path.") from error
            if not target.is_relative_to(HOME):
                raise ValueError(
                    f"Action {index + 1} match paths must stay inside your home folder."
                )
            action["value"] = target
        else:
            raise ValueError(
                f"Action {index + 1} match kind must be file, extension, or directory."
            )
        actions.append(action)
    return path, actions


def matching_custom_actions(value):
    target = safe_path(value)
    _, actions = custom_action_configuration()
    matched = []
    for index, action in enumerate(actions):
        if action["kind"] == "file":
            applies = target.is_file() and target == action["value"]
        elif action["kind"] == "extension":
            applies = target.is_file() and target.suffix.casefold() == action["value"]
        else:
            applies = target.is_dir() and target == action["value"]
        if applies:
            matched.append({"index": index, "name": action["name"]})
    return {"actions": matched}


def run_custom_action(value, index):
    target = safe_path(value)
    _, actions = custom_action_configuration()
    if not isinstance(index, int) or isinstance(index, bool) or index < 0 or index >= len(actions):
        raise ValueError("That file action is no longer available. Reopen the menu and try again.")
    action = actions[index]
    if action["kind"] == "file":
        applies = target.is_file() and target == action["value"]
    elif action["kind"] == "extension":
        applies = target.is_file() and target.suffix.casefold() == action["value"]
    else:
        applies = target.is_dir() and target == action["value"]
    if not applies:
        raise ValueError("That file action no longer applies. Reopen the menu and try again.")

    directory = target if target.is_dir() else target.parent
    values = {
        "path": str(target),
        "name": target.name,
        "directory": str(directory),
        "stem": target.stem,
        "extension": target.suffix,
    }
    command = ACTION_PLACEHOLDER.sub(
        lambda match: shlex.quote(values[match.group(1)]), action["command"]
    )
    process = subprocess.Popen(
        ["/bin/sh", "-c", command],
        cwd=str(directory),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    ACTION_PROCESSES[process.pid] = process
    return {"message": "Started " + action["name"], "job_id": process.pid}


def custom_action_status(value):
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise ValueError("That file action is no longer available.")
    process = ACTION_PROCESSES.get(value)
    if process is None:
        return {"finished": True, "returncode": None}
    returncode = process.poll()
    if returncode is None:
        return {"finished": False}
    ACTION_PROCESSES.pop(value, None)
    return {"finished": True, "returncode": returncode}


def stop_custom_actions(signum=None, _frame=None):
    EDITS.stop()
    JOBS.stop()
    processes = list(ACTION_PROCESSES.values())
    for process in processes:
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    for process in processes:
        if process.poll() is None:
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
    ACTION_PROCESSES.clear()
    if signum is not None:
        raise SystemExit(0)


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
    if gio:
        command = [gio, "trash", "--", str(target)]
    else:
        assert trash is not None
        command = [trash, "--", str(target)]
    result = subprocess.run(
        command, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=15, check=False
    )
    if result.returncode:
        raise ValueError("This entry could not be moved to Trash. Check its permissions.")
    return {"message": "Moved " + target.name + " to Trash"}


def run(request):
    op = request.get("op")
    if op == "jobs":
        return JOBS.snapshots()
    if op == "edit_sessions":
        return EDITS.poll()
    if op == "edit_session_action":
        return EDITS.action(request.get("session_id"), request.get("pause", False))
    if op == "cancel_job":
        return JOBS.cancel(request.get("job_id"))
    if op == "connect_drive":
        return DRIVE_SIGN_IN.start_or_reopen()
    if op == "complete_drive_sign_in":
        return DRIVE_SIGN_IN.complete(request.get("callback_url"))
    if op == "transfer":
        return JOBS.start(str(request.get("title") or "File transfer"), lambda: transfer(request))
    location = request.get("provider", "local")
    if op == "open" and location != "local":
        return JOBS.start(
            str(request.get("title") or "Open cloud file"),
            lambda: EDITS.open(location, request.get("path")),
        )
    if op == "list":
        return (
            list_directory(request.get("path"))
            if location == "local"
            else provider(location).list(request.get("path"), request.get("cursor", ""))
        )
    if op == "mkdir":
        name = name_checked(request.get("name"))
        if location == "local":
            path = safe_path(request.get("path")) / name
            path.mkdir()
        else:
            path = provider(location).mkdir(request.get("path"), name)
        return {"message": "Created " + name, "path": str(path)}
    if location != "local":
        raise ValueError("Use Download or Open in browser for cloud files.")
    if op == "custom_actions":
        return matching_custom_actions(request.get("path"))
    if op == "custom_action":
        return run_custom_action(request.get("path"), request.get("index"))
    if op == "custom_action_status":
        return custom_action_status(request.get("job_id"))
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
        for name, arguments in (
            ("wl-copy", []),
            ("xclip", ["-selection", "clipboard"]),
            ("xsel", ["--clipboard", "--input"]),
        ):
            executable = shutil.which(name)
            if executable:
                subprocess.run(
                    [executable, *arguments],
                    input=str(path),
                    text=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=True,
                    timeout=3,
                )
                return {"message": "Copied path to clipboard"}
        raise ValueError("No clipboard utility found. Install wl-clipboard, xclip, or xsel.")
    if op == "terminal":
        directory = path if path.is_dir() else path.parent
        terminal = os.environ.get("TERMINAL", "").strip()
        candidates = [shlex.split(terminal)] if terminal else []
        candidates += [
            [name]
            for name in (
                "x-terminal-emulator",
                "kgx",
                "gnome-terminal",
                "konsole",
                "kitty",
                "alacritty",
                "foot",
            )
        ]
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

    atexit.register(stop_custom_actions)
    signal.signal(signal.SIGTERM, stop_custom_actions)
    serve(
        run,
        latest=("list",),
        controls=(
            "delete",
            "open",
            "reveal",
            "copy",
            "terminal",
            "custom_action",
            "mkdir",
            "transfer",
            "connect_drive",
            "complete_drive_sign_in",
            "cancel_job",
            "edit_session_action",
        ),
        scope=lambda r: (r["op"], r.get("provider", "local"), r.get("context", "browse")),
    )


if __name__ == "__main__":
    main()
