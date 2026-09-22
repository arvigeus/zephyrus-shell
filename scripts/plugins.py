"""Read metadata only; never import or execute plugins during discovery."""
import json
from pathlib import Path
import re
import sys


def discover(root):
    entries, errors, seen = [], [], set()
    for manifest in sorted(Path(root).glob("*/manifest.json")):
        try:
            if manifest.stat().st_size > 16384:
                raise ValueError("manifest exceeds 16 KiB")
            data = json.loads(manifest.read_text())
            if data.get("enabled", True) is False:
                continue
            if data.get("apiVersion") != 1:
                raise ValueError("apiVersion must be 1")
            plugin_id = data.get("id", "")
            if not isinstance(plugin_id, str) or not re.fullmatch(r"[a-z][a-z0-9-]{0,63}", plugin_id):
                raise ValueError("invalid id")
            if plugin_id in seen:
                raise ValueError("duplicate id")
            if not isinstance(data.get("name"), str) or not data["name"].strip():
                raise ValueError("name is required")
            entry = (manifest.parent / data.get("entry", "Main.qml")).resolve()
            if not entry.is_relative_to(manifest.parent.resolve()) or entry.suffix != ".qml" or not entry.is_file():
                raise ValueError("entry must be a QML file inside this plugin")
            order = data.get("order", 100)
            if not isinstance(order, int):
                raise ValueError("order must be an integer")
            icon = data.get("icon", "monitor")
            if not isinstance(icon, str):
                raise ValueError("icon must be text")
            # Older manifests used glyphs; keep them readable with a Lucide fallback.
            if not re.fullmatch(r"[a-z0-9-]+", icon) or not (Path(__file__).resolve().parent.parent / "assets" / "lucide" / (icon + ".svg")).is_file():
                icon = "monitor"
            entries.append(dict(id=plugin_id, name=data["name"], icon=icon, order=order, entry=entry.as_uri()))
            seen.add(plugin_id)
        except (ValueError, TypeError, OSError, AttributeError) as error:
            errors.append(f"{manifest.parent.name}: {error}")
    return {"entries": sorted(entries, key=lambda e: (e["order"], e["name"])), "errors": errors}


if __name__ == "__main__":
    print(json.dumps(discover(sys.argv[1])))
