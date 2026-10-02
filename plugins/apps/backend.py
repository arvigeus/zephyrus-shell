"""Per-launch GPU selection using the active switcheroo-control service."""
import json
import os
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "services"))
from worker import serve

# Reset selectors inherited from an older session only for an explicit GPU launch.
GPU_ENVIRONMENT = ("DRI_PRIME", "MESA_VK_DEVICE_SELECT", "MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE",
                   "VK_LOADER_DRIVERS_SELECT", "__NV_PRIME_RENDER_OFFLOAD",
                   "__NV_PRIME_RENDER_OFFLOAD_PROVIDER", "__GLX_VENDOR_LIBRARY_NAME", "__VK_LAYER_NV_optimus")


def gpu_list():
    from gi.repository import Gio, GLib
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        result = bus.call_sync("net.hadess.SwitcherooControl", "/net/hadess/SwitcherooControl",
                               "org.freedesktop.DBus.Properties", "Get",
                               GLib.Variant("(ss)", ("net.hadess.SwitcherooControl", "GPUs")),
                               GLib.VariantType.new("(v)"), Gio.DBusCallFlags.NO_AUTO_START, 3000, None)
    except GLib.Error as error:
        raise RuntimeError("GPU choices require an active switcheroo-control service.") from error
    gpus = []
    for gpu in result.unpack()[0]:
        pairs = gpu.get("Environment", [])
        environment = dict(zip(pairs[::2], pairs[1::2]))
        if not environment:
            continue
        gpus.append({"id": json.dumps(environment, sort_keys=True), "name": gpu["Name"],
                     "default": gpu.get("Default", False), "discrete": gpu.get("Discrete", False),
                     "environment": environment})
    return sorted(gpus, key=lambda gpu: not gpu["default"])


def launch_environment(gpu, inherited):
    environment = {key: value for key, value in inherited.items() if key not in GPU_ENVIRONMENT}
    environment.update(gpu["environment"])
    # Mesa normally only reorders Vulkan devices. Explicit selection should
    # expose the chosen device alone so games cannot silently choose the other.
    prime = environment.get("DRI_PRIME", "")
    if prime and not prime.endswith("!"):
        environment["DRI_PRIME"] = prime + "!"
    return environment


def handle(request):
    if request["op"] == "gpus":
        return {"gpus": [{k: v for k, v in gpu.items() if k != "environment"} for gpu in gpu_list()]}
    if request["op"] != "launch":
        raise ValueError("Unsupported application action")
    command = request.get("command")
    if not isinstance(command, list) or not command or any(not isinstance(arg, str) or "\0" in arg for arg in command):
        raise ValueError("Application command is unavailable")
    gpu = next((gpu for gpu in gpu_list() if gpu["id"] == request.get("gpu")), None)
    if gpu is None:
        raise ValueError("The selected GPU is no longer available. Reopen Applications to refresh choices.")
    if request.get("terminal"):
        command = ["kitty", "--", *command]
    subprocess.Popen(command, cwd=request.get("directory") or None,
                     env=launch_environment(gpu, os.environ), start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True}


if __name__ == "__main__":
    serve(handle, errors=(ValueError, OSError, RuntimeError), controls=("launch",))
