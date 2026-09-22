"""User profile persistence. Defaults are versioned; edits live in XDG state."""
import json
import os
from pathlib import Path
import sys
import tempfile
import machine

FILE = machine.STATE / "profiles.json"


def load():
    data = json.loads((FILE if FILE.exists() else machine.ROOT / "config/profiles.json").read_text())
    names = [p["name"] for p in data["profiles"]]
    if not names or len(set(names)) != len(names) or data["active"] not in names:
        raise ValueError("Profiles need unique names and a valid active profile")
    if any(v and v not in names for v in data["battery"].values()):
        raise ValueError("Unknown automatic battery profile")
    return data


def save(data):
    FILE.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=FILE.parent, delete=False) as tmp:
        json.dump(data, tmp, indent=2); tmp.write("\n")
    os.replace(tmp.name, FILE)


def run(name, value):
    data = load()
    if name == "select":
        target = next((p for p in data["profiles"] if p["name"] == value), None)
        if target is None: raise ValueError("Unknown profile")
        errors = []
        for key, setting in target["settings"].items():
            if key in ("profile", "brightness", "gpu", "chargeLimit"):
                try: machine.action(key, str(setting))
                except Exception as error: errors.append(f"{key}: {error}")
        data["active"] = value
        save(data)
        return dict(data=data, error="; ".join(errors))
    if name == "edit":
        changes = json.loads(value)
        allowed = {"profile", "brightness", "gpu", "chargeLimit", "wifi", "bluetooth"}
        if not isinstance(changes, dict) or not set(changes) <= allowed: raise ValueError("Unsupported profile setting")
        next(p for p in data["profiles"] if p["name"] == data["active"])["settings"].update(changes)
        save(data)
    if name == "battery":
        changes = json.loads(value)
        if not set(changes) <= {"discharging", "low", "default"} or any(v and v not in [p["name"] for p in data["profiles"]] for v in changes.values()): raise ValueError("Invalid battery assignment")
        data["battery"].update(changes); save(data)
    return dict(data=data)


if __name__ == "__main__":
    try: print(json.dumps(run(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "")))
    except Exception as error:
        print(json.dumps({"error": str(error)})); sys.exit(1)
