#!/usr/bin/env python3
"""Open Kooha's native recording controls while keeping shell surfaces open."""
import os
import shutil
import subprocess
import sys

from screenshot import report_error


def record():
    executable = shutil.which("kooha")
    if not executable:
        raise ValueError("Install kooha to record your screen.")
    # Kooha owns source selection, recording, settings and application lifetime.
    os.execv(executable, [executable])


if __name__ == "__main__":
    try:
        record()
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        report_error("Screen recording", error)
        sys.exit(1)
