#!/usr/bin/python3 -I
"""Privileged one-shot control. Install root-owned; never run repository code via pkexec."""
import json
import os
from pathlib import Path
import sys

BOOST_NODE = Path("/sys/devices/system/cpu/cpufreq/boost")


def set_boost(value):
    if value not in ("0", "1"):
        raise ValueError("CPU boost accepts only 0 or 1")
    if os.geteuid() != 0:
        raise PermissionError("CPU boost requires administrator authorization")
    if BOOST_NODE.read_text().strip() not in ("0", "1"):
        raise ValueError("The kernel does not expose a supported CPU boost switch")
    BOOST_NODE.write_text(value + "\n")
    if BOOST_NODE.read_text().strip() != value:
        raise RuntimeError("The kernel did not apply the CPU boost setting")
    return {"ok": True}


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("Usage: cpu-boost 0|1")
        print(json.dumps(set_boost(sys.argv[1])))
    except (OSError, ValueError, RuntimeError) as error:
        print(json.dumps({"error": str(error)}))
        sys.exit(1)
