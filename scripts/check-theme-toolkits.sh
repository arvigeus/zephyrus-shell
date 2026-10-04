#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
# Requires Qt 5/6 development headers, their KDE platform plugins, GTK 3/4 and GI.
# No window is shown, settings are isolated, and no desktop notifications run.
python3 - <<'PY'
import json
import os
from pathlib import Path
import subprocess
import tempfile

with tempfile.TemporaryDirectory() as directory:
    env = {**os.environ, "XDG_CONFIG_HOME": directory + "/config",
           "XDG_DATA_HOME": directory + "/data", "XDG_STATE_HOME": directory + "/state",
           "QT_QPA_PLATFORM": "offscreen", "QT_QPA_PLATFORMTHEME": "kde",
           "XDG_CURRENT_DESKTOP": "Hyprland"}
    settings = json.loads(Path("config/theme.json").read_text())
    Path("tests/artifacts").mkdir(parents=True, exist_ok=True)
    settings.update(font="DejaVu Sans", font_size=13)
    source = Path(env["XDG_CONFIG_HOME"]) / "zephyrus-shell/theme.json"
    source.parent.mkdir(parents=True)
    for version in (5, 6):
        flags = subprocess.check_output(["pkg-config", "--cflags", "--libs", f"Qt{version}Widgets"], text=True).split()
        executable = directory + f"/probe{version}"
        subprocess.run(["g++", "-fPIC", "tests/native/theme_probe.cpp", "-o", executable, *flags], check=True)
        for mode in ("dark", "light"):
            settings["mode"] = mode
            source.write_text(json.dumps(settings))
            subprocess.run(["python3", "scripts/theme.py", "apply", "--no-notify"], env=env, check=True, stdout=subprocess.DEVNULL)
            result = subprocess.check_output([executable, f"tests/artifacts/qt{version}-theme-{mode}.png"], env=env, text=True).splitlines()
            palette = settings["palettes"][mode]
            assert result == [palette["background"], palette["background"], palette["accent"], "DejaVu Sans", "13", "kvantum", palette["surface"], palette["border"], palette["border"]], result
            print(f"Qt {version} {mode}: native palette and font PASS")
    for version in (3, 4):
        script = '''
import gi
from pathlib import Path
from services.theme import gtk_css, load
gi.require_version("Gtk", "VERSION.0")
from gi.repository import Gtk
for mode in ("dark", "light"):
    theme = load(Path("/nonexistent/theme-test"))
    theme["mode"] = mode
    provider = Gtk.CssProvider()
    errors = []
    provider.connect("parsing-error", lambda *args: errors.append(str(args[-1])))
    provider.load_from_data(gtk_css(theme, VERSION).encode())
    assert not errors, errors
    print("GTK VERSION " + mode + ": generated CSS PASS")
'''.replace("VERSION", str(version))
        subprocess.run(["python3", "-c", script], env=env, check=True)
PY
