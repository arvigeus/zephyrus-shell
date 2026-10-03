"""On-demand hardware snapshot and allowlisted actions. No resident polling daemon."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import re
import time
import math
import tempfile


def command(args, strict=False, timeout=8):
    result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
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
CPU_BOOST_HELPER = Path("/usr/lib/zephyrus-shell/cpu-boost")
STATE = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "zephyrus-shell"


def config_directory():
    return Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "zephyrus-shell"


def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as output:
            temporary = Path(output.name)
            output.write(text)
        temporary.replace(path)
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)


def display_config():
    defaults = json.loads((ROOT / "config/displays.json").read_text())
    personal = config_directory() / "displays.json"
    if personal.exists():
        for name, settings in json.loads(personal.read_text()).items():
            defaults[name] = dict(defaults.get(name, {}), **settings)
    return defaults


def ddc_bus(connector, config, drm_root=Path("/sys/class/drm")):
    override = config.get(connector, {}).get("ddcBus")
    if override is not None:
        return int(override)
    # Match the connector, never a guessed bus index or a costly full DDC scan.
    for port in drm_root.glob("card*-" + connector):
        # DisplayPort AUX adapters live directly under the connector and can
        # differ from its legacy ddc adapter (USB-C/MST docks in particular).
        aux = {int(bus.name.removeprefix("i2c-")) for bus in port.glob("i2c-*/i2c-dev/i2c-*")}
        if len(aux) == 1:
            return next(iter(aux))
        buses = {int(bus.name.removeprefix("i2c-")) for bus in (port / "ddc/i2c-dev").glob("i2c-*")}
        if len(buses) == 1:
            return next(iter(buses))
    return None


def ddc_brightness(bus, refresh=False, device_root=Path("/dev")):
    cache = STATE / ("ddc-brightness-" + str(bus) + ".json")
    if not refresh:
        try:
            saved = json.loads(cache.read_text())
            if time.time() - saved["checked"] < 60:
                return saved["value"], saved["error"]
        except (OSError, ValueError, KeyError):
            pass
    value, error = None, ""
    if not shutil.which("ddcutil"):
        error = "Install ddcutil with scripts/setup-system.sh."
    elif bus is None:
        error = "No DDC bus found. Choose a bus in Display settings."
    elif not (device_root / f"i2c-{bus}").exists():
        error = "DDC needs i2c-dev. Run scripts/setup-system.sh to enable it."
    elif not os.access(device_root / f"i2c-{bus}", os.R_OK | os.W_OK):
        error = "DDC access denied. Run setup-system.sh, then log out and back in."
    else:
        try:
            result = command(["ddcutil", "--bus", str(bus), "getvcp", "10", "--terse"], True, 5)
            match = re.search(r"C (\d+) (\d+)", result)
            if not match:
                raise ValueError("Brightness is not supported by this display.")
            value = round(int(match[1]) / max(1, int(match[2])) * 100)
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as problem:
            error = "Enable DDC/CI in the monitor menu. " + str(problem)
    atomic_write(cache, json.dumps({"checked": time.time(), "value": value, "error": error}))
    return value, error


def monitor_rule(monitor, **changes):
    rule = {"output": monitor["name"], "mode": f"{monitor['width']}x{monitor['height']}@{monitor['refreshRate']}",
            "position": f"{monitor.get('x', 0)}x{monitor.get('y', 0)}", "scale": monitor.get("scale", 1),
            "transform": monitor.get("transform", 0), "disabled": False}
    rule.update(changes)
    return rule


def lua_rule(rule):
    return "hl.monitor({ " + ", ".join(key + " = " + json.dumps(value) for key, value in rule.items()) + " })"


def saved_monitor_rules():
    path = config_directory() / "display-settings.lua"
    if not path.exists():
        return {}
    return json.loads(path.read_text().splitlines()[0].removeprefix("-- Zephyrus display settings: "))


def apply_monitor_rules(rules, persist=True):
    command(["hyprctl", "eval", "; ".join(lua_rule(rule) for rule in rules)], True)
    if not persist:
        return
    path = config_directory() / "display-settings.lua"
    prefix = "-- Zephyrus display settings: "
    saved = saved_monitor_rules()
    for rule in rules:
        saved[rule["output"]] = rule
    # One atomic file contains both editable state and reloadable Lua rules.
    atomic_write(path, prefix + json.dumps(saved) + "\n" + "\n".join(lua_rule(rule) for rule in saved.values()) + "\n")


def display_action(name, value):
    monitors = json.loads(command(["hyprctl", "monitors", "all", "-j"], True))
    data = json.loads(value) if name != "primary" else {"name": value}
    if name == "display-order":
        enabled = [m for m in monitors if not m.get("disabled")]
        order = data.get("order", [])
        if len(order) != len(enabled) or set(order) != {m["name"] for m in enabled}:
            raise ValueError("Order must include every enabled display exactly once")
        rules, x = [], 0
        for connector in order:
            monitor = next(m for m in enabled if m["name"] == connector)
            rules.append(monitor_rule(monitor, position=f"{x}x0"))
            width = monitor["height"] if monitor.get("transform", 0) % 2 else monitor["width"]
            x += round(width / monitor.get("scale", 1))
        apply_monitor_rules(rules)
        return
    monitor = next((m for m in monitors if m["name"] == data.get("name")), None)
    if not monitor or not re.fullmatch(r"[A-Za-z0-9_-]+", monitor["name"]):
        raise ValueError("Unknown display")
    connector = monitor["name"]
    if name == "primary":
        if monitor.get("disabled"):
            raise ValueError("Enable the display first")
        atomic_write(STATE / "primary-display", connector)
    elif name == "display-ddc":
        bus = data.get("bus")
        if bus is not None and (type(bus) is not int or bus < 0 or bus > 9999):
            raise ValueError("Invalid DDC bus")
        path = config_directory() / "displays.json"
        config = json.loads(path.read_text()) if path.exists() else {}
        config.setdefault(connector, {})["ddcBus"] = bus
        atomic_write(path, json.dumps(config, indent=2) + "\n")
        ddc_brightness(ddc_bus(connector, display_config()), refresh=True)
    elif name == "display":
        if not isinstance(data.get("enabled"), bool):
            raise ValueError("Expected display state")
        if not data["enabled"] and not monitor.get("disabled") and len([m for m in monitors if not m.get("disabled")]) <= 1:
            raise ValueError("Keep at least one display enabled")
        # Keep geometry along with the preference, including when an output is
        # disabled and Hyprland no longer reports its original mode/scale.
        rule = saved_monitor_rules().get(connector) or (
            monitor_rule(monitor) if monitor.get("width") else
            {"output": connector, "mode": "preferred", "scale": "auto", "position": "auto"})
        rule = dict(rule, disabled=not data["enabled"])
        apply_monitor_rules([rule])
    elif name in ("display-mode", "display-scale"):
        if monitor.get("disabled"):
            raise ValueError("Enable the display first")
        if name == "display-mode":
            if data.get("mode") not in monitor.get("availableModes", []):
                raise ValueError("Unsupported display mode")
            mode = re.fullmatch(r"(\d+)x(\d+)@([\d.]+)(?:Hz)?", data["mode"])
            if not mode:
                raise ValueError("Unsupported display mode format")
            monitor.update(width=int(mode[1]), height=int(mode[2]), refreshRate=float(mode[3]))
        else:
            scale = float(data.get("scale", 0))
            if scale not in (1, 1.25, 1.5, 1.75, 2):
                raise ValueError("Unsupported display scale")
            monitor["scale"] = scale
        rules, x = [], 0
        for item in sorted((m for m in monitors if not m.get("disabled")), key=lambda m: m.get("x", 0)):
            rules.append(monitor_rule(item, position=f"{x}x0"))
            width = item["height"] if item.get("transform", 0) % 2 else item["width"]
            x += round(width / item.get("scale", 1))
        apply_monitor_rules(rules)


def primary_monitor(monitors):
    preferred = read(STATE / "primary-display")
    enabled = [m for m in monitors if not m.get("disabled")]
    return next((m for m in enabled if m["name"] == preferred), next((m for m in enabled if m.get("focused")), enabled[0] if enabled else {})).get("name", "")


def recover_displays(wake=False):
    """Recover a laptop output after a topology change, never during idle polling.

    Hyprland moves windows/workspaces when it removes an output. Enabling a real
    output also recovers workspaces parked on its temporary fallback monitor.
    """
    if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return
    monitors = json.loads(command(["hyprctl", "monitors", "all", "-j"], True))
    real = [m for m in monitors if m["name"] != "FALLBACK"]
    saved = saved_monitor_rules()
    # Reassert preferences after hotplug/resume, but never disable the last
    # usable attached display. The safety fallback does not erase preferences.
    desired = [m for m in real if not saved.get(m["name"], {}).get("disabled", m.get("disabled", False))]
    if desired:
        changes = [saved[m["name"]] for m in real if m["name"] in saved
                   and "disabled" in saved[m["name"]]
                   and bool(m.get("disabled")) != saved[m["name"]]["disabled"]]
        if changes:
            apply_monitor_rules(changes, persist=False)
            real = [dict(m, disabled=saved.get(m["name"], {}).get("disabled", m.get("disabled", False))) for m in real]
    enabled = [m for m in real if not m.get("disabled")]
    if not enabled:
        internal = next((m for m in real if m["name"].startswith(("eDP", "LVDS", "DSI"))), None)
        destination = internal or next(iter(real), None)
        if destination:
            apply_monitor_rules([{"output": destination["name"], "mode": "preferred", "scale": "auto",
                                  "position": "auto", "disabled": False}], persist=False)
            enabled = [destination]
    # A disabled output and DPMS blanking are different states. Wake the sole
    # internal panel if the external screen has disappeared while it was blank.
    if wake:
        for monitor in enabled:
            command(["hyprctl", "dispatch", 'hl.dsp.dpms({ action = "enable", monitor = '
                     + json.dumps(monitor["name"]) + ' })'], True)
    elif len(enabled) == 1 and enabled[0]["name"].startswith(("eDP", "LVDS", "DSI")):
        command(["hyprctl", "dispatch", 'hl.dsp.dpms({ action = "enable", monitor = '
                 + json.dumps(enabled[0]["name"]) + ' })'], True)


def power_status():
    # Avoid D-Bus activation of a competing power daemon on ASUS machines.
    if shutil.which("asusctl") and command(["systemctl", "is-active", "asusd.service"]) == "active":
        available = command(["asusctl", "profile", "list"]).splitlines()
        result = command(["asusctl", "profile", "get"])
        active = re.search(r"Active profile:\s*(\w+)", result)
        mapping = {"Quiet": "power-saver", "Balanced": "balanced", "Performance": "performance"}
        return {"backend": "asusd", "profile": mapping.get(active[1], "") if active else "",
                "profiles": [mapping[v] for v in available if v in mapping]}
    if shutil.which("powerprofilesctl") and command(["systemctl", "is-active", "power-profiles-daemon.service"]) == "active":
        available = command(["powerprofilesctl", "list"])
        return {"backend": "ppd", "profile": command(["powerprofilesctl", "get"]),
                "profiles": [v for v in ("power-saver", "balanced", "performance") if v + ":" in available]}
    return {"backend": "", "profile": "", "profiles": []}


def gpu_status():
    return {"mode": "", "modes": [], "error": "Applications select GPUs through switcheroo-control. Use ROG Control Center for supported firmware GPU modes; changes may require a reboot."}


def scheduled_shutdown():
    if not shutil.which("systemctl"):
        return ""
    try:
        result = subprocess.run(["systemctl", "poweroff", "--when=show"], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return ""
    status = (result.stdout or result.stderr).strip()
    return status if result.returncode == 0 and "No scheduled shutdown" not in status else ""


def clean_thumbnail_cache():
    cache_root = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))).expanduser()
    if not cache_root.is_absolute():
        raise ValueError("XDG_CACHE_HOME must be an absolute directory")
    thumbnails = cache_root / "thumbnails"
    if thumbnails.is_symlink():
        raise ValueError("Thumbnail cache is a symlink; refusing to remove it")
    if not thumbnails.exists():
        return
    if not thumbnails.is_dir() or thumbnails.stat().st_uid != os.getuid():
        raise ValueError("Thumbnail cache must be a directory owned by this user")
    if thumbnails.is_mount():
        raise ValueError("Thumbnail cache is a mount point; refusing to remove it")
    entries = list(thumbnails.iterdir())
    if any(entry.is_mount() for entry in entries):
        raise ValueError("Thumbnail cache contains a mount point; refusing to remove it")
    for entry in entries:
        if entry.is_dir() and not entry.is_symlink():
            shutil.rmtree(entry)
        else:
            entry.unlink()


def cpu_usage():
    def counters():
        values = [int(value) for value in read("/proc/stat").splitlines()[0].split()[1:]]
        return sum(values), values[3] + values[4]

    first_total, first_idle = counters()
    time.sleep(0.12)
    last_total, last_idle = counters()
    elapsed = last_total - first_total
    return round(100 * (1 - (last_idle - first_idle) / elapsed)) if elapsed > 0 else 0


def gpu_hardware():
    cards = []
    for card in sorted(Path("/sys/class/drm").glob("card[0-9]*")):
        device = card / "device"
        if not (device / "vendor").exists():
            continue
        pci_address = device.resolve().name
        description = command(["lspci", "-s", pci_address, "-mm"]) if shutil.which("lspci") else ""
        match = re.search(r'"(?:VGA compatible controller|3D controller|Display controller)"\s+"[^"]+"\s+"([^"]+)"', description)
        name = match[1] if match else "Graphics " + pci_address
        product = re.search(r"\[([^]]+)\]", name)
        if product and "/" not in product[1]:
            name = product[1]
        elif product and "Radeon RX" in product[1]:
            series = re.search(r"Radeon RX (\d)", product[1])
            name = f"AMD Radeon RX {series[1]}000 series" if series else name.split(" [", 1)[0]
        else:
            name = re.sub(r"\s*\[[^]]+\]", "", name).strip()
        busy = read(device / "gpu_busy_percent") if read(device / "power/runtime_status") != "suspended" else ""
        cards.append({"name": name, "usage": min(100, max(0, int(busy))) if busy.isdigit() else None})
    return cards


def temperature_summary(temperatures, kind):
    """Prefer package/edge readings; the combined card shows the hottest matching device."""
    drivers = r"k10temp|coretemp|zenpower" if kind == "cpu" else r"amdgpu|nouveau|nvidia"
    candidates = [sensor for sensor in temperatures if re.fullmatch(drivers, sensor["driver"])]
    if not candidates:
        return None
    preferred = r"Tctl|Tdie|Package.*" if kind == "cpu" else r"edge|GPU.*|temp1"
    main = [sensor for sensor in candidates if re.fullmatch(preferred, sensor["label"], re.IGNORECASE)]
    return max(main or candidates, key=lambda sensor: (sensor["value"], sensor["driver"], sensor["label"]))


def boost_control_error():
    if read("/sys/devices/system/cpu/cpufreq/boost") not in ("0", "1"):
        return "This kernel does not expose a CPU boost switch."
    try:
        for path in (CPU_BOOST_HELPER, CPU_BOOST_HELPER.parent):
            info = path.stat()
            if info.st_uid != 0 or info.st_mode & 0o022:
                return "Reinstall the CPU boost helper with administrator ownership."
        if not os.access(CPU_BOOST_HELPER, os.X_OK):
            raise FileNotFoundError()
    except OSError:
        return "Install CPU boost control with sudo bash scripts/install-controls.sh."
    return ""


def hardware(*, hwmon_root=Path("/sys/class/hwmon")):
    mem = {line.split(":")[0]: int(line.split()[1]) for line in read("/proc/meminfo").splitlines() if len(line.split()) >= 2}
    total = mem.get("MemTotal", 0); used = total - mem.get("MemAvailable", total)
    temperatures = []
    fans = []
    for hw in sorted(hwmon_root.glob("*")):
        # Reading amdgpu sensors can wake a suspended dGPU.
        if read(hw / "device/power/runtime_status") == "suspended":
            continue
        for f in sorted(hw.glob("temp*_input")):
            value = read(f)
            if value.lstrip("-").isdigit():
                temperatures.append({"driver": read(hw / "name"), "label": read(f.with_name(f.name.replace("_input", "_label")), f.name.removesuffix("_input")), "value": round(int(value) / 1000)})
        for f in hw.glob("fan*_input"):
            if read(f).isdigit(): fans.append({"label": read(hw / "name") + " " + f.stem, "value": read(f)})
    processor = next((line.split(":", 1)[1].strip() for line in read("/proc/cpuinfo").splitlines() if line.startswith("model name")), "Processor")
    processor = re.sub(r"\s+with Radeon Graphics$", "", processor)
    storage = shutil.disk_usage("/")
    graphics = gpu_hardware()
    gpu_loads = [card["usage"] for card in graphics if card["usage"] is not None]
    return {"cpuName": processor, "cpuPercent": cpu_usage(), "gpuName": " + ".join(card["name"] for card in graphics) or "Graphics", "gpuPercent": max(gpu_loads) if gpu_loads else None,
            "memoryPercent": round(used / max(total, 1) * 100), "memoryUsed": round(used / 1048576, 1), "memoryTotal": round(total / 1048576, 1),
            "storagePercent": round((storage.total - storage.free) / max(storage.total, 1) * 100), "storageUsed": round((storage.total - storage.free) / 1073741824, 1), "storageTotal": round(storage.total / 1073741824, 1),
            "temperatures": temperatures, "cpuTemperature": temperature_summary(temperatures, "cpu"),
            "gpuTemperature": temperature_summary(temperatures, "gpu"),
            "fans": fans, "load": read("/proc/loadavg").split(" ")[0], "boost": read("/sys/devices/system/cpu/cpufreq/boost"), "boostControlError": boost_control_error()}


def external_power_online(supply_root=Path("/sys/class/power_supply")):
    """Keep adapter presence separate from a pack's charging/discharging state."""
    readings = []
    for supply in sorted(supply_root.glob("*")):
        kind = read(supply / "type")
        if read(supply / "scope") == "Device" or not (kind == "Mains" or kind == "Wireless" or kind.startswith("USB")):
            continue
        online = read(supply / "online")
        if online in ("0", "1"):
            readings.append(online == "1")
    return any(readings) if readings else None


