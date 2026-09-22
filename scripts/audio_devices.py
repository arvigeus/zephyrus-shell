"""Read route metadata and independent audio naming files; never changes audio."""
import json
from pathlib import Path
import subprocess
import sys


def load_rules(directory):
    rules, errors = [], []
    for path in sorted(Path(directory).glob("*.json")):
        try:
            data = json.loads(path.read_text())
            if not isinstance(data, list):
                raise ValueError("expected a list of naming rules")
            for rule in data:
                if "role" in rule and rule["role"] not in ("speaker", "headphones", "microphone", "headset", "hdmi"):
                    raise ValueError("unknown audio role")
                if not isinstance(rule.get("label"), str) or not rule["label"].strip():
                    raise ValueError("each rule needs a label")
                if not rule.get("match") and not rule.get("contains"):
                    raise ValueError("each rule needs match or contains fields")
                for key in ("match", "contains"):
                    if not isinstance(rule.get(key, {}), dict) or any(not isinstance(v, str) for v in rule.get(key, {}).values()):
                        raise ValueError("match values must be strings")
            rules.extend(data)
        except (OSError, ValueError, TypeError, AttributeError) as error:
            errors.append(f"{path.name}: {error}")
    return rules, errors


def snapshot(directory):
    rules, errors = load_rules(directory)
    devices = {}
    for kind in ("sinks", "sources"):
        try:
            result = subprocess.run(["pactl", "-f", "json", "list", kind], text=True, capture_output=True, check=True, timeout=5)
            for node in json.loads(result.stdout):
                ports = node.get("ports", [])
                if isinstance(ports, dict):
                    ports = [dict(value, name=key) for key, value in ports.items()]
                port = next((p for p in ports if p["name"] == node.get("active_port")), {})
                props = node.get("properties", {})
                props.update({"node.name": node["name"], "node.description": node.get("description", ""), "port.name": port.get("name", ""), "port.description": port.get("description", "")})
                devices[node["name"]] = {"properties": props, "available": port.get("availability") not in ("not available", "no"), "port": port.get("description", "")}
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            errors.append("Audio route details unavailable: " + type(error).__name__)
    candidates = []
    try:
        for card in read_cards():
            active = card.get("active_profile", "")
            profiles = card.get("profiles", {})
            for name, profile in profiles.items():
                if name.startswith(active + "+input:") and profile.get("available") not in (False, "no") and profile.get("sources", 0) > 0:
                    candidates.append(dict(card=card["name"], profile=name, previous=active))
    except (OSError, ValueError, subprocess.SubprocessError):
        errors.append("Audio profile details unavailable")
    return dict(rules=rules, devices=devices, errors=errors, inputProfiles=candidates)


def read_cards():
    result = subprocess.run(["pactl", "-f", "json", "list", "cards"], text=True, capture_output=True, check=True, timeout=5)
    return json.loads(result.stdout)


def enable_input(card_name, profile_name, previous):
    card = next((card for card in read_cards() if card["name"] == card_name), None)
    profile = card.get("profiles", {}).get(profile_name) if card else None
    if not card or card.get("active_profile") != previous:
        raise ValueError("Audio configuration changed. Refresh before trying again.")
    if not profile or not profile_name.startswith(previous + "+input:") or not profile.get("sources") or profile.get("available") in (False, "no"):
        raise ValueError("No compatible microphone profile is available")
    subprocess.run(["pactl", "set-card-profile", card_name, profile_name], capture_output=True, text=True, check=True, timeout=5)
    return {"ok": True}


if __name__ == "__main__":
    try:
        print(json.dumps(enable_input(*sys.argv[2:5]) if sys.argv[1] == "enable-input" else snapshot(sys.argv[1])))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(json.dumps({"error": str(error)}))
        sys.exit(1)
