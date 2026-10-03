#!/usr/bin/env python3
"""Open Kooha's native recording controls after dismissing shell overlays."""
import os
import shutil
import subprocess
import sys

from screenshot import dismiss_shell, report_error


def record():
    executable = shutil.which("kooha")
    if not executable:
        raise ValueError("Install kooha to record your screen.")
    dismiss_shell()
    # Kooha owns source selection, recording, settings and application lifetime.
    os.execv(executable, [executable])


if __name__ == "__main__":
    try:
        record()
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        report_error("Screen recording", error)
        sys.exit(1)
