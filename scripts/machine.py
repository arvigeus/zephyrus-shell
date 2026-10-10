"""On-demand hardware snapshot and allowlisted actions. No resident polling daemon."""

import fcntl
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CPU_BOOST_HELPER = Path("/usr/lib/zephyrus-shell/cpu-boost")
STATE = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "zephyrus-shell"
SUPPLIES = Path("/sys/class/power_supply")
MODE = re.compile(r"(\d+)x(\d+)@([\d.]+)(?:Hz)?")


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


def is_internal(connector):
    """Built-in panels use the backlight; other outputs use DDC/CI."""
    return connector.startswith(("eDP", "LVDS", "DSI"))


def in_hyprland():
    return bool(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"))


def connected_monitors():
    """Hyprland outputs, without its temporary headless FALLBACK output."""
    outputs = json.loads(command(["hyprctl", "monitors", "all", "-j"], True))
    return [m for m in outputs if m["name"] != "FALLBACK"]


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


def ddc_cache(bus):
    return STATE / f"ddc-brightness-{bus}.json"


def ddc_brightness(bus, refresh=False, device_root=Path("/dev")):
    """Read DDC brightness, cached for a minute: a DDC probe takes about a second."""
    if not refresh:
        try:
            saved = json.loads(ddc_cache(bus).read_text())
            if time.time() - saved["checked"] < 60:
                return saved["value"], saved["error"]
        except (OSError, ValueError, KeyError):
            pass
    value, error = None, ""
    if not shutil.which("ddcutil"):
        error = "Install ddcutil for external display brightness."
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
    atomic_write(ddc_cache(bus), json.dumps({"checked": time.time(), "value": value, "error": error}))
    return value, error


def monitor_rule(monitor, **changes):
    rule = {
        "output": monitor["name"],
        "mode": f"{monitor['width']}x{monitor['height']}@{monitor['refreshRate']}",
        "position": f"{monitor.get('x', 0)}x{monitor.get('y', 0)}",
        "scale": monitor.get("scale", 1),
        "transform": monitor.get("transform", 0),
        "disabled": False,
    }
    rule.update(changes)
    return rule


def lua_rule(rule):
    return (
        "hl.monitor({ "
        + ", ".join(key + " = " + json.dumps(value) for key, value in rule.items())
        + " })"
    )


def legacy_monitor_rules():
    """Connector rules from the old display-settings.lua, read only for migration."""
    path = config_directory() / "display-settings.lua"
    if not path.exists():
        return {}
    return json.loads(
        path.read_text().splitlines()[0].removeprefix("-- Zephyrus display settings: ")
    )


@contextmanager
def display_lock():
    directory = config_directory()
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / ".display.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def display_identities(monitors):
    identities = {}
    for monitor in monitors:
        details = [monitor.get(field, "") for field in ("make", "model", "serial")]
        if not any(details):
            details = [monitor.get("description") or monitor["name"]]
        identities[monitor["name"]] = json.dumps(details, ensure_ascii=True)
    # Identical displays without unique serials can only be distinguished by
    # their connector. Never silently collapse two outputs into one profile.
    return {
        name: identity
        if list(identities.values()).count(identity) == 1
        else json.dumps([identity, name])
        for name, identity in identities.items()
    }


def display_profiles() -> dict[str, Any] | None:
    path = config_directory() / "display-profiles.json"
    return json.loads(path.read_text()) if path.exists() else None


def display_setup(monitors, profiles):
    """Rules for the connected set: its saved setup, else per-monitor memory."""
    identities = display_identities(monitors)
    key = json.dumps(sorted(identities.values()))
    if profiles is not None and key in profiles["setups"]:
        return (
            identities,
            key,
            {
                m["name"]: dict(profiles["setups"][key][identities[m["name"]]], output=m["name"])
                for m in monitors
            },
        )
    legacy = legacy_monitor_rules() if profiles is None else {}
    rules = {}
    for monitor in monitors:
        name = monitor["name"]
        remembered = (profiles or {}).get("monitors", {}).get(identities[name])
        rule: dict[str, Any]
        if remembered:
            rule = dict(remembered, output=name)
        elif name in legacy:
            rule = dict(legacy[name])
        elif profiles is None and monitor.get("width") and monitor.get("height"):
            rule = monitor_rule(monitor, disabled=bool(monitor.get("disabled")))
        else:
            # A new physical monitor must not inherit the mode/scale/disabled
            # state of connector rules that may still be active in the compositor.
            rule = {
                "output": name,
                "mode": "preferred",
                "position": "auto",
                "scale": "auto",
                "transform": 0,
                "disabled": profiles is None and bool(monitor.get("disabled")),
            }
        rules[name] = rule
    # A new topology inherits each physical monitor's settings, with a fresh
    # layout. Dock coordinates must not leave gaps/overlaps in laptop-only use.
    if profiles is not None:
        enabled = [rule for rule in rules.values() if not rule.get("disabled")]
        for rule in enabled:
            rule["position"] = "0x0" if len(enabled) == 1 else "auto"
    return identities, key, rules


def save_display_setup(monitors, rules, profiles: dict[str, Any] | None = None):
    identities = display_identities(monitors)
    key = json.dumps(sorted(identities.values()))
    if profiles is None:
        profiles = {"version": 1, "monitors": {}, "setups": {}}
    setup = {
        identities[name]: {k: v for k, v in rule.items() if k != "output"}
        for name, rule in rules.items()
    }
    profiles["setups"][key] = setup
    profiles["monitors"].update(setup)
    atomic_write(
        config_directory() / "display-profiles.json", json.dumps(profiles, indent=2) + "\n"
    )


def apply_monitor_rules(rules, persist=True, monitors=None):
    command(["hyprctl", "eval", "; ".join(lua_rule(rule) for rule in rules)], True)
    if not persist:
        return
    profiles = display_profiles()
    _, _, saved = display_setup(monitors, profiles)
    for rule in rules:
        saved[rule["output"]] = rule
    save_display_setup(monitors, saved, profiles)


def reflow(ordered):
    """Place monitors left to right in the given order, without gaps or overlap."""
    rules, x = [], 0
    for monitor in ordered:
        rules.append(monitor_rule(monitor, position=f"{x}x0"))
        width = monitor["height"] if monitor.get("transform", 0) % 2 else monitor["width"]
        x += round(width / monitor.get("scale", 1))
    return rules


def display_action(name, value):
    with display_lock():
        return _display_action(name, value)


def _display_action(name, value):
    monitors = connected_monitors()
    enabled = [m for m in monitors if not m.get("disabled")]
    if name == "display-save":
        if not enabled:
            raise ValueError("Keep at least one display enabled")
        profiles = display_profiles()
        _, _, saved = display_setup(monitors, profiles)
        for monitor in monitors:
            if monitor.get("width") and monitor.get("height"):
                saved[monitor["name"]] = monitor_rule(
                    monitor, disabled=bool(monitor.get("disabled"))
                )
            else:
                saved[monitor["name"]]["disabled"] = bool(monitor.get("disabled"))
        save_display_setup(monitors, saved, profiles)
        return
    data = json.loads(value) if name != "primary" else {"name": value}
    if name == "display-order":
        order = data.get("order", [])
        if len(order) != len(enabled) or set(order) != {m["name"] for m in enabled}:
            raise ValueError("Order must include every enabled display exactly once")
        by_name = {m["name"]: m for m in enabled}
        apply_monitor_rules(reflow(by_name[connector] for connector in order), monitors=monitors)
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
        if not data["enabled"] and not monitor.get("disabled") and len(enabled) <= 1:
            raise ValueError("Keep at least one display enabled")
        # Keep geometry along with the preference, including when an output is
        # disabled and Hyprland no longer reports its original mode/scale.
        rule = (
            display_setup(monitors, display_profiles())[2][connector]
            if monitor.get("disabled")
            else monitor_rule(monitor)
        )
        apply_monitor_rules([dict(rule, disabled=not data["enabled"])], monitors=monitors)
    elif name in ("display-mode", "display-scale"):
        if monitor.get("disabled"):
            raise ValueError("Enable the display first")
        if name == "display-mode":
            if data.get("mode") not in monitor.get("availableModes", []):
                raise ValueError("Unsupported display mode")
            mode = MODE.fullmatch(data["mode"])
            if not mode:
                raise ValueError("Unsupported display mode format")
            monitor.update(width=int(mode[1]), height=int(mode[2]), refreshRate=float(mode[3]))
        else:
            scale = float(data.get("scale", 0))
            if scale not in (1, 1.25, 1.5, 1.75, 2):
                raise ValueError("Unsupported display scale")
            monitor["scale"] = scale
        apply_monitor_rules(
            reflow(sorted(enabled, key=lambda m: m.get("x", 0))), monitors=monitors
        )
    else:
        raise ValueError("Unsupported display action")


def primary_monitor(monitors):
    preferred = read(STATE / "primary-display")
    enabled = [m for m in monitors if not m.get("disabled")]
    return next(
        (m for m in enabled if m["name"] == preferred),
        next((m for m in enabled if m.get("focused")), enabled[0] if enabled else {}),
    ).get("name", "")


def monitor_rule_matches(monitor, rule):
    if bool(monitor.get("disabled")) != bool(rule.get("disabled")):
        return False
    if rule.get("disabled"):
        return True
    # Symbolic defaults have no numeric value to compare with a snapshot.
    # Reassert them on topology events so a reused connector cannot retain a
    # previous monitor's explicit mode or scale.
    if (
        rule.get("scale") == "auto"
        or rule.get("position") == "auto"
        or rule.get("mode") in ("preferred", "highres", "highrr")
    ):
        return False
    mode = MODE.fullmatch(rule.get("mode", ""))
    return (
        abs(monitor.get("scale", 1) - rule.get("scale", 1)) <= 0.001
        and monitor.get("transform", 0) == rule.get("transform", 0)
        and rule.get("position") == f"{monitor.get('x', 0)}x{monitor.get('y', 0)}"
        and (
            not mode
            or (
                monitor.get("width") == int(mode[1])
                and monitor.get("height") == int(mode[2])
                and abs(monitor.get("refreshRate", 0) - float(mode[3])) < 0.1
            )
        )
    )


def restore_display_setup():
    real = connected_monitors()
    if not real:
        return []
    profiles = display_profiles()
    _, key, saved = display_setup(real, profiles)
    desired = [m for m in real if not saved[m["name"]].get("disabled")]
    if not desired:
        destination = next((m for m in real if is_internal(m["name"])), real[0])
        # Preserve mode/scale/rotation when making the last attached screen
        # usable. This belongs to the laptop-only setup, not its docked one.
        saved[destination["name"]] = dict(
            saved[destination["name"]], disabled=False, position="0x0"
        )
        desired = [destination]
    changes = [saved[m["name"]] for m in real if not monitor_rule_matches(m, saved[m["name"]])]
    if changes:
        # Enable destinations before disabling the temporary fallback output.
        apply_monitor_rules(sorted(changes, key=lambda r: bool(r.get("disabled"))), persist=False)
    if profiles is None or key not in profiles["setups"]:
        save_display_setup(real, saved, profiles)
    return desired


def recover_displays(wake=False):
    """Reapply the connected setup's layout after a topology change or wake.

    Hyprland moves windows/workspaces when it removes an output. Enabling a real
    output also recovers workspaces parked on its temporary fallback monitor.
    """
    if not in_hyprland():
        return
    with display_lock():
        enabled = restore_display_setup()
    # A disabled output and DPMS blanking are different states. Wake the sole
    # internal panel if the external screen has disappeared while it was blank.
    if not wake and not (len(enabled) == 1 and is_internal(enabled[0]["name"])):
        return
    for monitor in enabled:
        command(
            [
                "hyprctl",
                "dispatch",
                'hl.dsp.dpms({ action = "enable", monitor = ' + json.dumps(monitor["name"]) + " })",
            ],
            True,
        )


ASUS_PROFILES = {"power-saver": "Quiet", "balanced": "Balanced", "performance": "Performance"}


def power_status():
    # Avoid D-Bus activation of a competing power daemon on ASUS machines.
    if shutil.which("asusctl") and command(["systemctl", "is-active", "asusd.service"]) == "active":
        available = command(["asusctl", "profile", "list"]).splitlines()
        active = re.search(r"Active profile:\s*(\w+)", command(["asusctl", "profile", "get"]))
        return {
            "backend": "asusd",
            "profile": next((k for k, v in ASUS_PROFILES.items() if active and v == active[1]), ""),
            "profiles": [k for k, v in ASUS_PROFILES.items() if v in available],
        }
    if (
        shutil.which("powerprofilesctl")
        and command(["systemctl", "is-active", "power-profiles-daemon.service"]) == "active"
    ):
        available = command(["powerprofilesctl", "list"])
        return {
            "backend": "ppd",
            "profile": command(["powerprofilesctl", "get"]),
            "profiles": [v for v in ASUS_PROFILES if v + ":" in available],
        }
    return {"backend": "", "profile": "", "profiles": []}


def scheduled_shutdown():
    if not shutil.which("systemctl"):
        return ""
    try:
        result = subprocess.run(
            ["systemctl", "poweroff", "--when=show"], capture_output=True, text=True, timeout=5
        )
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
        match = re.search(
            r'"(?:VGA compatible controller|3D controller|Display controller)"\s+"[^"]+"\s+"([^"]+)"',
            description,
        )
        name = match[1] if match else "Graphics " + pci_address
        product = re.search(r"\[([^]]+)\]", name)
        if product and "/" not in product[1]:
            name = product[1]
        elif product and "Radeon RX" in product[1]:
            series = re.search(r"Radeon RX (\d)", product[1])
            name = f"AMD Radeon RX {series[1]}000 series" if series else name.split(" [", 1)[0]
        else:
            name = re.sub(r"\s*\[[^]]+\]", "", name).strip()
        # Reading a suspended dGPU would wake it.
        busy = (
            read(device / "gpu_busy_percent")
            if read(device / "power/runtime_status") != "suspended"
            else ""
        )
        cards.append(
            {"name": name, "usage": min(100, max(0, int(busy))) if busy.isdigit() else None}
        )
    return cards


def temperature_summary(temperatures, kind):
    """Prefer package/edge readings; the combined card shows the hottest matching device."""
    drivers = r"k10temp|coretemp|zenpower" if kind == "cpu" else r"amdgpu|nouveau|nvidia"
    candidates = [sensor for sensor in temperatures if re.fullmatch(drivers, sensor["driver"])]
    if not candidates:
        return None
    preferred = r"Tctl|Tdie|Package.*" if kind == "cpu" else r"edge|GPU.*|temp1"
    main = [
        sensor for sensor in candidates if re.fullmatch(preferred, sensor["label"], re.IGNORECASE)
    ]
    return max(
        main or candidates, key=lambda sensor: (sensor["value"], sensor["driver"], sensor["label"])
    )


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
        return "Install the zephyrus-shell package for CPU boost control."
    return ""


def hardware(*, hwmon_root=Path("/sys/class/hwmon")):
    mem = {
        line.split(":")[0]: int(line.split()[1])
        for line in read("/proc/meminfo").splitlines()
        if len(line.split()) >= 2
    }
    total = mem.get("MemTotal", 0)
    used = total - mem.get("MemAvailable", total)
    temperatures = []
    fans = []
    for hw in sorted(hwmon_root.glob("*")):
        # Reading amdgpu sensors can wake a suspended dGPU.
        if read(hw / "device/power/runtime_status") == "suspended":
            continue
        for f in sorted(hw.glob("temp*_input")):
            value = read(f)
            if value.lstrip("-").isdigit():
                temperatures.append(
                    {
                        "driver": read(hw / "name"),
                        "label": read(
                            f.with_name(f.name.replace("_input", "_label")),
                            f.name.removesuffix("_input"),
                        ),
                        "value": round(int(value) / 1000),
                    }
                )
        for f in hw.glob("fan*_input"):
            if read(f).isdigit():
                fans.append({"label": read(hw / "name") + " " + f.stem, "value": read(f)})
    processor = next(
        (
            line.split(":", 1)[1].strip()
            for line in read("/proc/cpuinfo").splitlines()
            if line.startswith("model name")
        ),
        "Processor",
    )
    processor = re.sub(r"\s+with Radeon Graphics$", "", processor)
    storage = shutil.disk_usage("/")
    graphics = gpu_hardware()
    gpu_loads = [card["usage"] for card in graphics if card["usage"] is not None]
    return {
        "cpuName": processor,
        "cpuPercent": cpu_usage(),
        "gpuName": " + ".join(card["name"] for card in graphics) or "Graphics",
        "gpuPercent": max(gpu_loads) if gpu_loads else None,
        "memoryPercent": round(used / max(total, 1) * 100),
        "memoryUsed": round(used / 1048576, 1),
        "memoryTotal": round(total / 1048576, 1),
        "storagePercent": round((storage.total - storage.free) / max(storage.total, 1) * 100),
        "storageUsed": round((storage.total - storage.free) / 1073741824, 1),
        "storageTotal": round(storage.total / 1073741824, 1),
        "temperatures": temperatures,
        "cpuTemperature": temperature_summary(temperatures, "cpu"),
        "gpuTemperature": temperature_summary(temperatures, "gpu"),
        "fans": fans,
        "load": read("/proc/loadavg").split(" ")[0],
        "boost": read("/sys/devices/system/cpu/cpufreq/boost"),
        "boostControlError": boost_control_error(),
    }


def external_power_online(supply_root=SUPPLIES):
    """Keep adapter presence separate from a pack's charging/discharging state."""
    readings = []
    for supply in sorted(supply_root.glob("*")):
        kind = read(supply / "type")
        if read(supply / "scope") == "Device" or not (
            kind == "Mains" or kind == "Wireless" or kind.startswith("USB")
        ):
            continue
        online = read(supply / "online")
        if online in ("0", "1"):
            readings.append(online == "1")
    return any(readings) if readings else None


def battery_status_text(status, external_power):
    descriptions = {
        "Charging": "Charging",
        "Discharging": "Battery discharging",
        "Full": "Fully charged",
        "Not charging": "Not charging",
    }
    description = descriptions.get(status, "Battery status unavailable")
    if external_power is True:
        return "Plugged in · " + description
    if status == "Discharging" and external_power is False:
        return "On battery"
    return description


def battery_details(*, supply_root=SUPPLIES):
    """System battery packs from sysfs, without commands or privileged access."""

    def number(pack, field):
        try:
            value = float(read(pack / field))
            return value if math.isfinite(value) and value >= 0 else None
        except ValueError:
            return None

    external_power = external_power_online(supply_root)
    packs = []
    for pack in sorted(supply_root.glob("*")):
        if (
            read(pack / "type") != "Battery"
            or read(pack / "scope") == "Device"
            or read(pack / "present") == "0"
        ):
            continue
        # Keep capacity pairs in the same units; some drivers only report charge.
        unit, scale = "Wh", 1000000
        full, design, now = [
            number(pack, field) for field in ("energy_full", "energy_full_design", "energy_now")
        ]
        if not full or not design:
            charge = [
                number(pack, field) for field in ("charge_full", "charge_full_design", "charge_now")
            ]
            if (charge[0] and charge[1]) or not any(
                value is not None for value in (full, design, now)
            ):
                unit, scale = "mAh", 1000
                full, design, now = charge
        health = round(full / design * 100, 1) if full and design else None
        power = number(pack, "power_now")
        current, voltage = number(pack, "current_now"), number(pack, "voltage_now")
        watts = (
            power / 1000000
            if power is not None
            else current * voltage / 1e12
            if current is not None and voltage is not None
            else None
        )
        status = read(pack / "status")
        threshold = number(pack, "charge_control_end_threshold")
        charge_limit = threshold if threshold is not None and 50 <= threshold <= 100 else 100
        rate = power if unit == "Wh" else current
        seconds = None
        if (
            rate
            and now is not None
            and (status == "Charging" or status == "Discharging" and external_power is not True)
        ):
            remaining = (
                max(0, full * charge_limit / 100 - now)
                if status == "Charging" and full
                else now
                if status == "Discharging"
                else None
            )
            if remaining is not None and remaining > 0:
                seconds = round(remaining / rate * 3600)
        temperature = number(pack, "temp")
        packs.append(
            {
                "name": pack.name,
                "manufacturer": read(pack / "manufacturer"),
                "model": read(pack / "model_name"),
                "technology": {
                    "Li-ion": "Lithium-ion",
                    "Li-poly": "Lithium-polymer",
                    "NiMH": "Nickel-metal hydride",
                }.get(read(pack / "technology"), read(pack / "technology")),
                "status": status,
                "statusText": battery_status_text(status, external_power),
                "externalPower": external_power,
                "percent": number(pack, "capacity"),
                "healthPercent": health,
                "fullCapacity": full / scale if full else None,
                "designCapacity": design / scale if design else None,
                "capacityUnit": unit,
                "watts": watts,
                "seconds": seconds,
                "chargeLimit": charge_limit,
                "chargeLimitSupported": threshold is not None,
                "cycles": number(pack, "cycle_count"),
                "temperature": temperature / 10 if temperature is not None else None,
            }
        )
    return {"batteries": packs}


def battery_summary(pack, charge_limit_control):
    """The one-line battery state under the drawer's battery bar."""
    if pack is None:
        return {"batteryPresent": False, "batteryInfo": "", "chargeLimit": ""}
    minutes = round((pack["seconds"] or 0) / 60)
    info = (
        f"{minutes // 60}h {minutes % 60}m "
        + ("until charged" if pack["status"] == "Charging" else "remaining")
        if minutes
        else pack["statusText"]
    )
    if pack["status"] == "Discharging" and pack["watts"]:
        info += f" · {pack['watts']:.1f} W"
    return {
        "batteryPresent": True,
        "batteryPercent": pack["percent"] or 0,
        "batteryStatus": pack["status"],
        "batteryInfo": info,
        # The slider is enabled only where the charge-limit action can work.
        "chargeLimit": round(pack["chargeLimit"])
        if charge_limit_control and pack["chargeLimitSupported"]
        else "",
    }


def brightness_target(monitors):
    """The primary output and, for an external one, its DDC bus."""
    primary = primary_monitor(monitors)
    external = bool(primary) and not is_internal(primary)
    return primary, external, ddc_bus(primary, display_config()) if external else None


def snapshot(refresh_ddc=False):
    power_policy = power_status()
    monitors = []
    if in_hyprland():
        try:
            monitors = connected_monitors()
        except (RuntimeError, ValueError, OSError, subprocess.SubprocessError):
            pass
    aliases = display_config()
    for monitor in monitors:
        monitor["label"] = aliases.get(monitor["name"], {}).get(
            "label", monitor.get("description") or monitor["name"]
        )
        monitor["ddcBus"] = (
            None if is_internal(monitor["name"]) else ddc_bus(monitor["name"], aliases)
        )
    monitors.sort(key=lambda m: (bool(m.get("disabled")), m.get("x", 0), m.get("y", 0)))
    primary, external, bus = brightness_target(monitors)
    light = backlight()
    brightness_error = ""
    if external:
        value, brightness_error = ddc_brightness(bus, refresh=refresh_ddc)
        can_brighten, brightness = value is not None, value or 0
    else:
        can_brighten = light is not None
        brightness = (
            round(
                int(read(light / "brightness", "0"))
                / max(1, int(read(light / "max_brightness", "1")))
                * 100
            )
            if light
            else 0
        )
    packs = battery_details()["batteries"]
    return dict(
        hardware=hardware(),
        primary=primary,
        brightnessAvailable=can_brighten,
        brightnessError=brightness_error,
        brightness=brightness,
        ddcBuses=[int(p.name.removeprefix("i2c-")) for p in sorted(Path("/dev").glob("i2c-*"))],
        **battery_summary(packs[0] if packs else None, power_policy["backend"] == "asusd"),
        model=read("/sys/class/dmi/id/product_name", "Linux desktop"),
        profile=power_policy["profile"],
        profiles=power_policy["profiles"],
        scheduledShutdown=scheduled_shutdown(),
        asus=bool(shutil.which("asusctl")),
        hyprland=in_hyprland(),
        monitors=monitors,
    )


def set_brightness(percent):
    if not 5 <= percent <= 100:
        raise ValueError("Brightness must be between 5 and 100")
    _, external, bus = brightness_target(connected_monitors() if in_hyprland() else [])
    if external:
        if bus is None:
            raise ValueError("No DDC bus found. Choose one in Display settings.")
        command(["ddcutil", "--bus", str(int(bus)), "setvcp", "10", str(percent)], True)
        ddc_cache(bus).unlink(missing_ok=True)
        return
    light = backlight()
    if light is None:
        raise RuntimeError("No backlight device")
    if shutil.which("brightnessctl"):
        command(["brightnessctl", "-d", light.name, "set", f"{percent}%"], True)
        return
    level = max(1, round(int(read(light / "max_brightness")) * percent / 100))
    command(
        [
            "busctl",
            "--system",
            "call",
            "org.freedesktop.login1",
            "/org/freedesktop/login1/session/auto",
            "org.freedesktop.login1.Session",
            "SetBrightness",
            "ssu",
            "backlight",
            light.name,
            str(level),
        ],
        True,
    )


def action(name, value):
    if name == "profile" and value in ASUS_PROFILES:
        policy = power_status()
        if value not in policy["profiles"]:
            raise ValueError("Power profile is unavailable")
        if policy["backend"] == "asusd":
            command(["asusctl", "profile", "set", ASUS_PROFILES[value]], True)
        else:
            command(["powerprofilesctl", "set", value], True)
    elif name == "cpu-boost" and value in ("on", "off"):
        error = boost_control_error()
        if error:
            raise ValueError(error)
        command(["pkexec", str(CPU_BOOST_HELPER), "1" if value == "on" else "0"], True, 120)
    elif name == "chargeLimit":
        percent = int(value)
        if not 50 <= percent <= 100:
            raise ValueError("Charge limit must be between 50 and 100")
        if not any(pack["chargeLimitSupported"] for pack in battery_details()["batteries"]):
            raise ValueError("Charge limit is unavailable")
        if power_status()["backend"] != "asusd":
            raise ValueError("Use your system's battery charge-limit settings")
        command(["asusctl", "battery", "limit", str(percent)], True)
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
    elif name in (
        "primary",
        "display",
        "display-mode",
        "display-scale",
        "display-order",
        "display-ddc",
        "display-save",
    ):
        display_action(name, value)
    elif name == "brightness":
        set_brightness(int(value))
    elif name in ("suspend", "reboot", "poweroff"):
        command(["systemctl", name], True)
    elif name == "logout" and in_hyprland():
        managed = (
            subprocess.run(
                ["uwsm", "check", "is-active"], capture_output=True, timeout=5
            ).returncode
            == 0
        )
        command(["uwsm", "stop"] if managed else ["hyprctl", "dispatch", "hl.dsp.exit()"], True)
    else:
        raise ValueError("Unsupported action or value")
    return {"ok": True}


if __name__ == "__main__":
    try:
        operation = sys.argv[1]
        print(
            json.dumps(
                snapshot(len(sys.argv) > 2 and sys.argv[2] == "refresh")
                if operation == "snapshot"
                else battery_details()
                if operation == "battery-details"
                else action(operation, sys.argv[2] if len(sys.argv) > 2 else "")
            )
        )
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(json.dumps({"error": str(error)}))
        sys.exit(1)
