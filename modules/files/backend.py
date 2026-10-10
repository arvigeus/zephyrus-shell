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
from modules.files import local
from modules.files.cloud import name_checked, provider
from modules.files.drive_sign_in import DriveSignIn
from modules.files.transfers import transfer
from modules.files.working_copies import WorkingCopies
from modules.terminal.backend import open_terminal
from services.jobs import Jobs
from services.worker import serve

ACTION_PLACEHOLDER = re.compile(r"\{(path|name|directory|stem|extension)\}")
ACTION_PROCESSES = {}


def spawn(command):
    subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


JOBS = Jobs()
DRIVE_SIGN_IN = DriveSignIn(JOBS)
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
                target = local.HOME / target
            try:
                target = target.resolve(strict=False)
            except (OSError, RuntimeError) as error:
                raise ValueError(f"Action {index + 1} has an invalid match path.") from error
            if not target.is_relative_to(local.HOME):
                raise ValueError(
                    f"Action {index + 1} match paths must stay inside your home folder."
                )
            action["value"] = target
        else:
            raise ValueError(
                f"Action {index + 1} match kind must be file, extension, or directory."
            )
        actions.append(action)
    return actions


def applies(action, target):
    if action["kind"] == "file":
        return target.is_file() and target == action["value"]
    if action["kind"] == "extension":
        return target.is_file() and target.suffix.casefold() == action["value"]
    return target.is_dir() and target == action["value"]


def matching_custom_actions(value):
    target = local.safe_path(value)
    actions = custom_action_configuration()
    return {
        "actions": [
            {"index": index, "name": action["name"]}
            for index, action in enumerate(actions)
            if applies(action, target)
        ]
    }


def run_custom_action(value, index):
    target = local.safe_path(value)
    actions = custom_action_configuration()
    if not isinstance(index, int) or isinstance(index, bool) or index < 0 or index >= len(actions):
        raise ValueError("That file action is no longer available. Reopen the menu and try again.")
    action = actions[index]
    if not applies(action, target):
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


def shutdown(signum=None, _frame=None):
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
            local.list_directory(request.get("path"))
            if location == "local"
            else provider(location).list(request.get("path"), request.get("cursor", ""))
        )
    if op == "mkdir":
        name = name_checked(request.get("name"))
        if location == "local":
            path = local.safe_path(request.get("path")) / name
            try:
                path.mkdir()
            except FileExistsError as error:
                raise ValueError(f"{name} already exists.") from error
            except OSError as error:
                raise ValueError(f"Cannot create {name}: {error.strerror or error}") from error
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
        return local.delete_entry(request.get("path", ""))
    path = local.safe_path(request.get("path"))
    if op == "open":
        spawn(["xdg-open", str(path)])
        return {"message": f"Opened {path.name or 'Home'}"}
    if op == "reveal":
        spawn(["xdg-open", str(path if path.is_dir() else path.parent)])
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
        return open_terminal(path if path.is_dir() else path.parent)
    raise ValueError("Unsupported file action.")


def main():
    atexit.register(shutdown)
    signal.signal(signal.SIGTERM, shutdown)
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
