#!/usr/bin/env python3
"""Control automatic locking for the current compositor session only."""

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from services.idle import lock_on_lid, run_idle, set_paused, state


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("get", "pause", "restore", "run", "lid"))
    args = parser.parse_args()
    try:
        if args.action == "run":
            run_idle()
        elif args.action == "lid":
            lock_on_lid()
        elif args.action in ("pause", "restore"):
            print(json.dumps(set_paused(args.action == "pause")))
        else:
            print(json.dumps(state()))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(json.dumps({**state(), "error": str(error)}))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