def battery_status_text(status, external_power):
    descriptions = {"Charging": "Charging", "Discharging": "Battery discharging", "Full": "Fully charged", "Not charging": "Not charging"}
    description = descriptions.get(status, "Battery status unavailable")
    if external_power is True:
        return "Plugged in · " + description
    if status == "Discharging" and external_power is False:
        return "On battery"
    return description


def battery_details(*, supply_root=Path("/sys/class/power_supply")):
    """Read pack details only on expansion, without commands or privileged access."""
    def number(pack, field):
        try:
            value = float(read(pack / field))
            return value if math.isfinite(value) and value >= 0 else None
        except ValueError:
            return None

    external_power = external_power_online(supply_root)
    packs = []
    for pack in sorted(supply_root.glob("*")):
        if read(pack / "type") != "Battery" or read(pack / "scope") == "Device" or read(pack / "present") == "0":
            continue
        # Keep capacity pairs in the same units; some drivers only report charge.
        unit, scale = "Wh", 1000000
        full, design, now = [number(pack, field) for field in ("energy_full", "energy_full_design", "energy_now")]
        if not full or not design:
            charge = [number(pack, field) for field in ("charge_full", "charge_full_design", "charge_now")]
            if (charge[0] and charge[1]) or not any(value is not None for value in (full, design, now)):
                unit, scale = "mAh", 1000
                full, design, now = charge
        health = round(full / design * 100, 1) if full and design else None
        power = number(pack, "power_now")
        current, voltage = number(pack, "current_now"), number(pack, "voltage_now")
        watts = power / 1000000 if power is not None else current * voltage / 1e12 if current is not None and voltage is not None else None
        status = read(pack / "status")
        charge_limit = number(pack, "charge_control_end_threshold")
        if charge_limit is None or not 50 <= charge_limit <= 100:
            charge_limit = 100
        rate = power if unit == "Wh" else current
        seconds = None
        if rate and now is not None and (status == "Charging" or status == "Discharging" and external_power is not True):
            remaining = max(0, full * charge_limit / 100 - now) if status == "Charging" and full else now if status == "Discharging" else None
            if remaining is not None and remaining > 0:
                seconds = round(remaining / rate * 3600)
        temperature = number(pack, "temp")
        packs.append({
            "name": pack.name, "manufacturer": read(pack / "manufacturer"), "model": read(pack / "model_name"),
            "technology": {"Li-ion": "Lithium-ion", "Li-poly": "Lithium-polymer", "NiMH": "Nickel-metal hydride"}.get(read(pack / "technology"), read(pack / "technology")),
            "status": status, "statusText": battery_status_text(status, external_power), "externalPower": external_power,
            "percent": number(pack, "capacity"), "healthPercent": health,
            "fullCapacity": full / scale if full else None, "designCapacity": design / scale if design else None,
            "capacityUnit": unit, "watts": watts, "seconds": seconds, "chargeLimit": charge_limit,
            "cycles": number(pack, "cycle_count"), "temperature": temperature / 10 if temperature is not None else None,
        })
    return {"batteries": packs}


