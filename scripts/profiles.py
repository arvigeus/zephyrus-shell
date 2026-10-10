"""User profile persistence. Defaults are versioned; edits live in XDG state."""

import json
import sys

import machine

FILE = machine.STATE / "profiles.json"
HARDWARE_KEYS = ("profile", "brightness", "chargeLimit")


def load():
    data = json.loads(
        (FILE if FILE.exists() else machine.ROOT / "config/profiles.json").read_text()
    )
    names = [p["name"] for p in data["profiles"]]
    if not names or len(set(names)) != len(names) or data["active"] not in names:
        raise ValueError("Profiles need unique names and a valid active profile")
    if any(v and v not in names for v in data["battery"].values()):
        raise ValueError("Unknown automatic battery profile")
    return data


def save(data):
    machine.atomic_write(FILE, json.dumps(data, indent=2) + "\n")


def run(name, value):
    data = load()
    if name == "select":
        target = next((p for p in data["profiles"] if p["name"] == value), None)
        if target is None:
            raise ValueError("Unknown profile")
        errors = []
        # wifi and bluetooth are applied by Profiles.qml through Quickshell.
        for key, setting in target["settings"].items():
            if key in HARDWARE_KEYS:
                try:
                    machine.action(key, str(setting))
                except Exception as error:
                    errors.append(f"{key}: {error}")
        if not errors:
            data["active"] = value
            save(data)
        return dict(data=data, error="; ".join(errors))
    if name == "edit":
        changes = json.loads(value)
        if not isinstance(changes, dict) or not set(changes) <= {*HARDWARE_KEYS, "wifi", "bluetooth"}:
            raise ValueError("Unsupported profile setting")
        next(p for p in data["profiles"] if p["name"] == data["active"])["settings"].update(changes)
        save(data)
    elif name != "get":
        raise ValueError("Unsupported profile operation")
    return dict(data=data)


if __name__ == "__main__":
    try:
        print(json.dumps(run(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "")))
    except Exception as error:
        print(json.dumps({"error": str(error)}))
        sys.exit(1)
