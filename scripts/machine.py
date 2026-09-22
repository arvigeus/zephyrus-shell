"""On-demand hardware snapshot and allowlisted actions. No resident polling daemon."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import re


def command(args, strict=False):
    result = subprocess.run(args, capture_output=True, text=True, timeout=8)
    if strict and result.returncode:
        raise RuntimeError(result.stderr.strip() or f"{args[0]} exited {result.returncode}")
    return result.stdout.strip()


def read(path, default=""):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return default


def backlight():
    devices = sorted(Path("/sys/class/backlight").glob("*"))
    return devices[0] if devices else None


ROOT = Path(__file__).resolve().parents[1]
STATE = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "drawer-shell"


def display_config():
    path = ROOT / "config/displays.json"
    return json.loads(path.read_text()) if path.exists() else {}


def primary_monitor(monitors):
    preferred = read(STATE / "primary-display")
    enabled = [m for m in monitors if not m.get("disabled")]
    return next((m for m in enabled if m["name"] == preferred), next((m for m in enabled if m.get("focused")), enabled[0] if enabled else {})).get("name", "")


def gpu_status():
    if not shutil.which("cardwire"):
        return {"mode": "", "modes": [], "error": "Install Cardwire and start cardwired to manage GPU modes."}
    try:
        result = command(["cardwire", "get"], True)
        current = re.search(r"Current Mode:\s*(\w+)", result, re.I)
        available = re.search(r"Available Mode:\s*([^\n]+)", result, re.I)
        return {"mode": current[1].lower() if current else "", "modes": [v.strip().lower() for v in available[1].split(",")] if available else [], "error": ""}
    except (OSError, subprocess.SubprocessError, RuntimeError) as error:
        return {"mode": "", "modes": [], "error": str(error)}


def hardware():
    mem = {line.split(":")[0]: int(line.split()[1]) for line in read("/proc/meminfo").splitlines() if len(line.split()) >= 2}
    total = mem.get("MemTotal", 0); used = total - mem.get("MemAvailable", total)
    temperatures = []
    fans = []
    for hw in Path("/sys/class/hwmon").glob("*"):
        for f in hw.glob("temp*_input"):
            value = read(f)
            if value.lstrip("-").isdigit():
                temperatures.append({"driver": read(hw / "name"), "label": read(f.with_name(f.name.replace("_input", "_label")), read(hw / "name")), "value": round(int(value) / 1000)})
        for f in hw.glob("fan*_input"):
            if read(f).isdigit(): fans.append({"label": read(hw / "name") + " " + f.stem, "value": read(f)})
    return {"memoryPercent": round(used / max(total, 1) * 100), "memoryUsed": round(used / 1048576, 1), "memoryTotal": round(total / 1048576, 1), "temperatures": temperatures, "fans": fans, "load": read("/proc/loadavg").split(" ")[0], "boost": read("/sys/devices/system/cpu/cpufreq/boost")}


def snapshot():
    light = backlight()
    batteries = [p for p in Path("/sys/class/power_supply").glob("*") if read(p / "type") == "Battery" and read(p / "scope") != "Device"]
    battery = batteries[0] if batteries else None
    profiles = command(["powerprofilesctl", "list"]) if shutil.which("powerprofilesctl") else ""
    monitors = json.loads(command(["hyprctl", "monitors", "all", "-j"]) or "[]") if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") else []
    aliases = display_config()
    for monitor in monitors:
        monitor["label"] = aliases.get(monitor["name"], {}).get("label", monitor.get("description") or monitor["name"])
    primary = primary_monitor(monitors)
    power = float(read(battery / "power_now", "0")) / 1000000 if battery else 0
    energy = float(read(battery / "energy_now", "0")) / 1000000 if battery else 0
    full = float(read(battery / "energy_full", "0")) / 1000000 if battery else 0
    status = read(battery / "status") if battery else ""
    hours = ((full - energy) if status == "Charging" else energy) / power if power > 0 else 0
    minutes = round(max(0, hours) * 60)
    battery_info = (f"{minutes // 60}h {minutes % 60}m " + ("until charged" if status == "Charging" else "remaining")) if minutes and status in ("Charging", "Discharging") else status
    if power > 0 and status == "Discharging": battery_info += f" · {power:.1f} W"
    external = aliases.get(primary, {}).get("ddcBus")
    brightness = round(int(read(light / "brightness", "0")) / max(1, int(read(light / "max_brightness", "1"))) * 100) if light else 0
    can_brighten = bool(light) and (not primary or primary.startswith(("eDP", "LVDS")))
    if external is not None and shutil.which("ddcutil"):
        result = command(["ddcutil", "--bus", str(int(external)), "getvcp", "10", "--terse"])
        match = re.search(r"C (\d+) (\d+)", result)
        if match:
            brightness = round(int(match[1]) / max(1, int(match[2])) * 100); can_brighten = True
    return dict(
        hardware=hardware(), gpu=gpu_status(), primary=primary, brightnessAvailable=can_brighten,
        batteryPercent=int(read(battery / "capacity", "0")) if battery else 0,
        batteryStatus=status, batteryInfo=battery_info,
        model=read("/sys/class/dmi/id/product_name", "Linux desktop"),
        backlight=light.name if light else "",
        brightness=brightness,
        battery=f"{read(battery / 'capacity')}% · {read(battery / 'status')}" if battery else "",
        chargeLimit=read(battery / "charge_control_end_threshold") if battery else "",
        nmcli=bool(shutil.which("nmcli")),
        wifi=command(["nmcli", "radio", "wifi"]) if shutil.which("nmcli") else "",
        network=command(["nmcli", "-t", "-f", "NAME", "connection", "show", "--active"]) if shutil.which("nmcli") else "",
        networkEditor=bool(shutil.which("nm-connection-editor")),
        bluetoothEditor=bool(shutil.which("blueman-manager") or shutil.which("systemsettings")),
        profile=command(["powerprofilesctl", "get"]) if profiles else "",
        profiles=[p for p in ["power-saver", "balanced", "performance"] if p + ":" in profiles],
        asus=bool(shutil.which("asusctl")),
        hyprland=bool(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")),
        monitors=monitors,
    )


def action(name, value):
    if name == "wifi" and value in ("on", "off"):
        command(["nmcli", "radio", "wifi", value], True)
    elif name == "profile" and value in ("power-saver", "balanced", "performance"):
        command(["powerprofilesctl", "set", value], True)
    elif name == "gpu":
        if value not in ("integrated", "hybrid", "smart", "manual") or value not in gpu_status()["modes"]:
            raise ValueError("GPU mode is not supported on this machine")
        command(["cardwire", "set", value], True)
    elif name == "chargeLimit":
        percent = int(value)
        if not 50 <= percent <= 100: raise ValueError("Charge limit must be between 50 and 100")
        battery = next((p for p in Path("/sys/class/power_supply").glob("*") if read(p / "type") == "Battery" and (p / "charge_control_end_threshold").exists()), None)
        if battery is None: raise ValueError("Charge limit is unavailable")
        target = battery / "charge_control_end_threshold"
        if os.access(target, os.W_OK): target.write_text(str(percent))
        else:
            result = subprocess.run(["pkexec", "tee", str(target)], input=str(percent), capture_output=True, text=True, timeout=60)
            if result.returncode: raise RuntimeError(result.stderr.strip() or "Charge limit authorization was cancelled")
    elif name in ("primary", "display", "display-mode", "display-scale"):
        monitors = json.loads(command(["hyprctl", "monitors", "all", "-j"], True))
        data = json.loads(value) if name != "primary" else {"name": value}
        monitor = next((m for m in monitors if m["name"] == data.get("name")), None)
        if not monitor or not re.fullmatch(r"[A-Za-z0-9_-]+", monitor["name"]): raise ValueError("Unknown display")
        connector = monitor["name"]
        if name == "primary":
            if monitor.get("disabled"): raise ValueError("Enable the display first")
            STATE.mkdir(parents=True, exist_ok=True); (STATE / "primary-display").write_text(connector)
        elif name == "display":
            if not isinstance(data.get("enabled"), bool): raise ValueError("Expected display state")
            if not data["enabled"] and len([m for m in monitors if not m.get("disabled")]) <= 1: raise ValueError("Keep at least one display enabled")
            command(["hyprctl", "keyword", "monitor", connector + (",preferred,auto,1" if data["enabled"] else ",disable")], True)
        elif name == "display-mode":
            if data.get("mode") not in monitor.get("availableModes", []): raise ValueError("Unsupported display mode")
            command(["hyprctl", "keyword", "monitor", f"{connector},{data['mode']},{monitor.get('x', 0)}x{monitor.get('y', 0)},{monitor.get('scale', 1)}"], True)
        else:
            scale = float(data.get("scale", 0))
            if scale not in (1, 1.25, 1.5, 1.75, 2): raise ValueError("Unsupported display scale")
            command(["hyprctl", "keyword", "monitor", f"{connector},{monitor['width']}x{monitor['height']}@{monitor['refreshRate']},{monitor.get('x', 0)}x{monitor.get('y', 0)},{scale}"], True)
    elif name == "brightness":
        percent = int(value)
        if not 5 <= percent <= 100:
            raise ValueError("Brightness must be between 5 and 100")
        monitors = json.loads(command(["hyprctl", "monitors", "all", "-j"]) or "[]") if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") else []
        primary = primary_monitor(monitors)
        bus = display_config().get(primary, {}).get("ddcBus")
        if bus is not None:
            command(["ddcutil", "--bus", str(int(bus)), "setvcp", "10", str(percent)], True)
            return {"ok": True}
        if primary and not primary.startswith(("eDP", "LVDS")): raise ValueError("Configure a DDC bus for this display")
        light = backlight()
        if light is None:
            raise RuntimeError("No backlight device")
        if shutil.which("brightnessctl"):
            command(["brightnessctl", "-d", light.name, "set", f"{percent}%"], True)
        else:
            level = max(1, round(int(read(light / "max_brightness")) * percent / 100))
            command(["busctl", "--system", "call", "org.freedesktop.login1", "/org/freedesktop/login1/session/auto", "org.freedesktop.login1.Session", "SetBrightness", "ssu", "backlight", light.name, str(level)], True)
    elif name in ("networks", "bluetooth"):
        args = ["nm-connection-editor"] if name == "networks" else ["blueman-manager"] if shutil.which("blueman-manager") else ["systemsettings", "kcm_bluetooth"]
        # External settings applications intentionally survive the drawer.
        subprocess.Popen(args, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif name in ("suspend", "reboot", "poweroff"):
        command(["systemctl", name], True)
    elif name == "logout" and os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        command(["hyprctl", "dispatch", "hl.dsp.exit()"], True)
    else:
        raise ValueError("Unsupported action or value")
    return {"ok": True}


if __name__ == "__main__":
    try:
        print(json.dumps(snapshot() if sys.argv[1] == "snapshot" else action(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "")))
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(json.dumps({"error": str(error)}))
        sys.exit(1)
