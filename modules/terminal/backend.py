"""Saved terminal commands and the system-terminal fallback.

Saved commands only run in the selected embedded terminal session.
"""

import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from services.worker import serve

# Terminals with a known working-directory flag. Any other terminal inherits the cwd.
DIRECTORY_FLAGS = {
    "kgx": "--working-directory",
    "gnome-terminal": "--working-directory",
    "konsole": "--workdir",
    "kitty": "--working-directory",
    "alacritty": "--working-directory",
    "foot": "--working-directory",
    "ptyxis": "--working-directory",
}


def configuration():
    directory = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    path = directory / "zephyrus-shell/terminal.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with path.open("x", encoding="utf-8") as file:
            file.write('{"commands": []}\n')
    except FileExistsError:
        pass
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, UnicodeError) as error:
        raise ValueError(f"Fix the JSON in {path} to load saved commands.") from error
    if not isinstance(data, dict) or not isinstance(data.get("commands"), list):
        raise ValueError("Terminal configuration must contain a commands array.")
    commands = []
    for index, item in enumerate(data["commands"], 1):
        if not isinstance(item, dict) or any(
            not isinstance(item.get(key), str) or not item[key].strip()
            for key in ("name", "command")
        ):
            raise ValueError(f"Command {index} needs a nonempty name and command.")
        if any(character in item["command"] for character in ("\0", "\x1b", "\r")):
            raise ValueError(f"Command {index} contains unsupported terminal control characters.")
        commands.append({"name": item["name"].strip(), "command": item["command"]})
    return {"path": str(path), "commands": commands}


def open_terminal(directory):
    """Start $TERMINAL or the first installed known terminal in directory."""
    configured = os.environ.get("TERMINAL", "").strip()
    candidates = [shlex.split(configured)] if configured else []
    candidates += [["x-terminal-emulator"], *([name] for name in DIRECTORY_FLAGS)]
    for command in candidates:
        if not command or not shutil.which(command[0]):
            continue
        if flag := DIRECTORY_FLAGS.get(Path(command[0]).name):
            command = [*command, flag, str(directory)]
        subprocess.Popen(
            command,
            cwd=directory,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        return {"message": f"Opened a terminal in {directory}"}
    raise ValueError("No terminal was found. Set TERMINAL to your preferred terminal command.")


def handle(request):
    if request["op"] == "config":
        return configuration()
    if request["op"] == "system_terminal":
        return open_terminal(Path.home())
    raise ValueError("Unknown terminal operation.")


if __name__ == "__main__":
    serve(handle, errors=(ValueError, OSError), controls=("config", "system_terminal"))