def snapshot(refresh_ddc=False):
    light = backlight()
    batteries = [p for p in Path("/sys/class/power_supply").glob("*") if read(p / "type") == "Battery" and read(p / "scope") != "Device"]
    battery = batteries[0] if batteries else None
    power_policy = power_status()
    monitors = json.loads(command(["hyprctl", "monitors", "all", "-j"]) or "[]") if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") else []
    aliases = display_config()
    for monitor in monitors:
        monitor["label"] = aliases.get(monitor["name"], {}).get("label", monitor.get("description") or monitor["name"])
    primary = primary_monitor(monitors)
    power = float(read(battery / "power_now", "0")) / 1000000 if battery else 0
    energy = float(read(battery / "energy_now", "0")) / 1000000 if battery else 0
    full = float(read(battery / "energy_full", "0")) / 1000000 if battery else 0
    status = read(battery / "status") if battery else ""
    external_power = external_power_online()
    hours = ((full - energy) if status == "Charging" else energy) / power if power > 0 else 0
    minutes = round(max(0, hours) * 60)
    estimate_available = status == "Charging" or status == "Discharging" and external_power is not True
    battery_info = (f"{minutes // 60}h {minutes % 60}m " + ("until charged" if status == "Charging" else "remaining")) if minutes and estimate_available else battery_status_text(status, external_power) if battery else ""
    if power > 0 and status == "Discharging": battery_info += f" · {power:.1f} W"
    external = ddc_bus(primary, aliases) if primary and not primary.startswith(("eDP", "LVDS")) else None
    brightness_error = ""
    brightness = round(int(read(light / "brightness", "0")) / max(1, int(read(light / "max_brightness", "1"))) * 100) if light else 0
    can_brighten = bool(light) and (not primary or primary.startswith(("eDP", "LVDS")))
    if primary and not primary.startswith(("eDP", "LVDS")):
        value, brightness_error = ddc_brightness(external, refresh=refresh_ddc)
        can_brighten = value is not None
        brightness = value or 0
    for monitor in monitors:
        monitor["ddcBus"] = ddc_bus(monitor["name"], aliases) if not monitor["name"].startswith(("eDP", "LVDS")) else None
    monitors.sort(key=lambda m: (bool(m.get("disabled")), m.get("x", 0), m.get("y", 0)))
    return dict(
        hardware=hardware(), gpu=gpu_status(), primary=primary, brightnessAvailable=can_brighten,
        brightnessError=brightness_error, ddcBuses=[int(p.name.removeprefix("i2c-")) for p in sorted(Path("/dev").glob("i2c-*"))],
        batteryPercent=int(read(battery / "capacity", "0")) if battery else 0,
        batteryStatus=status, batteryInfo=battery_info, externalPower=external_power,
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
        profile=power_policy["profile"], profiles=power_policy["profiles"],
        powerBackend=power_policy["backend"],
        scheduledShutdown=scheduled_shutdown(),
        asus=bool(shutil.which("asusctl")),
        hyprland=bool(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")),
        monitors=monitors,
    )


def action(name, value):
    if name == "wifi" and value in ("on", "off"):
        command(["nmcli", "radio", "wifi", value], True)
    elif name == "profile" and value in ("power-saver", "balanced", "performance"):
        policy = power_status()
        if value not in policy["profiles"]:
            raise ValueError("Power profile is unavailable")
        if policy["backend"] == "asusd":
            command(["asusctl", "profile", "set", {"power-saver": "Quiet", "balanced": "Balanced", "performance": "Performance"}[value]], True)
        else:
            command(["powerprofilesctl", "set", value], True)
    elif name == "gpu":
        raise ValueError("Use the application's GPU selection or ROG Control Center")
    elif name == "cpu-boost" and value in ("on", "off"):
        error = boost_control_error()
        if error:
            raise ValueError(error)
        command(["pkexec", str(CPU_BOOST_HELPER), "1" if value == "on" else "0"], True, 120)
    elif name == "chargeLimit":
        percent = int(value)
        if not 50 <= percent <= 100: raise ValueError("Charge limit must be between 50 and 100")
        battery = next((p for p in Path("/sys/class/power_supply").glob("*") if read(p / "type") == "Battery" and (p / "charge_control_end_threshold").exists()), None)
        if battery is None: raise ValueError("Charge limit is unavailable")
        if power_status()["backend"] == "asusd":
            command(["asusctl", "battery", "limit", str(percent)], True)
        else:
            raise ValueError("Use your system's battery charge-limit settings")
    elif name == "schedule-poweroff":
        if value not in ("15", "30", "60", "90", "120", "180", "240", "300"):
            raise ValueError("Unsupported shutdown delay")
        command(["systemctl", "poweroff", f"--when=+{value}min"], True, 60)
    elif name == "cancel-poweroff":
        command(["systemctl", "poweroff", "--when=cancel"], True, 60)
    elif name == "clean-thumbnails" and value == "confirm":
        clean_thumbnail_cache()
    elif name == "recover-displays":
        recover_displays()
    elif name == "wake-displays":
        recover_displays(wake=True)
    elif name in ("primary", "display", "display-mode", "display-scale", "display-order", "display-ddc"):
        display_action(name, value)
    elif name == "brightness":
        percent = int(value)
        if not 5 <= percent <= 100:
            raise ValueError("Brightness must be between 5 and 100")
        monitors = json.loads(command(["hyprctl", "monitors", "all", "-j"]) or "[]") if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") else []
        primary = primary_monitor(monitors)
        bus = ddc_bus(primary, display_config()) if primary and not primary.startswith(("eDP", "LVDS")) else None
        if bus is not None:
            command(["ddcutil", "--bus", str(int(bus)), "setvcp", "10", str(percent)], True)
            (STATE / ("ddc-brightness-" + str(bus) + ".json")).unlink(missing_ok=True)
            return {"ok": True}
        if primary and not primary.startswith(("eDP", "LVDS")): raise ValueError("No DDC bus found. Choose one in Display settings.")
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
        managed = subprocess.run(["uwsm", "check", "is-active"], capture_output=True, timeout=5).returncode == 0
        command(["uwsm", "stop"] if managed else ["hyprctl", "dispatch", "hl.dsp.exit()"], True)
    else:
        raise ValueError("Unsupported action or value")
    return {"ok": True}


if __name__ == "__main__":
    try:
        operation = sys.argv[1]
        print(json.dumps(snapshot(len(sys.argv) > 2 and sys.argv[2] == "refresh") if operation == "snapshot" else battery_details() if operation == "battery-details" else action(operation, sys.argv[2] if len(sys.argv) > 2 else "")))
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(json.dumps({"error": str(error)}))
        sys.exit(1)
